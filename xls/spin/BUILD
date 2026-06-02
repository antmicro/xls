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

# Build rules for the XLS -> Promela code generator.
# Promela is the input language for the SPIN model checker (https://spinroot.com).

load("@rules_cc//cc:cc_test.bzl", "cc_test")

package(
    default_applicable_licenses = ["//:license"],
    default_visibility = ["//xls:xls_users"],
    licenses = ["notice"],
)

cc_library(
    name = "trace_compare",
    srcs = ["trace_compare.cc"],
    hdrs = ["trace_compare.h"],
    deps = [
        "//xls/ir",
        "//xls/ir:channel",
        "//xls/ir:evaluator_result_cc_proto",
        "@com_google_absl//absl/container:flat_hash_map",
        "@com_google_absl//absl/container:flat_hash_set",
        "@com_google_absl//absl/log",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/strings",
        "@com_google_absl//absl/strings:str_format",
        "@com_google_protobuf//:protobuf",
        "@re2",
    ],
)

cc_library(
    name = "promela_generator",
    srcs = ["promela_generator.cc"],
    hdrs = ["promela_generator.h"],
    deps = [
        "//xls/common/status:status_macros",
        "//xls/ir",
        "//xls/ir:channel",
        "//xls/ir:op",
        "//xls/ir:source_location",
        "//xls/ir:state_element",
        "//xls/ir:type",
        "//xls/ir:value",
        "@com_google_absl//absl/container:flat_hash_map",
        "@com_google_absl//absl/container:flat_hash_set",
        "@com_google_absl//absl/log",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
        "@com_google_absl//absl/strings",
        "@com_google_absl//absl/strings:str_format",
    ],
)

cc_test(
    name = "promela_generator_test",
    size = "medium",
    srcs = ["promela_generator_test.cc"],
    data = [
        "//xls/spin/testdata:assertion.ir",
        "//xls/spin/testdata:blocking_receive.ir",
        "//xls/spin/testdata:conditional_io.ir",
        "//xls/spin/testdata:conditional_io.x",
        "//xls/spin/testdata:counter.ir",
        "//xls/spin/testdata:counter.x",
        "//xls/spin/testdata:multi_proc.ir",
        "//xls/spin/testdata:non_blocking_receive.ir",
        "//xls/spin/testdata:passthrough.ir",
        "//xls/spin/testdata:func.ir",
        "//xls/spin/testdata:proc.ir",
        "//xls/spin/testdata:passthrough.x",
        "//xls/spin/testdata:predicated_receive.ir",
        "//xls/spin/testdata:predicated_send.ir",
        "//xls/spin/testdata:state_counter.ir",
        "//xls/spin/testdata:unconditional_send.ir",
        "//xls/spin/testdata:xr_xs_hints.ir",
        "//xls/spin/testdata:deadlock.ir",
        "//xls/spin/testdata:deadlock.x",
        "//xls/spin/testdata:channel_naming.x",
        "//xls/dslx:interpreter_main",
        "//xls/dslx/ir_convert:ir_converter_main",
        "//xls/tools:opt_main",
        ":promela_main",
        "@spin//:spin",
    ],
    deps = [
        ":promela_generator",
        ":trace_compare",
        "//xls/common:subprocess",
        "//xls/common:xls_gunit_main",
        "//xls/common/file:filesystem",
        "//xls/common/file:get_runfile_path",
        "//xls/common/file:temp_directory",
        "//xls/common/status:matchers",
        "//xls/ir",
        "//xls/ir:ir_test_base",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
        "@com_google_absl//absl/strings",
        "@com_google_absl//absl/strings:str_format",
        "@googletest//:gtest",
    ],
)

cc_test(
    name = "promela_spin_runner_test",
    size = "medium",
    srcs = ["promela_spin_runner_test.cc"],
    data = [
        "//xls/dslx:interpreter_main",
        "//xls/spin/testdata:deadlock.ir",
        "//xls/spin/testdata:passthrough.ir",
        "//xls/spin/testdata:passthrough.x",
        "@spin//:spin",
    ],
    deps = [
        ":promela_generator",
        ":promela_spin_runner",
        "//xls/common:subprocess",
        "//xls/common:xls_gunit_main",
        "//xls/common/file:filesystem",
        "//xls/common/file:get_runfile_path",
        "//xls/common/file:temp_directory",
        "//xls/common/status:matchers",
        "//xls/ir",
        "//xls/ir:evaluator_result_cc_proto",
        "//xls/ir:ir_test_base",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
        "@com_google_protobuf//:protobuf",
        "@googletest//:gtest",
    ],
)

cc_test(
    name = "trace_compare_test",
    srcs = ["trace_compare_test.cc"],
    deps = [
        ":trace_compare",
        "//xls/common:xls_gunit_main",
        "@googletest//:gtest",
    ],
)

cc_library(
    name = "promela_spin_runner",
    srcs = ["promela_spin_runner.cc"],
    hdrs = ["promela_spin_runner.h"],
    deps = [
        ":promela_generator",
        ":trace_compare",
        "//xls/common:subprocess",
        "//xls/common/file:filesystem",
        "//xls/common/file:get_runfile_path",
        "//xls/common/file:temp_directory",
        "//xls/common/status:status_macros",
        "//xls/dslx:create_import_data",
        "//xls/dslx:parse_and_typecheck",
        "//xls/dslx:virtualizable_file_system",
        "//xls/dslx:warning_kind",
        "//xls/dslx/frontend:proc",
        "//xls/dslx/ir_convert:ir_converter",
        "//xls/estimators",
        "//xls/ir",
        "//xls/ir:evaluator_result_cc_proto",
        "//xls/passes:optimization_pass_pipeline",
        "@com_google_absl//absl/log",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
        "@com_google_absl//absl/strings:str_format",
        "@com_google_protobuf//:protobuf",
        "@re2",
    ],
)

cc_binary(
    name = "dslx_trace_filter",
    srcs = ["dslx_trace_filter_main.cc"],
    visibility = ["//xls:xls_users"],
    deps = [
        "//xls/common:exit_status",
        "//xls/common:init_xls",
        "//xls/common/file:filesystem",
        "//xls/common/status:status_macros",
        "//xls/ir:evaluator_result_cc_proto",
        "@com_google_absl//absl/flags:flag",
        "@com_google_absl//absl/flags:parse",
        "@com_google_absl//absl/log",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/strings",
        "@com_google_absl//absl/strings:str_format",
        "@com_google_protobuf//:protobuf",
    ],
)

cc_binary(
    name = "promela_trace_compare",
    srcs = ["promela_trace_compare_main.cc"],
    visibility = ["//xls:xls_users"],
    deps = [
        ":trace_compare",
        "//xls/common:init_xls",
        "//xls/common/file:filesystem",
        "//xls/common/status:status_macros",
        "@com_google_absl//absl/flags:flag",
        "@com_google_absl//absl/flags:parse",
        "@com_google_absl//absl/status",
    ],
)

cc_binary(
    name = "promela_main",
    srcs = ["promela_main.cc"],
    visibility = ["//xls:xls_users"],
    deps = [
        ":promela_generator",
        "//xls/common:exit_status",
        "//xls/common:init_xls",
        "//xls/common/file:filesystem",
        "//xls/common/status:status_macros",
        "//xls/ir:ir_parser",
        "@com_google_absl//absl/flags:flag",
        "@com_google_absl//absl/log",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/strings",
        "@com_google_absl//absl/strings:str_format",
    ],
)
