load(
    "//xls/build_rules:xls_build_defs.bzl",
    "xls_dslx_library",
    "xls_dslx_test",
    "xls_benchmark_ir",
    "xls_dslx_verilog",
)

xls_dslx_library(
    name = "window_buffer_dslx_untagged",
    srcs = [
        "//xls/modules/zstd:window_buffer.x",
    ],
    deps = [
        "//xls/modules/zstd:buffer_dslx",
    ],
)

xls_dslx_test(
    name = "window_buffer_dslx_test_untagged",
    library = ":window_buffer_dslx_untagged",
)

xls_dslx_verilog(
    name = "window_buffer_verilog_untagged",
    codegen_args = {
        "module_name": "WindowBuffer64",
        "delay_model": "asap7",
        "pipeline_stages": "2",
        "reset": "rst",
        "use_system_verilog": "false",
    },
    dslx_top = "WindowBuffer64",
    library = ":window_buffer_dslx_untagged",
    # TODO: 2024-01-25: Workaround for https://github.com/google/xls/issues/869
    # Force proc inlining and set last internal proc as top proc for IR optimization
    opt_ir_args = {
        "inline_procs": "true",
        "top": "__window_buffer__WindowBuffer64__WindowBuffer_0__64_32_48_next",
    },
    verilog_file = "window_buffer_untagged.v",
)

xls_benchmark_ir(
    name = "window_buffer_opt_ir_benchmark_untagged",
    src = ":window_buffer_verilog_untagged.opt.ir",
    benchmark_ir_args = {
        "pipeline_stages": "2",
        "delay_model": "asap7",
    },
)

xls_dslx_library(
    name = "window_buffer_dslx_tagged",
    srcs = [
        "//xls/modules/zstd:window_buffer.x",
    ],
    deps = [
        "//xls/modules/zstd:buffer_dslx",
    ],
    tags = ["manual"],
)

xls_dslx_test(
    name = "window_buffer_dslx_test_tagged",
    library = ":window_buffer_dslx_tagged",
    tags = ["manual"],
)

xls_dslx_verilog(
    name = "window_buffer_verilog_tagged",
    codegen_args = {
        "module_name": "WindowBuffer64",
        "delay_model": "asap7",
        "pipeline_stages": "2",
        "reset": "rst",
        "use_system_verilog": "false",
    },
    dslx_top = "WindowBuffer64",
    library = ":window_buffer_dslx_tagged",
    # TODO: 2024-01-25: Workaround for https://github.com/google/xls/issues/869
    # Force proc inlining and set last internal proc as top proc for IR optimization
    opt_ir_args = {
        "inline_procs": "true",
        "top": "__window_buffer__WindowBuffer64__WindowBuffer_0__64_32_48_next",
    },
    verilog_file = "window_buffer_tagged.v",
    tags = ["manual"],
)

xls_benchmark_ir(
    name = "window_buffer_opt_ir_benchmark_tagged",
    src = ":window_buffer_verilog_tagged.opt.ir",
    benchmark_ir_args = {
        "pipeline_stages": "2",
        "delay_model": "asap7",
    },
    tags = ["manual"],
)

