# Build rules for the RamModel config-struct wrapper examples.

load(
    "//xls/build_rules:xls_build_defs.bzl",
    "xls_dslx_library",
    "xls_dslx_test",
)

xls_dslx_library(
    name = "old_style_dslx",
    srcs = ["old_style.x"],
    deps = ["//xls/examples:ram_dslx"],
)

xls_dslx_test(
    name = "old_style_test",
    dslx_test_args = {"compare": "jit"},
    library = ":old_style_dslx",
)

xls_dslx_library(
    name = "named_style_dslx",
    srcs = ["named_style.x"],
    deps = ["//xls/examples:ram_dslx"],
)

xls_dslx_test(
    name = "named_style_test",
    dslx_test_args = {"compare": "jit"},
    library = ":named_style_dslx",
)

xls_dslx_library(
    name = "impl_style_dslx",
    srcs = ["impl_style.x"],
    deps = ["//xls/examples:ram_dslx"],
)

# No xls_dslx_test for impl_style_dslx: its #[test] proc fails at runtime
# (UNIMPLEMENTED: BytecodeInterpreter does not support spawning procs),
# a known, unrelated impl-style limitation -- see the file's header
# comment. Would be:
#
# xls_dslx_test(
#     name = "impl_style_test",
#     dslx_test_args = {"compare": "jit"},
#     library = ":impl_style_dslx",
# )

xls_dslx_library(
    name = "trait_style_dslx",
    srcs = ["trait_style.x"],
    deps = ["//xls/examples:ram_dslx"],
)

xls_dslx_test(
    name = "trait_style_test",
    dslx_test_args = {"compare": "jit"},
    library = ":trait_style_dslx",
)
