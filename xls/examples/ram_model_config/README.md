# RamModel parametric-default overrides

DSLX patterns for overriding one `ram::RamModel` parametric default without
repeating the others (issue 102991), plus the Rust patterns they're modeled
on, compared side by side.

## DSLX

| File                           | Approach                             |
|---------------------------------|---------------------------------------|
| `struct_as_value.x`             | Struct-as-value + struct-update       |
| `struct_as_value_impl.x`        | Same, written with `impl`/`fn new`    |
| `trait_bound_generics.x`        | Trait-bound generics                  |
| `named_parametric_overrides.x`  | Named parametric arguments            |

```
bazel test //xls/examples/ram_model_config:named_parametric_overrides_test
```

(`struct_as_value_impl.x` has no test target -- see its header comment.
`named_parametric_overrides.x` needs the experimental named parametric
arguments feature; the other two are usable DSLX today.)

## Rust reference

`rust_reference/` -- plain reference code, not built by this workspace.

```
make -C rust_reference run
```
