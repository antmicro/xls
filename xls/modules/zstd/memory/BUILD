# Copyright 2024 The XLS Authors
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

load("@xls_pip_deps//:requirements.bzl", "requirement")
load("@rules_hdl//place_and_route:build_defs.bzl", "place_and_route")
load("@rules_hdl//synthesis:build_defs.bzl", "benchmark_synth", "synthesize_rtl")
load("@rules_hdl//verilog:providers.bzl", "verilog_library")
load(
    "//xls/build_rules:xls_build_defs.bzl",
    "xls_benchmark_ir",
    "xls_benchmark_verilog",
    "xls_dslx_library",
    "xls_dslx_test",
    "xls_dslx_verilog",
)

package(
    default_applicable_licenses = ["//:license"],
    default_visibility = ["//xls:xls_users"],
    licenses = ["notice"],
)

xls_dslx_library(
    name = "axi_dslx",
    srcs = ["axi.x"],
)

xls_dslx_library(
    name = "axi_st_dslx",
    srcs = ["axi_st.x"],
)

xls_dslx_library(
    name = "axi_reader_dslx",
    srcs = ["axi_reader.x"],
    deps = [
        ":axi_dslx",
        ":axi_st_dslx",
    ],
)

xls_dslx_test(
    name = "axi_reader_dslx_test",
    library = ":axi_reader_dslx",
)

xls_dslx_verilog(
    name = "axi_reader_verilog",
    codegen_args = {
        "module_name": "AxiReader",
        "delay_model": "asap7",
        "pipeline_stages": "10",
        "reset": "rst",
        "use_system_verilog": "false",
        "worst_case_throughput": "1",
        "streaming_channel_data_suffix": "_data",
        "flop_inputs_kind": "skid",
        "flop_outputs_kind": "skid",
    },
    dslx_top = "AxiReaderInst",
    library = ":axi_reader_dslx",
    opt_ir_args = {
        "top": "__axi_reader__AxiReaderInst__AxiReader_0__16_32_4_4_4_3_2_14_next",
    },
    verilog_file = "axi_reader.v",
)

xls_benchmark_ir(
    name = "axi_reader_opt_ir_benchmark",
    src = ":axi_reader_verilog.opt.ir",
    benchmark_ir_args = {
        "pipeline_stages": "10",
        "delay_model": "asap7",
    },
)

verilog_library(
    name = "axi_reader_verilog_lib",
    srcs = [
        ":axi_reader.v",
    ],
)

synthesize_rtl(
    name = "axi_reader_synth_asap7",
    standard_cells = "@org_theopenroadproject_asap7sc7p5t_28//:asap7-sc7p5t_rev28_rvt",
    top_module = "AxiReader",
    deps = [
        ":axi_reader_verilog_lib",
    ],
)

benchmark_synth(
    name = "axi_reader_benchmark_synth",
    synth_target = ":axi_reader_synth_asap7",
)

place_and_route(
    name = "axi_reader_place_and_route",
    clock_period = "750",
    core_padding_microns = 2,
    min_pin_distance = "0.5",
    placement_density = "0.30",
    stop_after_step = "global_routing",
    synthesized_rtl = ":axi_reader_synth_asap7",
    target_die_utilization_percentage = "10",
)

xls_dslx_library(
    name = "axi_stream_downscaler_dslx",
    srcs = ["axi_stream_downscaler.x"],
    deps = [
        ":axi_st_dslx",
    ],
)

xls_dslx_test(
    name = "axi_stream_downscaler_dslx_test",
    library = ":axi_stream_downscaler_dslx",
)

xls_dslx_verilog(
    name = "axi_stream_downscaler_verilog",
    codegen_args = {
        "module_name": "AxiStreamDownscaler",
        "delay_model": "asap7",
        "pipeline_stages": "10",
        "reset": "rst",
        "use_system_verilog": "false",
        "worst_case_throughput": "1",
        "streaming_channel_data_suffix": "_data",
    },
    dslx_top = "AxiStreamDownscalerInst",
    library = ":axi_stream_downscaler_dslx",
    opt_ir_args = {
        "top": "__axi_stream_downscaler__AxiStreamDownscalerInst__AxiStreamDownscaler_0__8_8_128_16_32_4_4_3_next",
    },
    verilog_file = "axi_stream_downscaler.v",
)

xls_benchmark_ir(
    name = "axi_stream_downscaler_opt_ir_benchmark",
    src = ":axi_stream_downscaler_verilog.opt.ir",
    benchmark_ir_args = {
        "pipeline_stages": "10",
        "delay_model": "asap7",
    },
)

verilog_library(
    name = "axi_stream_downscaler_verilog_lib",
    srcs = [
        ":axi_stream_downscaler.v",
    ],
)

synthesize_rtl(
    name = "axi_stream_downscaler_synth_asap7",
    standard_cells = "@org_theopenroadproject_asap7sc7p5t_28//:asap7-sc7p5t_rev28_rvt",
    top_module = "AxiStreamDownscaler",
    deps = [
        ":axi_stream_downscaler_verilog_lib",
    ],
)

benchmark_synth(
    name = "axi_stream_downscaler_benchmark_synth",
    synth_target = ":axi_stream_downscaler_synth_asap7",
)

place_and_route(
    name = "axi_stream_downscaler_place_and_route",
    clock_period = "750",
    core_padding_microns = 2,
    min_pin_distance = "0.5",
    placement_density = "0.30",
    stop_after_step = "global_routing",
    synthesized_rtl = ":axi_stream_downscaler_synth_asap7",
    target_die_utilization_percentage = "10",
)

xls_dslx_library(
    name = "csr_config_dslx",
    srcs = [
        "csr_config.x",
    ],
    deps = [
        ":axi_dslx",
    ],
)

xls_dslx_test(
    name = "csr_config_dslx_test",
    library = ":csr_config_dslx",
    tags = ["manual"],
)

xls_dslx_verilog(
    name = "csr_config_verilog",
    codegen_args = {
        "module_name": "CsrConfig",
        "delay_model": "asap7",
        "pipeline_stages": "8",
        "reset": "rst",
        "use_system_verilog": "false",
    },
    dslx_top = "CsrConfigInst",
    library = ":csr_config_dslx",
    opt_ir_args = {
        "inline_procs": "true",
        "top": "__csr_config__CsrConfigInst__CsrConfig_0__2_32_4_32_4_next",
    },
    tags = ["manual"],
    verilog_file = "csr_config.v",
)

xls_benchmark_ir(
    name = "csr_config_opt_ir_benchmark",
    src = ":csr_config_verilog.opt.ir",
    benchmark_ir_args = {
        "pipeline_stages": "4",
        "delay_model": "asap7",
    },
    tags = ["manual"],
)

verilog_library(
    name = "csr_config_verilog_lib",
    srcs = [
        ":csr_config.v",
    ],
    tags = ["manual"],
)

synthesize_rtl(
    name = "csr_config_synth_asap7",
    standard_cells = "@org_theopenroadproject_asap7sc7p5t_28//:asap7-sc7p5t_rev28_rvt",
    tags = ["manual"],
    top_module = "CsrConfig",
    deps = [
        ":csr_config_verilog_lib",
    ],
)

benchmark_synth(
    name = "csr_config_benchmark_synth",
    synth_target = ":csr_config_synth_asap7",
    tags = ["manual"],
)

place_and_route(
    name = "csr_config_place_and_route",
    clock_period = "750",
    core_padding_microns = 2,
    min_pin_distance = "0.5",
    placement_density = "0.30",
    stop_after_step = "global_routing",
    synthesized_rtl = ":csr_config_synth_asap7",
    tags = ["manual"],
    target_die_utilization_percentage = "10",
)
