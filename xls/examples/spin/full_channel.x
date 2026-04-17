proc Counter {
    data_s: chan<u32> out;

    config(data_s: chan<u32> out) { (data_s,) }

    init { u32:0 }

    next(cnt: u32) {
        let tok = send(join(), data_s, cnt);
        cnt + u32:1
    }
}

#[test_proc]
proc CounterTest {
    terminator: chan<bool> out;
    data_s: chan<u32> out;
    data_r: chan<u32> in;

    config(terminator: chan<bool> out) {
        let (data_s, data_r) = chan<u32>("data");
        spawn Counter(data_s);
        (terminator, data_s, data_r)
    }

    init { () }

    next(state: ()) {
        const for (_, expected) in u32:0..u32:32 {
            let (tok, value) = recv(join(), data_r);
            assert_eq(value, expected);
            value + u32:1
        }(u32:0);
        let tok = send(join(), terminator, true);
    }
}

proc SlowReceiver {
    req_r:  chan<u32> in;
    resp_s: chan<u32> out;

    config(
        req_r: chan<u32> in,
        resp_s: chan<u32> out
    ) {
        (req_r, resp_s)
    }

    init { false }

    next(state: bool) {
        let tok = join();

        let (tok, val) = recv_if(join(), req_r, state, zero!<u32>());
        let tok = send_if(tok, resp_s, state, val);

        !state
    }
}

#[test_proc]
proc SlowReceiverTest {
    terminator: chan<bool> out;

    req_s:  chan<u32> out;
    resp_r: chan<u32> in;

    config(terminator: chan<bool> out) {
        let (req_s, req_r) = chan<u32>("req");
        let (resp_s, resp_r) = chan<u32>("resp");
        spawn SlowReceiver(req_r, resp_s);

        (terminator, req_s, resp_r)
    }

    init { }

    next (state: ()) {
        let tok = send(join(), req_s, u32:1);
        let (tok, _) = recv(tok, resp_r);

        let tok = send(tok, req_s, u32:2);
        let (tok, _) = recv(tok, resp_r);

        let tok = send(tok, req_s, u32:3);
        let (tok, _) = recv(tok, resp_r);

        let tok = send(tok, req_s, u32:4);
        let (tok, _) = recv(tok, resp_r);

        let tok = send(join(), terminator, true);
    }
}

