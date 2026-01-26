proc SelArray {
  sel_r: chan<u32> in;
  array_r: chan<u32>[10] in;
  data_s: chan<u32> out;

  init { }

  config(
     sel_r: chan<u32> in,
     array_r: chan<u32>[10] in,
     data_s: chan<u32> out
  ) { (sel_r, array_r, data_s) }

  next(state: ()) {
    let (tok, sel) = recv(join(), sel_r);
    let (tok, result) = recv(tok, array_r[sel]);
    let tok = send(tok, data_s, result);
  }
}

#[test_proc]
proc SelArrayTest {
  terminator: chan<bool> out;
  sel_s: chan<u32> out;
  array_s: chan<u32>[10] out;
  data_r: chan<u32> in;

  init {}

  config(terminator: chan<bool> out) {
    let (sel_s, sel_r) = chan<u32>("sel");
    let (array_s, array_r) = chan<u32>[10]("array");
    let (data_s, data_r) = chan<u32>("data");

    spawn SelArray(sel_r, array_r, data_s);
    (terminator, sel_s, array_s, data_r)
  }

  next(state: ()) {
    let tok = send(join(), sel_s, u32:1);
    let tok = send(tok, array_s[1], u32:123);
    let (tok, data) = recv(tok, data_r);
    send(tok, terminator, true);
  }
}
