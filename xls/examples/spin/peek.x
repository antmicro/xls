#![feature(type_inference_v2)]

proc Peek {
    req_r: chan<u32> in;
    resp_s: chan<u32> out;

    init { }

    config(
        req_r: chan<u32> in,
        resp_s: chan<u32> out
    ) {
        (req_r, resp_s)
    }

    next(state: ()) {
        const PACKET_THRESHOLD = u32:10;

        let (tok, peeked_val) = peek(join(), req_r);
        let should_process = peeked_val >= PACKET_THRESHOLD;

        let (tok, val) = recv_if(tok, req_r, should_process, zero!<u32>());
        send(tok, resp_s, val);
    }
}

#[test_proc]
proc PeekTest {
    req_s: chan<u32> out;
    resp_r: chan<u32> in;
    terminator: chan<bool> out;

    config(terminator: chan<bool> out) {
        let (req_s, req_r) = chan<u32>("req");
        let (resp_s, resp_r) = chan<u32>("resp");
        spawn Peek(req_r, resp_s);

        (req_s, resp_r, terminator)
    }

    init {  }

    next(_: ()) {
        const FIRST_PACKET_DATA = u32:15;
        let tok = send(join(), req_s, FIRST_PACKET_DATA);
        let (tok, packet) = recv(tok, resp_r);
        assert_eq(packet, FIRST_PACKET_DATA);

        const SECOND_PACKET_DATA = u32:3;
        let tok = send(tok, req_s, SECOND_PACKET_DATA);
        let (tok, packet) = recv(tok, resp_r);
        assert_eq(packet, u32:0);

        send(tok, terminator, true);
    }
}
