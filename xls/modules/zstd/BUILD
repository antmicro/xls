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

load(
    "//xls/build_rules:xls_build_defs.bzl",
    "xls_dslx_library",
    "xls_dslx_test",
    "xls_dslx_ir",
)

load("//xls/build_rules:xls_macros.bzl", "xls_full_benchmark_ir_macro")
load("@rules_hdl//place_and_route:build_defs.bzl", "place_and_route")
load("@rules_hdl//synthesis:build_defs.bzl", "benchmark_synth", "synthesize_rtl")

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

# BENCHMARK RULES START
xls_dslx_library(
    name = "buffer_minimal_dslx",
    srcs = [
        "buffer_minimal.x",
    ],
)

xls_dslx_test(
    name = "buffer_minimal_dslx_test",
    library = ":buffer_minimal_dslx",
)

# BUFFER_POP
xls_dslx_ir(
    name = "buffer_minimal_pop_ir",
    dslx_top = "buffer128_pop32",
    ir_file = "buffer_minimal_pop.ir",
    library = "buffer_minimal_dslx",
)

xls_full_benchmark_ir_macro(
    name = "buffer_minimal_pop_benchmark",
    src = ":buffer_minimal_pop.ir",
    top = "__buffer_minimal__buffer128_pop32",
    codegen_args = {
        "module_name": "buffer_minimal",
        "delay_model": "asap7",
        "pipeline_stages": "1",
        "reset": "rst",
        "use_system_verilog": "false",
    },
    benchmark_ir_args = {
        "pipeline_stages": "1",
        "delay_model": "asap7",
    },
    standard_cells = "@org_theopenroadproject_asap7sc7p5t_28//:asap7-sc7p5t_rev28_rvt",
)

benchmark_synth(
    name = "buffer_minimal_pop_benchmark_synth",
    synth_target = ":buffer_minimal_pop_benchmark.default_asap7.synth",
)

place_and_route(
    name = "buffer_minimal_pop_place_and_route",
    clock_period = "750",
    core_padding_microns = 10,
    placement_density = "0.16",
    synthesized_rtl = ":buffer_minimal_pop_benchmark.default_asap7.synth",
	die_width_microns = 110,
	die_height_microns = 110,
    min_pin_distance = "0.5",
)

# BUFFER_FIXED_POP
xls_dslx_ir(
    name = "buffer_minimal_fixed_pop_ir",
    dslx_top = "buffer128_pop32_fixed",
    ir_file = "buffer_minimal_fixed_pop.ir",
    library = "buffer_minimal_dslx",
)

xls_full_benchmark_ir_macro(
    name = "buffer_minimal_fixed_pop_benchmark",
    src = ":buffer_minimal_fixed_pop.ir",
    top = "__buffer_minimal__buffer128_pop32_fixed",
    codegen_args = {
        "module_name": "buffer_minimal",
        "delay_model": "asap7",
        "pipeline_stages": "1",
        "reset": "rst",
        "use_system_verilog": "false",
    },
    benchmark_ir_args = {
        "pipeline_stages": "1",
        "delay_model": "asap7",
    },
    standard_cells = "@org_theopenroadproject_asap7sc7p5t_28//:asap7-sc7p5t_rev28_rvt",
)

benchmark_synth(
    name = "buffer_minimal_fixed_pop_benchmark_synth",
    synth_target = ":buffer_minimal_fixed_pop_benchmark.default_asap7.synth",
)

place_and_route(
    name = "buffer_minimal_fixed_pop_place_and_route",
    clock_period = "750",
    core_padding_microns = 10,
    placement_density = "0.16",
    synthesized_rtl = ":buffer_minimal_fixed_pop_benchmark.default_asap7.synth",
	die_width_microns = 110,
	die_height_microns = 110,
    min_pin_distance = "0.5",
)

# BUFFER_FIXED_POP_ORIGINAL
xls_dslx_ir(
    name = "buffer_minimal_fixed_pop_original_ir",
    dslx_top = "buffer128_pop32_fixed_original",
    ir_file = "buffer_minimal_fixed_pop_original.ir",
    library = "buffer_minimal_dslx",
)

xls_full_benchmark_ir_macro(
    name = "buffer_minimal_fixed_pop_original_benchmark",
    src = ":buffer_minimal_fixed_pop_original.ir",
    top = "__buffer_minimal__buffer128_pop32_fixed_original",
    codegen_args = {
        "module_name": "buffer_minimal",
        "delay_model": "asap7",
        "pipeline_stages": "1",
        "reset": "rst",
        "use_system_verilog": "false",
    },
    benchmark_ir_args = {
        "pipeline_stages": "1",
        "delay_model": "asap7",
    },
    standard_cells = "@org_theopenroadproject_asap7sc7p5t_28//:asap7-sc7p5t_rev28_rvt",
)

benchmark_synth(
    name = "buffer_minimal_fixed_pop_original_benchmark_synth",
    synth_target = ":buffer_minimal_fixed_pop_original_benchmark.default_asap7.synth",
)

place_and_route(
    name = "buffer_minimal_fixed_pop_original_place_and_route",
    clock_period = "750",
    core_padding_microns = 10,
    placement_density = "0.16",
    synthesized_rtl = ":buffer_minimal_fixed_pop_original_benchmark.default_asap7.synth",
	die_width_microns = 110,
	die_height_microns = 110,
    min_pin_distance = "0.5",
)

# BENCHMARK RULES END

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
