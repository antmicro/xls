enum Status: u1 {
    A = 0,
    B = 1
}

proc DummyProc {
    channel_s: chan<Status> out;

    init {
        zero!<Status>()
    }

    config(
        channel_s: chan<Status> out
    ) {
        (channel_s,)
    }
    next(tok: token, state: Status) {
        let state = match (state) {
            Status::A => {
                Status::B
            },
            Status::B => {
                let tok = send(tok, channel_s, state);
                Status::A
            },
            _ => fail!("impossible_case", zero!<Status>())
        };
        state
    }
}

#[test_proc]
proc DummyProcTest {
    terminator: chan<bool> out;

    channel_r: chan<Status> in;

    init {}

    config(terminator: chan<bool> out) {
        let (channel_s, channel_r) = chan<Status>("channel");

        spawn DummyProc(channel_s);
        (terminator, channel_r)
    }
    next(tok: token, state: ()) {
        for (_, tok) in range(u32:0, u32:10) {
            let (tok, resp) = recv(tok, channel_r);
            assert_eq(resp, Status::B);
            tok
        }(tok);
        let tok = send(tok, terminator, true);
    }
}
