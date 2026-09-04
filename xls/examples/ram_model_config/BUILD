# Build rules for the RamModel parametric-default-override examples.
#
# See README.md for what each style demonstrates. rust_reference/ holds
# reference Rust code only -- not built by this workspace.

load(
    "//xls/build_rules:xls_build_defs.bzl",
    "xls_dslx_library",
    "xls_dslx_test",
)

xls_dslx_library(
    name = "struct_as_value_dslx",
    srcs = ["struct_as_value.x"],
    deps = ["//xls/examples:ram_dslx"],
)

xls_dslx_test(
    name = "struct_as_value_test",
    dslx_test_args = {"compare": "jit"},
    library = ":struct_as_value_dslx",
)

xls_dslx_library(
    name = "struct_as_value_impl_dslx",
    srcs = ["struct_as_value_impl.x"],
    deps = ["//xls/examples:ram_dslx"],
)

# No xls_dslx_test for struct_as_value_impl_dslx: its #[test] proc fails at
# runtime (UNIMPLEMENTED: BytecodeInterpreter does not support spawning
# procs), a known, unrelated impl-style limitation -- see the file's header
# comment. Would be:
#
# xls_dslx_test(
#     name = "struct_as_value_impl_test",
#     dslx_test_args = {"compare": "jit"},
#     library = ":struct_as_value_impl_dslx",
# )

xls_dslx_library(
    name = "trait_bound_generics_dslx",
    srcs = ["trait_bound_generics.x"],
    deps = ["//xls/examples:ram_dslx"],
)

xls_dslx_test(
    name = "trait_bound_generics_test",
    dslx_test_args = {"compare": "jit"},
    library = ":trait_bound_generics_dslx",
)

xls_dslx_library(
    name = "named_parametric_overrides_dslx",
    srcs = ["named_parametric_overrides.x"],
    deps = ["//xls/examples:ram_dslx"],
)

xls_dslx_test(
    name = "named_parametric_overrides_test",
    dslx_test_args = {"compare": "jit"},
    library = ":named_parametric_overrides_dslx",
)
