# XLS / SPIN examples

The DSLX interpreter executes one fixed schedule per run, so it can't catch
bugs that only appear under a different interleaving of a concurrent design.
These examples translate DSLX procs to Promela and check them with SPIN
instead, which can reason about all schedules.

Two checks are available per example:

- **Trace comparison** (`*_dslx_test`, `--spin_verify`): one guided SPIN
  simulation (`spin -c`), diffed against the DSLX interpreter's trace. Can
  catch a divergence by luck, but doesn't cover every schedule.

- **Exhaustive search** (`*_pml_verify`, `spin -search`): full state-space
  search for assertion violations, deadlocks, and liveness issues. Pass/fail
  only, plus a `.trail` counterexample on failure.

## counter

`counter.x` sends incrementing u32 values on a channel. Well-behaved example
that provides the same output in DSLX and SPIN.

```
bazel test  //xls/spin/examples:counter_dslx_test    # DSLX + guided SPIN
bazel test  //xls/spin/examples:counter_pml_verify   # exhaustive SPIN state check
```

Expected result: both pass.

## order_dependence

An `Arbiter` forwards requests to two parametric `Worker` procs and collects
their responses via a `Receiver` using non-blocking receives. The two
workers run concurrently. The response the `Receiver` sees is
non-deterministic. The DSLX interpreter never notices that because it runs
the same schedule of operations. SPIN sees it both in a guided simulation
that explores interesting schedules and in the  exhaustive search.

```
bazel test  //xls/spin/examples:order_dependence_dslx_test   # DSLX + guided SPIN
bazel test  //xls/spin/examples:order_dependence_pml_verify  # exhaustive SPIN state check
```

Expected result: both fail.

`_dslx_test` reports a trace mismatch as SPIN's guided run landed on
an interleaving whose response value doesn't match the interpreter's.

`_pml_verify` reports 1 error as exhaustive search proves the
assertion fails under some schedule.

## Test artifacts

Both `_dslx_test` and `_pml_verify` write to Bazel's undeclared test outputs:

```
bazel-testlogs/xls/spin/examples/<target>/test.outputs/outputs.zip
```

- `_dslx_test`: `spin_verify/model.pml`, `spin_trace.json`,
  `dslx_trace.textproto`, `spin_output.log`.
- `_pml_verify`: the counterexample `<model>.pml.trail`, present only on
  failure. To replay it: put it alongside `<model>.pml` and run
  `spin -t -p -g <model>.pml`.
