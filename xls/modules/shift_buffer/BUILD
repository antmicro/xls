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

# This is a pipeline-aware data buffer. The implementation aligns incoming data
# before it enters the buffer and mutates its state.

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
    name = "fixme_dslx",
    srcs = ["fixme.x"],
)

xls_dslx_test(
    name = "fixme_dslx_test",
    library = ":fixme_dslx",
)

xls_dslx_library(
    name = "math_dslx",
    srcs = ["math.x"],
    deps = [":fixme_dslx"]
)

xls_dslx_test(
    name = "math_dslx_test",
    library = ":math_dslx",
)

## ShiftBuffer

xls_dslx_library(
    name = "shift_buffer_dslx",
    srcs = ["shift_buffer.x"],
    deps = [
        ":math_dslx",
        ":fixme_dslx",
    ],
)

xls_dslx_test(
    name = "shift_buffer_dslx_test",
    library = ":shift_buffer_dslx",
)

xls_dslx_library(
    name = "shift_buffer_inst_dslx",
    srcs = ["shift_buffer_inst.x"],
    deps = [
        ":shift_buffer_dslx",
    ],
)

