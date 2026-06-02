# XLS Spin / Promela Integration

## Overview

DSLX procs communicate over channels and may use bounded FIFOs,
`recv_non_blocking`, `send_if`/`recv_if` predicates, peek operations, and
shared-state channels. These constructs make correctness dependent on execution
ordering: deadlocks, livelocks, assertion violations, and race conditions can
only surface under specific interleavings that a sequential interpreter does not
explore.

This toolset translates XLS IR to [Promela](https://spinroot.com) and runs the
SPIN model checker, which exhaustively searches all possible execution
interleavings of the generated model. `PromelaGenerator::Generate(Package*)`
maps each XLS `Proc` to a Promela `proctype`, functions to `inline`s, and
channels to bounded `chan` declarations. A trace-comparison layer
(`trace_compare`) normalises and diffs per-channel event sequences from the
DSLX interpreter and from SPIN to surface any divergence.

## Directory layout

| File / dir | Role |
|---|---|
| `promela_generator.h/.cc` | Core IR -> Promela translator (`PromelaGenerator::Generate`) |
| `promela_spin_runner.h/.cc` | Library pipeline: DSLX source or IR `Package*` -> SPIN verification |
| `trace_compare.h/.cc` | Parse and compare SPIN / DSLX channel-event traces |
| `promela_main.cc` | Tool: reads `.ir`, emits `.pml` |
| `dslx_trace_filter_main.cc` | Tool: re-encode DSLX trace values |
| `promela_trace_compare_main.cc` | Tool: compare two trace files |
| `defs.bzl` | Public Bazel rules (see below) |
| `testdata/` | `.ir` / `.x` fixtures; golden IR diff tests in `testdata/BUILD` |
| `examples/` | DSLX proc examples with full target suites via `promela_targets()` |

## Generating and running Promela

The pipeline is: DSLX -> IR -> optimised IR -> Promela -> SPIN. To generate
Promela from an IR file directly:

```bash
bazelisk run //xls/spin:promela_main -- --output=/tmp/out.pml path/to/my.ir
```

To run SPIN on the generated model:

```bash
spin -c -Q /tmp/spin_trace.json /tmp/out.pml  # guided simulation + channel trace
spin -search /tmp/out.pml                       # exhaustive state-space search
```

The rules in `defs.bzl` automate the full pipeline:

| Rule | What it does |
|---|---|
| `xls_ir_spin` | IR -> Promela build action |
| `xls_dslx_spin` | DSLX -> IR -> opt -> Promela build action |
| `spin_run` | `spin -c` guided simulation (`bazel run`) |
| `spin_test` | `spin -search` exhaustive verification (`bazel test`) |

## Coverage

Use `bazelisk coverage` with `--instrumentation_filter` scoped to the generator
library to avoid instrumenting all transitive dependencies:

```bash
bazelisk coverage //xls/spin:promela_generator_test \
  --instrumentation_filter=//xls/spin:promela_generator \
  --combined_report=lcov
```

For line-level HTML output, export from the LLVM profdata Bazel writes under
the test-log directory:

```bash
PROFDATA=bazel-out/k8-fastbuild/testlogs/xls/spin/promela_generator_test/coverage.dat
TEST_BIN=bazel-bin/xls/spin/promela_generator_test
SOLIB=bazel-bin/xls/spin/libpromela_generator.so

llvm-cov-19 export \
  --format=lcov \
  --object="$TEST_BIN" \
  --object="$SOLIB" \
  --sources "$(pwd)/xls/spin/promela_generator.cc" \
  --instr-profile="$PROFDATA" > /tmp/spin_pg.lcov

# Fix the /proc/self/cwd prefix embedded by llvm-cov.
sed -i "s|SF:/proc/self/cwd/|SF:$(pwd)/|g" /tmp/spin_pg.lcov

genhtml /tmp/spin_pg.lcov \
  --output-directory /tmp/spin_coverage_html \
  --title "promela_generator.cc coverage" \
  --demangle-cpp \
  --ignore-errors unsupported

xdg-open /tmp/spin_coverage_html/index.html
```

Prerequisites: `sudo apt install lcov llvm-19`.
