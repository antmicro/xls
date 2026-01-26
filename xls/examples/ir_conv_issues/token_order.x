proc TokenOrder {
  req1_r: chan<u32> in;
  resp1_s: chan<u32> out;
  req2_r: chan<u32> in;
  resp2_s: chan<u32> out;

  init {}

  config(
    req1_r: chan<u32> in,
    resp1_s: chan<u32> out,
    req2_r: chan<u32> in,
    resp2_s: chan<u32> out
  ) {
    (req1_r, resp1_s, req2_r, resp2_s)
  }

  next (state: ()) {
    let tok0 = join();
    let (tok1, data0) = recv(tok0, req1_r);
    let tok2 = send(tok1, resp1_s, data0);
    let (tok1, data1) = recv(tok2, req2_r);
    let tok2 = send(tok1, resp2_s, data1);
  }
}

#[test_proc]
proc TokenOrderTest {
  terminator: chan<bool> out;
  req1_s: chan<u32> out;
  resp1_r: chan<u32> in;
  req2_s: chan<u32> out;
  resp2_r: chan<u32> in;

  init {}

  config(
    terminator: chan<bool> out
  ) {
    let (req1_s, req1_r) = chan<u32>("req1");
    let (resp1_s, resp1_r) = chan<u32>("resp1");
    let (req2_s, req2_r) = chan<u32>("req2");
    let (resp2_s, resp2_r) = chan<u32>("resp2");

    spawn TokenOrder(req1_r, resp1_s, req2_r, resp2_s);
    (
      terminator,
      req1_s, resp1_r,
      req2_s, resp2_r
    )
  }

  next (state: ()) {
    let tok = send(join(), req1_s, u32:1);
    let (tok, data) = recv(tok, resp1_r);

    let tok = send(tok, req2_s, u32:2);
    let (tok, data) = recv(tok, resp2_r);

    send(tok, terminator, true);
  }
}
