import std;

fn derived_parametrics_fn<PARAM_A: u32, PARAM_B: u32>(arg: uN[PARAM_B]) -> uN[PARAM_A] {
    let var = uN[PARAM_A]:1;
    var + arg as uN[PARAM_A]
}

#[test]
fn test_derived_parametrics_fn() {
    assert_eq(u32:5, derived_parametrics_fn<u32:32>(u8:4));
}
