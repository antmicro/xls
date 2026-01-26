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
# Build rules for XLS examples.

load(
    "//xls/build_rules:xls_build_defs.bzl",
    "cc_xls_ir_jit_wrapper",
    "xls_benchmark_ir",
    "xls_dslx_fmt_test",
    "xls_dslx_ir",
    "xls_dslx_library",
    "xls_dslx_opt_ir",
    "xls_dslx_opt_ir_test",
    "xls_dslx_prove_quickcheck_test",
    "xls_dslx_test",
    "xls_dslx_verilog",
    "xls_eval_ir_test",
    "xls_ir_opt_ir",
    "xls_ir_verilog",
)
package(
    default_applicable_licenses = ["//:license"],
    default_visibility = ["//xls:xls_internal"],
    features = [
        "layering_check",
        "parse_headers",
    ],
    licenses = ["notice"],
)

xls_dslx_library(
    name = "enumerate_dslx",
    srcs = ["enumerate.x"],
)

xls_dslx_test(
    name = "enumerate_dslx_test",
    library = ":enumerate_dslx"
)

xls_dslx_verilog(
    name = "enumerate_verilog",
    codegen_args = {
        "module_name": "my_enumerate",
        "delay_model": "unit",
        "pipeline_stages": "1",
        "reset": "rst",
    },
    dslx_top = "my_enumerate",
    library = ":enumerate_dslx",
    verilog_file = "enumerate.sv",
)

xls_dslx_library(
    name = "token_order_dslx",
    srcs = ["token_order.x"],
)

xls_dslx_test(
    name = "token_order_dslx_test",
    library = ":token_order_dslx"
)

xls_dslx_verilog(
    name = "token_order_verilog",
    codegen_args = {
        "module_name": "TokenOrder",
        "delay_model": "unit",
        "pipeline_stages": "2",
        "reset": "rst",
    },
    dslx_top = "TokenOrder",
    library = "token_order_dslx",
    verilog_file = "token_order.sv",
)

xls_dslx_library(
    name = "sel_array_dslx",
    srcs = ["sel_array.x"],
)

xls_dslx_test(
    name = "sel_array_dslx_test",
    library = "sel_array_dslx"
)


xls_dslx_verilog(
    name = "sel_array_verilog",
    codegen_args = {
        "module_name": "SelArray",
        "delay_model": "unit",
        "pipeline_stages": "2",
        "reset": "rst",
    },
    dslx_top = "SelArray",
    library = "sel_array_dslx",
    verilog_file = "sel_array.sv",
)

