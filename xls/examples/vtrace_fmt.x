fn vtrace_fmt_example(a: u32, b: u32) -> u32 {
    vtrace_fmt!(u32:0, "Verbosity level 0");
    vtrace_fmt!(u32:10, "Verbosity level 10");
    a + b
}

#[test]
fn example_test() {
    assert_eq(vtrace_fmt_example(u32:1, u32:2), u32:3);
}

