# Copyright 2026 The XLS Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Bazel rules for XLS -> SPIN model-checker integration.

Public rules:
  xls_dslx_spin  -- generate a SPIN model from a DSLX source file (build action)
  xls_ir_spin    -- generate a SPIN model from an XLS IR file      (build action)
  spin_run       -- interactive simulation: prints the execution trace to stdout;
                    use for exploration and debugging               (bazel run)
  spin_test      -- exhaustive state-space search; fails the test if SPIN reports
                    a deadlock, assertion violation, or liveness violation
                                                                   (bazel test)

Internal rules and macros are in //xls/spin:priv-defs.bzl.
"""

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(
    "//xls/build_rules:xls_ir_rules.bzl",
    "xls_dslx_ir_attrs",
    "xls_dslx_ir_impl",
    "xls_ir_opt_ir_attrs",
    "xls_ir_opt_ir_impl",
)
load("//xls/build_rules:xls_toolchains.bzl", "xls_toolchain_attrs")


# Attrs shared by xls_ir_spin and xls_dslx_spin.
_promela_attrs = {
    "emit_source_locations": attr.bool(
        default = False,
        doc = "Annotate each Promela statement with a /* filename:line:col */ " +
              "comment derived from the XLS IR source location.",
    ),
    "emit_source_hints": attr.bool(
        default = False,
        doc = "Annotate each Promela statement with a /* ir: <node-expr> */ " +
              "comment showing the original IR operation.",
    ),
    "channel_depth": attr.int(
        default = 8,
        doc = "Buffer depth for every declared Promela channel " +
              "(chan x = [N] of {T}). Defaults to 8.",
    ),
    "emit_termination_hook": attr.bool(
        default = False,
        doc = "Append a blocking receive on the terminator channel to " +
              "the init block so the simulation trace shows test completion.",
    ),
    "assert_send_on_full_channel": attr.bool(
        default = False,
        doc = "Prefix every send with assert(len(ch) < DEPTH). " +
              "Turns a blocked-on-full-channel situation into an explicit " +
              "SPIN assertion violation during exhaustive verification.",
    ),
    "worst_case_throughput": attr.string_dict(
        default = {},
        doc = "Per-proc worst-case throughput: maps a sanitised Promela " +
              "proctype name to N (string). The proc does useful work at " +
              "most once every N loop iterations; all other iterations are " +
              "idle stalls. Procs not listed run every iteration (N=1).",
    ),
    "emit_progress_labels": attr.bool(
        default = False,
        doc = "Prefix each channel send/receive with a SPIN progress label " +
              "(progress_recv_<chan>: or progress_send_<chan>:). " +
              "Use with spin -search -DNP to detect livelocks.",
    ),
    "_promela_main": attr.label(
        default = Label("//xls/spin:promela_main"),
        executable = True,
        cfg = "exec",
    ),
}

def _xls_ir_spin_impl(ctx):
    out = ctx.actions.declare_file(ctx.label.name + ".pml")
    args = ["--output=" + out.path]
    if ctx.attr.emit_source_locations:
        args.append("--emit_source_locations")
    if ctx.attr.emit_source_hints:
        args.append("--emit_source_hints")
    args.append("--channel_depth=" + str(ctx.attr.channel_depth))
    if ctx.attr.emit_termination_hook:
        args.append("--emit_termination_hook")
    if ctx.attr.assert_send_on_full_channel:
        args.append("--assert_send_on_full_channel")
    if ctx.attr.worst_case_throughput:
        args.append("--worst_case_throughput=" + ",".join([
            k + ":" + v
            for k, v in ctx.attr.worst_case_throughput.items()
        ]))
    if ctx.attr.emit_progress_labels:
        args.append("--emit_progress_labels")
    args.append(ctx.file.src.path)
    ctx.actions.run(
        executable = ctx.executable._promela_main,
        arguments = args,
        inputs = [ctx.file.src],
        outputs = [out],
        mnemonic = "IrToPromela",
        progress_message = "Generating Promela from %{input}",
    )
    return [DefaultInfo(files = depset([out]))]

xls_ir_spin = rule(
    implementation = _xls_ir_spin_impl,
    attrs = dicts.add(
        {
            "src": attr.label(
                allow_single_file = [".ir"],
                mandatory = True,
                doc = "XLS IR source file.",
            ),
        },
        _promela_attrs,
    ),
    doc = "Generates a SPIN Promela model from an XLS IR file.",
)

def _xls_dslx_spin_impl(ctx):
    # Step 1: DSLX -> IR - fully delegated to the standard XLS implementation.
    ir_file_info, _dslx_info, ir_conv_info, _ir_files, _runfiles = (
        xls_dslx_ir_impl(ctx)
    )

    # Step 2 (optional): IR -> optimised IR.
    if ctx.attr.opt:
        opt_ir_file_info, _opt_info, _opt_files, _opt_runfiles = xls_ir_opt_ir_impl(
            ctx,
            ir_file_info,
            ir_conv_info.original_input_files,
        )
        ir_for_promela = opt_ir_file_info
    else:
        ir_for_promela = ir_file_info

    # Step 3: IR -> Promela
    pml_out = ctx.actions.declare_file(ctx.label.name + ".pml")
    args = ["--output=" + pml_out.path]
    if ctx.attr.emit_source_locations:
        args.append("--emit_source_locations")
    if ctx.attr.emit_source_hints:
        args.append("--emit_source_hints")
    args.append("--channel_depth=" + str(ctx.attr.channel_depth))
    if ctx.attr.emit_termination_hook:
        args.append("--emit_termination_hook")
    if ctx.attr.assert_send_on_full_channel:
        args.append("--assert_send_on_full_channel")
    if ctx.attr.worst_case_throughput:
        args.append("--worst_case_throughput=" + ",".join([
            k + ":" + v
            for k, v in ctx.attr.worst_case_throughput.items()
        ]))
    if ctx.attr.emit_progress_labels:
        args.append("--emit_progress_labels")
    args.append(ir_for_promela.ir_file.path)
    ctx.actions.run(
        executable = ctx.executable._promela_main,
        inputs = [ir_for_promela.ir_file],
        outputs = [pml_out],
        arguments = args,
        mnemonic = "IrToPromela",
        progress_message = "Generating Promela from IR: %{input}",
    )

    return [DefaultInfo(files = depset([pml_out]))]

_xls_dslx_spin_attrs = dicts.add(
    {k: v for k, v in xls_dslx_ir_attrs.items() if k != "ir_conv_args"},
    xls_ir_opt_ir_attrs,
    {
        "ir_conv_args": attr.string_dict(
            default = {"lower_to_proc_scoped_channels": "true", "convert_tests": "true"},
            doc = "Arguments forwarded to ir_converter_main. " +
                  "lower_to_proc_scoped_channels defaults to 'true'; " +
                  "promela_main requires proc-scoped channels.",
        ),
        "opt": attr.bool(
            default = True,
            doc = "Run IR optimisation before Promela generation (default True). " +
                  "Set to False to use the raw unoptimised IR.",
        ),
    },
    _promela_attrs,
    dicts.pick(xls_toolchain_attrs, ["_xls_ir_converter_tool", "_xls_opt_ir_tool"]),
)

xls_dslx_spin = rule(
    implementation = _xls_dslx_spin_impl,
    attrs = _xls_dslx_spin_attrs,
    doc = """\
Converts a DSLX source file to a SPIN Promela model in one step.

Follows the same combined-rule convention as xls_dslx_opt_ir: the DSLX->IR
step is handled by xls_dslx_ir_impl; by default the IR is then optimised via
xls_ir_opt_ir_impl before being passed to promela_main.  Set opt = False to
skip optimisation and use the raw IR directly.

Example:
    xls_dslx_spin(
        name = "my_proc_pml",
        srcs = ["my_proc.x"],
        dslx_top = "MyProc",
    )
""",
)

def _spin_run_impl(ctx):
    script = ctx.actions.declare_file(ctx.label.name + "_runner.sh")
    ctx.actions.write(
        output = script,
        is_executable = True,
        content = "\n".join([
            "#!/usr/bin/env bash",
            "set -e",
            "{spin} {args} {src} \"$@\"".format(
                spin = ctx.executable._spin.short_path,
                args = " ".join(ctx.attr.spin_args),
                src = ctx.file.src.short_path,
            ),
            "exit 0",
        ]),
    )
    return [DefaultInfo(
        executable = script,
        runfiles = ctx.runfiles(files = [ctx.executable._spin, ctx.file.src]),
    )]

spin_run = rule(
    implementation = _spin_run_impl,
    executable = True,
    attrs = {
        "src": attr.label(
            allow_single_file = [".pml"],
            mandatory = True,
            doc = "Promela source file.",
        ),
        "spin_args": attr.string_list(
            default = ["-c"],
            doc = "Flags forwarded to spin before the model path (default: -c).",
        ),
        "_spin": attr.label(
            default = Label("@spin//:spin"),
            executable = True,
            cfg = "target",
        ),
    },
    doc = "Runs an interactive SPIN simulation trace on a Promela model (`bazel run`).",
)


def _spin_verify_impl(ctx):
    trail_name = ctx.file.src.basename + ".trail"
    script = ctx.actions.declare_file(ctx.label.name + "_runner.sh")
    # SPIN may exit 0 even on a violation; parse "errors: N" from its output.
    # Copy any .trail file to $TEST_UNDECLARED_OUTPUTS_DIR for Bazel to preserve.
    ctx.actions.write(
        output = script,
        is_executable = True,
        content = "\n".join([
            "#!/usr/bin/env bash",
            "OUTPUT=$({spin} {args} {src} \"$@\" 2>&1)".format(
                spin = ctx.executable._spin.short_path,
                args = " ".join(ctx.attr.spin_args),
                src = ctx.file.src.short_path,
            ),
            "echo \"$OUTPUT\"",
            "if [ -f \"{trail}\" ] && [ -n \"$TEST_UNDECLARED_OUTPUTS_DIR\" ]; then".format(trail = trail_name),
            "  cp \"{trail}\" \"$TEST_UNDECLARED_OUTPUTS_DIR/\"".format(trail = trail_name),
            "fi",
            "ERRORS=$(echo \"$OUTPUT\" | grep -oP 'errors:\\s+\\K[0-9]+' || echo 0)",
            "if [ \"$ERRORS\" -gt 0 ]; then",
            "  echo \"SPIN verification FAILED: $ERRORS error(s) found\" >&2",
            "  exit 1",
            "fi",
            "exit 0",
        ]),
    )
    runfiles = ctx.runfiles(files = [ctx.executable._spin, ctx.file.src])
    return [DefaultInfo(executable = script, runfiles = runfiles)]

spin_test = rule(
    implementation = _spin_verify_impl,
    test = True,
    attrs = {
        "src": attr.label(
            allow_single_file = [".pml"],
            mandatory = True,
            doc = "Promela source file.",
        ),
        "spin_args": attr.string_list(
            default = ["-search"],
            doc = "Flags forwarded to spin before the model path (default: -search).",
        ),
        "_spin": attr.label(
            default = Label("@spin//:spin"),
            executable = True,
            cfg = "target",
        ),
    },
    doc = """\
Exhaustive SPIN verification as a Bazel test.

The test fails if SPIN reports any errors (deadlocks, assertion violations,
or liveness violations).  When SPIN finds an error it writes a counterexample
.trail file; this is automatically preserved as a Bazel undeclared test output
and can be retrieved from:

  bazel-testlogs/.../<target>/test.outputs/outputs.zip

Replay the counterexample:

  unzip -p bazel-testlogs/.../<target>/test.outputs/outputs.zip > model.trail
  spin -t -p -g model.pml   # requires model.trail alongside model.pml

To detect livelocks in addition to deadlocks, pass -DNP:

  spin_test(
      name = "my_verify",
      src  = ":my_pml",
      spin_args = ["-search", "-DNP"],
  )
""",
)
