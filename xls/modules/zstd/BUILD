# Copyright 2023 The XLS Authors
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

# Build rules for XLS ZSTD codec implementation.

load("@rules_hdl//verilog:providers.bzl", "verilog_library")
load("@rules_hdl//synthesis:build_defs.bzl", "benchmark_synth", "synthesize_rtl")
load("@rules_hdl//static_timing:build_defs.bzl", "run_opensta")
load("@rules_hdl//place_and_route:build_defs.bzl", "place_and_route")
load("@rules_hdl//gds_write:build_defs.bzl", "gds_write")

load(
    "//xls/build_rules:xls_build_defs.bzl",
    "xls_dslx_library",
    "xls_dslx_test",
    "xls_dslx_ir",
    "xls_ir_opt_ir",
    "xls_ir_verilog",
    "xls_ir_opt_verilog_packer",
    "xls_benchmark_verilog",
)

package(
    default_applicable_licenses = ["//:license"],
    default_visibility = ["//xls:xls_users"],
    licenses = ["notice"],
)

xls_dslx_library(
    name = "buffer_dslx",
    srcs = [
        "buffer.x",
    ],
)

xls_dslx_test(
    name = "buffer_dslx_test",
    library = ":buffer_dslx",
)

xls_dslx_library(
    name = "magic_dslx",
    srcs = [
        "magic.x",
    ],
    deps = [
        ":buffer_dslx",
    ],
)

xls_dslx_test(
    name = "magic_dslx_test",
    library = ":magic_dslx",
)

cc_library(
    name = "data_generator",
    srcs = ["data_generator.cc"],
    hdrs = ["data_generator.h"],
    data = [
        "@com_github_facebook_zstd//:decodecorpus",
    ],
    deps = [
        "//xls/common:subprocess",
        "//xls/common/file:filesystem",
        "//xls/common/file:get_runfile_path",
        "//xls/common/status:status_macros",
        "//xls/ir",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
        "@com_google_absl//absl/time",
        "@com_google_absl//absl/types:span",
    ],
)

xls_dslx_library(
    name = "frame_header_dslx",
    srcs = [
        "frame_header.x",
    ],
    deps = [
        ":buffer_dslx",
    ],
)

#xls_dslx_ir(
#    name = "zstd_dec_ir",
#    dslx_top = "ZstdDecoder",
#    library = "zstd_dec_dslx",
#)
#
#xls_ir_opt_ir(
#    name = "zstd_dec_ir_opt",
#    src = ":zstd_dec_ir.ir",
#)
#
#xls_ir_verilog(
#    name = "zstd_dec_verilog",
#    src = ":zstd_dec_ir_opt.opt.ir",
#    codegen_args = {
#        "delay_model": "asap7",
#        "pipeline_stages": "2",
#        "reset": "rst",
#        "use_system_verilog": "false",
#        "flop_inputs": "true",
#        "flop_inputs_kind": "skid",
#        "flop_outputs": "true",
#        "flop_outputs_kind": "skid",
#        "top": "__zstd_dec__ZstdDecoder_0_next",
#    },
#    verilog_file = "zstd_dec.v"
#)
#
#xls_ir_opt_verilog_packer(
#    name = "zstd_dec_packed",
#    OptIR = ":zstd_dec_ir_opt",
#    Verilog = ":zstd_dec_verilog"
#)
#
#xls_benchmark_verilog(
#    name = "zstd_dec_benchmark",
#    verilog_target = "zstd_dec_packed"
#)
#
#verilog_library(
#    name = "zstd_dec_verilog_lib",
#    srcs = [":zstd_dec.v"],
#)
#
#synthesize_rtl(
#    name = "zstd_dec_synth",
#    standard_cells = "@org_theopenroadproject_asap7sc7p5t_27//:asap7-sc7p5t_rev27_rvt",
#    top_module = "__zstd_dec__ZstdDecoder_0_next",
#    deps = [":zstd_dec_verilog_lib"],
#)
#
#run_opensta(
#    name = "zstd_dec_benchmark_synth",
#    synth_target = ":zstd_dec_synth",
#    tags = ["manual"],
#)
#
#place_and_route(
#    name = "zstd_dec_PnR",
#    clock_period = "5000.0",
#    core_padding_microns = 0,
#    die_width_microns = 200,
#    die_height_microns = 200,
#    placement_density = "0.16",
#    synthesized_rtl = ":zstd_dec_synth",
#)
#
#gds_write(
#    name = "zstd_dec_gds",
#    implemented_rtl = ":zstd_dec_PnR",
#)

xls_dslx_library(
    name = "common_dslx",
    srcs = [
        "common.x",
    ],
    deps = [],
)

xls_dslx_test(
    name = "frame_header_dslx_test",
    library = ":frame_header_dslx",
)

xls_dslx_library(
    name = "frame_header_test_dslx",
    srcs = [
        "frame_header_test.x",
    ],
    deps = [
        ":buffer_dslx",
        ":frame_header_dslx",
    ],
)

cc_test(
    name = "frame_header_cc_test",
    srcs = [
        "frame_header_test.cc",
    ],
    data = [
        ":frame_header_test_dslx",
    ],
    shard_count = 50,
    deps = [
        ":data_generator",
        "//xls/common:xls_gunit",
        "//xls/common:xls_gunit_main",
        "//xls/common/file:filesystem",
        "//xls/common/file:get_runfile_path",
        "//xls/common/status:matchers",
        "//xls/dslx:create_import_data",
        "//xls/dslx:import_data",
        "//xls/dslx:interp_value",
        "//xls/dslx:parse_and_typecheck",
        "//xls/dslx/ir_convert:ir_converter",
        "//xls/dslx/type_system:parametric_env",
        "//xls/ir",
        "//xls/ir:ir_parser",
        "//xls/ir:ir_test_base",
        "@com_github_facebook_zstd//:zstd",
        "@com_google_absl//absl/container:flat_hash_map",
        "@com_google_googletest//:gtest",
    ],
)

xls_dslx_library(
    name = "raw_block_dec_dslx",
    srcs = [
        "raw_block_dec.x",
    ],
    deps = [
        ":buffer_dslx",
        ":common_dslx",
    ],
)

xls_dslx_test(
    name = "raw_block_dec_dslx_test",
    library = ":raw_block_dec_dslx",
)

xls_dslx_library(
    name = "rle_block_dec_dslx",
    srcs = [
        "rle_block_dec.x",
    ],
    deps = [
        ":buffer_dslx",
        ":common_dslx",
        "//xls/modules/rle:rle_common_dslx",
        "//xls/modules/rle:rle_dec_dslx",
    ],
)

xls_dslx_test(
    name = "rle_block_dec_dslx_test",
    library = ":rle_block_dec_dslx",
)

xls_dslx_library(
    name = "block_header_dslx",
    srcs = [
        "block_header.x",
    ],
    deps = [
        ":buffer_dslx",
        ":common_dslx",
    ],
)

xls_dslx_test(
    name = "block_header_dslx_test",
    library = ":block_header_dslx",
)

xls_dslx_library(
    name = "dec_mux_dslx",
    srcs = [
        "dec_mux.x",
    ],
    deps = [
        ":buffer_dslx",
        ":common_dslx",
    ],
)

xls_dslx_test(
    name = "dec_mux_dslx_test",
    library = ":dec_mux_dslx",
)

xls_dslx_library(
    name = "dec_demux_dslx",
    srcs = [
        "dec_demux.x",
    ],
    deps = [
        ":common_dslx",
        ":block_header_dslx",
    ],
)

xls_dslx_test(
    name = "dec_demux_dslx_test",
    library = ":dec_demux_dslx",
)

xls_dslx_ir(
    name = "dec_demux_dslx_ir",
    dslx_top = "DecoderDemux",
    library = "dec_demux_dslx",
)

xls_ir_opt_ir(
    name = "dec_demux_dslx_ir_opt",
    src = "dec_demux_dslx_ir.ir",
)

xls_ir_verilog(
    name = "dec_demux_dslx_verilog",
    src = ":dec_demux_dslx_ir_opt.opt.ir",
    codegen_args = {
        "delay_model": "asap7",
        "pipeline_stages": "2",
        "reset": "rst",
        "use_system_verilog": "false",
        "flop_inputs": "true",
        "flop_inputs_kind": "skid",
        "flop_outputs": "true",
        "flop_outputs_kind": "skid",
        "top": "__dec_demux__DecoderDemux_0_next",
    },
    verilog_file = "dec_demux_dslx.v",
)

xls_ir_opt_verilog_packer(
    name = "dec_demux_dslx_packed",
    OptIR = ":dec_demux_dslx_ir_opt",
    Verilog = ":dec_demux_dslx_verilog"
)

xls_benchmark_verilog(
    name = "dec_demux_dslx_benchmark",
    verilog_target = "dec_demux_dslx_packed"
)

verilog_library(
    name = "dec_demux_dslx_verilog_lib",
    srcs = [":dec_demux_dslx.v"],
)

synthesize_rtl(
    name = "dec_demux_dslx_synth",
    standard_cells = "@org_theopenroadproject_asap7sc7p5t_28//:asap7-sc7p5t_rev28_rvt",
    top_module = "__dec_demux__DecoderDemux_0_next",
    deps = [":dec_demux_dslx_verilog_lib"],
)

run_opensta(
    name = "dec_demux_dslx_benchmark_synth",
    synth_target = "dec_demux_dslx_synth",
    tags = ["manual"],
)

place_and_route(
    name = "dec_demux_dslx_PnR",
    clock_period = "2500.0",
    core_padding_microns = 0,
    die_width_microns = 200,
    die_height_microns = 200,
    placement_density = "0.16",
    synthesized_rtl = ":dec_demux_dslx_synth",
)

gds_write(
    name = "dec_demux_dslx_gds",
    implemented_rtl = ":dec_demux_dslx_PnR",
)

xls_dslx_library(
    name = "block_dec_dslx",
    srcs = [
        "block_dec.x",
    ],
    deps = [
        ":common_dslx",
        ":dec_demux_dslx",
        ":raw_block_dec_dslx",
        ":rle_block_dec_dslx",
        ":dec_mux_dslx",
    ],
)

xls_dslx_test(
    name = "block_dec_dslx_test",
    library = ":block_dec_dslx",
)
