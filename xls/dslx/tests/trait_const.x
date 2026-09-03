#![feature(type_inference_v2)]
#![feature(traits)]

// A trait's associated `const`s must carry a value (unlike Rust, which
// allows a bare `const FOO: u32;` declaration): DSLX's `ConstantDef` has no
// representation for "declared but valueless" the way `Function` does for a
// stub body. So instead the trait's const value is a *default* -- exactly
// like Rust's optional `trait Foo { const BAR: u32 = 5; }` form, just
// mandatory here. An implementing struct's `impl SomeTrait for SomeStruct`
// may override any subset of the trait's consts with its own; whichever it
// doesn't override fall back to the trait's default.
trait RamConfig {
    const DATA_WIDTH: u32 = u32:32;
    const SIZE: u32 = u32:256;
}

// Overrides both consts.
struct WideRam {}
impl RamConfig for WideRam {
    const DATA_WIDTH = u32:128;
    const SIZE = u32:4096;
}

// Overrides only SIZE; DATA_WIDTH falls back to the trait's default.
struct SmallRam {}
impl RamConfig for SmallRam {
    const SIZE = u32:64;
}

#[test]
fn test_full_override() {
    assert_eq(WideRam::DATA_WIDTH, u32:128);
    assert_eq(WideRam::SIZE, u32:4096);
}

#[test]
fn test_partial_override_falls_back_to_default() {
    assert_eq(SmallRam::DATA_WIDTH, u32:32);  // trait default, not overridden
    assert_eq(SmallRam::SIZE, u32:64);  // overridden
}
