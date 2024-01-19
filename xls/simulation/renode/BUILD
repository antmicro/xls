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

cc_library(
    name = "renode_protocol",
    hdrs = [
        "renode_protocol.h",
    ],
    deps = [
        "@renode//:renode_base",
    ],
)

cc_library(
    name = "renode_protocol_native",
    hdrs = [
        "renode_protocol_native.h",
    ],
    deps = [
        ":renode_protocol",
    ],
)

cc_library(
    name = "sharedlibconnection",
    srcs = [
        "sharedlibconnection.cc",
    ],
    hdrs = [
        "sharedlibconnection.h",
    ],
    deps = [
        ":renode_protocol",
        ":renode_protocol_native",
        "//xls/common/logging",
        "//xls/common/status:ret_check",
        "//xls/simulation/generic:iconnection",
        "//xls/simulation/generic:iperipheral",
        "//xls/simulation/generic:log_redirector",
        "//xls/simulation/generic:peripheral_factory",
        "@com_google_absl//absl/log",
    ],
    alwayslink = True,
)

# Main output of this project - a VerilatedPeripheral plugin, a shared
# library that can be loaded by Renode.
cc_binary(
    name = "renode_xls_peripheral_plugin",
    linkshared = True,
    deps = [
        ":sharedlibconnection",
    ],
)
