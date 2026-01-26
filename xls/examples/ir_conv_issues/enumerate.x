fn my_enumerate(x: u32) -> u32 {
  const ARRAY = u32[5]:[u32:5, u32:10, u32:15, u32:20, u32:25];
  for ((i, elem), acc): ((u32, u32), u32) in enumerate(ARRAY) {
    trace_fmt!("{}: {}", i, elem);
    elem + acc
  }(x)
}

#[test]
fn my_enumerate_test() {
    my_enumerate(u32:5);
}
