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
