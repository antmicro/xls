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

cc_library(
    name = "gem5connection",
    srcs = [
        "gem5connection.cc",
    ],
    hdrs = [
        "gem5connection.h",
        "gem5api.h"
    ],
    deps = [
        "//xls/simulation/generic:iconnection",
        "//xls/simulation/generic:iperipheral",
        "//xls/simulation/generic:log_redirector",
        "//xls/simulation/generic:xlsperipheral",
        "//xls/simulation/generic:peripheral_factory",
        "@com_google_absl//absl/log",
        "@com_google_absl//absl/strings:str_format"

    ],
    alwayslink = True,
    linkstatic = True
)

cc_test(
    name = "gem5connection_test",
    size = "small",
    srcs = [
        "gem5connection_test.cc",
    ],
    deps = [
        ":gem5connection",
        "//xls/common:xls_gunit_main",
        "//xls/common/status:matchers",
        "//xls/simulation/generic:iconnection",
        "//xls/simulation/generic:iperipheral_stub",
        "//xls/simulation/generic:peripheral_factory",
        "@com_google_absl//absl/log",
        "@com_google_absl//absl/strings:str_format",
        "@com_google_googletest//:gtest",
    ],
)

cc_binary(
    name = "gem5_xls_plugin",
    linkshared = True,
    deps = [
        ":gem5connection",
    ],
)