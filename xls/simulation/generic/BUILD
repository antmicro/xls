# Copyright 2020 The XLS Authors
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

package(
    default_visibility = ["//xls:xls_internal"],
    licenses = ["notice"],  # Apache 2.0
)

proto_library(
    name = "config_proto",
    srcs = ["config.proto"],
)

cc_proto_library(
    name = "cc_config_proto",
    deps = [":config_proto"],
)

cc_library(
    name = "common",
    hdrs = [
        "common.h",
    ],
    deps = [
        "//xls/common/logging",
    ],
)

cc_library(
    name = "config",
    srcs = [
        "config.cc",
    ],
    hdrs = [
        "config.h",
    ],
    deps = [
        ":cc_config_proto",
        "//xls/common/file:filesystem",
        "//xls/common/status:status_macros",
        "@com_google_absl//absl/flags:flag",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
        "@com_google_absl//absl/strings",
    ],
)

cc_library(
    name = "iconnection",
    hdrs = [
        "iconnection.h",
    ],
    deps = [
        "@com_google_absl//absl/log",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
    ],
)

cc_library(
    name = "byteops",
    hdrs = [
        "byteops.h",
    ],
    deps = [
        "//xls/common/logging",
        "@com_google_absl//absl/types:span",
    ],
)

cc_test(
    name = "byteops_test",
    size = "small",
    srcs = [
        "byteops_test.cc",
    ],
    deps = [
        ":byteops",
        "//xls/common:xls_gunit_main",
        "//xls/common/status:matchers",
        "@com_google_absl//absl/types:span",
        "@com_google_googletest//:gtest",
    ],
)

cc_library(
    name = "ichannel",
    hdrs = [
        "ichannel.h",
    ],
    deps = [
        ":common",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
    ],
)

cc_library(
    name = "register_mock",
    hdrs = [
        "register_mock.h",
    ],
    deps = [
        ":byteops",
        ":ichannel",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
        "@com_google_absl//absl/types:span",
    ],
)

cc_test(
    name = "register_mock_test",
    size = "small",
    srcs = [
        "register_mock_test.cc",
    ],
    deps = [
        ":register_mock",
        "//xls/common:xls_gunit_main",
        "//xls/common/status:matchers",
        "@com_google_googletest//:gtest",
    ],
)

cc_library(
    name = "ir_value_common",
    srcs = [
        "ir_value_access_methods.cc",
    ],
    hdrs = [
        "ir_value_access_methods.h",
    ],
    deps = [
        "//xls/common/status:status_macros",
        "//xls/ir:value",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
    ],
)

cc_test(
    name = "ir_value_common_test",
    size = "small",
    srcs = [
        "ir_value_access_methods_test.cc",
    ],
    deps = [
        ":ir_value_common",
        "//xls/common:xls_gunit_main",
        "//xls/common/status:matchers",
        "//xls/ir:bits",
        "//xls/ir:type",
        "//xls/ir:value",
        "//xls/ir:value_utils",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
        "@com_google_googletest//:gtest",
    ],
)


cc_library(
    name = "ir_single_value",
    srcs = [
        "ir_single_value.cc",
    ],
    hdrs = [
        "ir_single_value.h",
    ],
    deps = [
        ":ichannel",
        ":ir_value_common",
        "//xls/interpreter:channel_queue",
        "//xls/ir:value_utils",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
    ],
)

cc_library(
    name = "istream",
    hdrs = [
        "istream.h",
    ],
    deps = [
        ":ichannel",
        "@com_google_absl//absl/status",
    ],
)

cc_library(
    name = "istream_mock",
    hdrs = [
        "istream_mock.h",
    ],
    deps = [
        ":istream",
        ":register_mock",
        "//xls/common/logging",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
    ],
)

cc_library(
    name = "ir_stream",
    srcs = [
        "ir_stream.cc",
    ],
    hdrs = [
        "ir_stream.h",
    ],
    deps = [
        ":ir_value_common",
        ":istream",
        "//xls/common/status:status_macros",
        "//xls/interpreter:channel_queue",
        "//xls/ir:value",
        "//xls/ir:value_utils",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
    ],
)

cc_library(
    name = "ir_axistreamlike",
    srcs = [
        "ir_axistreamlike.cc",
    ],
    hdrs = [
        "ir_axistreamlike.h",
    ],
    deps = [
        ":iaxistreamlike",
        ":ir_stream",
        ":ir_value_common",
        "//xls/interpreter:channel_queue",
        "//xls/ir:value",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
        "@com_google_absl//absl/strings:str_format",
        "@com_google_absl//absl/types:span",
    ],
)

cc_library(
    name = "ichannelmanager",
    hdrs = [
        "ichannelmanager.h",
    ],
    deps = [
        ":ichannel",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
    ],
)

cc_test(
    name = "ichannelmanager_stub_test",
    srcs = [
        "ichannelmanager_stub.cc",
        "ichannelmanager_stub.h",
        "ichannelmanager_stub_test.cc",
    ],
    deps = [
        ":ichannel",
        ":ichannelmanager",
        "//xls/common:xls_gunit_main",
        "//xls/common/logging",
        "//xls/common/logging:log_flags",
        "//xls/common/status:matchers",
        "@com_google_absl//absl/flags:flag",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
        "@com_google_googletest//:gtest",
    ],
)

cc_library(
    name = "log_redirector",
    srcs = [
        "log_redirector.cc",
    ],
    hdrs = [
        "log_redirector.h",
    ],
    deps = [
        ":iconnection",
        "//xls/common/logging",
        "//xls/common/logging:log_flags",
        "@com_google_absl//absl/log:log_entry",
        "@com_google_absl//absl/log:log_sink",
        "@com_google_absl//absl/log:log_sink_registry",
    ],
)

cc_library(
    name = "runtime_manager",
    srcs = [
        "runtime_manager.cc",
        "runtime_status.cc",
    ],
    hdrs = [
        "managed_serial_proc_runtime.h",
        "runtime_manager.h",
        "runtime_status.h",
    ],
    deps = [
        ":ichannel",
        "//xls/interpreter:interpreter_proc_runtime",
        "//xls/ir",
        "//xls/jit:jit_proc_runtime",
        "@com_google_absl//absl/container:flat_hash_map",
        "@com_google_absl//absl/memory",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
    ],
)

cc_test(
    name = "runtime_manager_test",
    srcs = [
        "runtime_manager_test.cc",
    ],
    data = [
        "//xls/simulation/generic/testdata:pasthrough_opt_ir",
    ],
    deps = [
        ":runtime_manager",
        "//xls/common:xls_gunit_main",
        "//xls/common/file:filesystem",
        "//xls/common/file:get_runfile_path",
        "//xls/common/status:matchers",
        "//xls/ir:ir_parser",
        "//xls/ir:value",
        "@com_google_googletest//:gtest",
    ],
)

cc_library(
    name = "iaxistreamlike",
    hdrs = [
        "iaxistreamlike.h",
    ],
    deps = [
        ":istream",
    ],
)

cc_library(
    name = "iperipheral",
    hdrs = [
        "iperipheral.h",
    ],
    deps = [
        ":common",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
    ],
)

cc_library(
    name = "idmaendpoint",
    hdrs = [
        "idmaendpoint.h",
    ],
    deps = [
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
    ],
)

cc_library(
    name = "singlevaluemanager",
    srcs = [
        "singlevaluemanager.cc",
    ],
    hdrs = [
        "singlevaluemanager.h",
    ],
    deps = [
        ":common",
        ":ichannel",
        ":ichannelmanager",
        "//xls/common/logging",
        "//xls/common/status:status_macros",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
    ],
)

cc_test(
    name = "ir_single_value_test",
    srcs = [
        "ir_single_value_test.cc",
    ],
    deps = [
        ":ir_single_value",
        "//xls/common:xls_gunit_main",
        "//xls/common/status:matchers",
        "//xls/interpreter:channel_queue",
        "//xls/ir",
        "//xls/ir:channel",
        "//xls/ir:ir_test_base",
        "@com_google_absl//absl/status",
    ],
)

cc_library(
    name = "streammanager",
    srcs = [
        "streammanager.cc",
    ],
    hdrs = [
        "streammanager.h",
    ],
    deps = [
        ":ichannel",
        ":ichannelmanager",
        ":istream",
        "//xls/common:bits_util",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
    ],
)

cc_test(
    name = "streammanager_test",
    srcs = [
        "streammanager_test.cc",
    ],
    deps = [
        ":common",
        ":ichannel",
        ":ichannelmanager",
        ":istream",
        ":istream_mock",
        ":streammanager",
        "//xls/common:bits_util",
        "//xls/common:xls_gunit_main",
        "//xls/common/logging",
        "//xls/common/logging:log_flags",
        "//xls/common/status:matchers",
        "@com_google_absl//absl/flags:flag",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
        "@com_google_googletest//:gtest",
    ],
)

cc_library(
    name = "streamdmaendpoint",
    srcs = [
        "stream_dma_endpoint.cc",
    ],
    hdrs = [
        "stream_dma_endpoint.h",
    ],
    deps = [
        ":idmaendpoint",
        ":istream",
        "//xls/common/logging",
        "//xls/common/status:status_macros",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
        "@com_google_absl//absl/strings:str_format",
    ],
)

cc_library(
    name = "axistreamlikedmaendpoint",
    srcs = [
        "axi_stream_like_dma_endpoint.cc",
    ],
    hdrs = [
        "axi_stream_like_dma_endpoint.h",
    ],
    deps = [
        ":iaxistreamlike",
        ":idmaendpoint",
        "//xls/common/logging",
        "//xls/common/status:status_macros",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
        "@com_google_absl//absl/strings:str_format",
    ],
)

cc_library(
    name = "streamdmachannel",
    srcs = [
        "streamdmachannel.cc",
    ],
    hdrs = [
        "streamdmachannel.h",
    ],
    deps = [
        ":common",
        ":iconnection",
        ":idmaendpoint",
        "//xls/common:bits_util",
        "//xls/common/logging",
        "//xls/common/status:status_macros",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
    ],
)

cc_library(
    name = "dmastreammanager",
    srcs = [
        "dmastreammanager.cc",
    ],
    hdrs = [
        "dmastreammanager.h",
    ],
    deps = [
        ":ichannelmanager",
        ":idmaendpoint",
        ":streamdmachannel",
        "//xls/common:bits_util",
        "//xls/common/logging",
        "//xls/common/status:status_macros",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
    ],
)

cc_library(
    name = "xlsperipheral",
    srcs = [
        "xlsperipheral.cc",
    ],
    hdrs = [
        "xlsperipheral.h",
    ],
    deps = [
        ":axistreamlikedmaendpoint",
        ":config",
        ":dmastreammanager",
        ":ichannelmanager",
        ":iconnection",
        ":iperipheral",
        ":ir_axistreamlike",
        ":ir_single_value",
        ":ir_stream",
        ":runtime_manager",
        ":singlevaluemanager",
        ":streamdmaendpoint",
        ":streammanager",
        "//xls/common/logging",
        "@com_google_absl//absl/status",
        "@com_google_absl//absl/status:statusor",
        "@com_google_absl//absl/strings:str_format",
    ],
)

cc_test(
    name = "xlsperipheral_test",
    srcs = [
        "xlsperipheral_test.cc",
    ],
    data = [
        "//xls/simulation/generic/testdata:pasthrough_opt_ir",
    ],
    deps = [
        ":xlsperipheral",
        "//xls/common:xls_gunit_main",
        "//xls/common/status:matchers",
        "@com_google_googletest//:gtest",
    ],
)

cc_library(
    name = "peripheral_factory",
    srcs = [
        "peripheral_factory.cc",
    ],
    hdrs = [
        "peripheral_factory.h",
    ],
    deps = [
        ":iconnection",
        ":iperipheral",
        ":xlsperipheral",
        "@com_google_absl//absl/status:statusor",
    ],
)
