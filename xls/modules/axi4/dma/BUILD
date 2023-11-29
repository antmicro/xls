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

load(
    "//xls/build_rules:xls_build_defs.bzl",
    "xls_benchmark_ir",
    "xls_dslx_ir",
    "xls_dslx_library",
    "xls_dslx_test",
    "xls_ir_opt_ir",
    "xls_ir_verilog",
)

package(
    default_applicable_licenses = ["//:license"],
    default_visibility = ["//xls:xls_users"],
    licenses = ["notice"],
)

# Common
xls_dslx_library(
    name = 'dma_common',
    srcs = [
        'axi_st.x',
        'gpf.x'
    ]
)

xls_dslx_test(
    name = "test_common",
    library = "dma_common",
)

# FIFO
xls_dslx_library(
    name = 'fifo',
    srcs = [
        'fifo.x'
    ],
    deps = [
        ':dma_common',
        '//xls/examples:ram_dslx'
    ]
)

xls_dslx_test(
    name = "test_fifo",
    library = "fifo",
)

xls_dslx_ir(
    name = "fifo_ir",
    dslx_top = "fifo_synth",
    ir_file = "fifo_ir.ir",
    library = "fifo",
)

xls_ir_opt_ir(
    name = "fifo_ir_opt",
    src = "fifo_ir.ir",
    # FIXME: Top level is not correctly generated in verilog
    top = "__fifo__fifo_synth__FIFO__Writer_0__4_8_1_1_16_1_next"
)

xls_ir_verilog(
    name = "verilog_fifo",
    src = ":fifo_ir_opt.opt.ir",
    codegen_args = {
        "module_name": "fifo",
        "delay_model": "unit",
        "pipeline_stages": "3",
        "worst_case_throughput": "2",
        "reset": "rst",
        "use_system_verilog": "false",
        # TODO: setup configuration for RAM macro generation
        # https://google.github.io/xls/codegen_options/#rams-experimental
        # https://github.com/google/xls/blob/609a7ab89d96d2a7396d2418d00d30e4cb57b119/xls/codegen/ram_configuration.h#L99
        # https://github.com/google/xls/blob/609a7ab89d96d2a7396d2418d00d30e4cb57b119/docs_src/tutorials/xlscc_memory.md?plain=1#L140
    },
    verilog_file = "fifo.v",
)
