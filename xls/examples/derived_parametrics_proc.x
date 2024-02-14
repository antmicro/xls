import std;

proc derived_parametrics_proc<PARAM_B: u32, PARAM_A: u32> {
    input_r: chan<uN[PARAM_B]> in;
    output_s: chan<uN[PARAM_A]> out;

    config(
        input_r: chan<uN[PARAM_B]> in,
        output_s: chan<uN[PARAM_A]> out
    ) { (input_r, output_s) }

    init { () }

    next(tok: token, state: ()) {
        let init_data = uN[PARAM_A]:1;
        let (tok, recv_data) = recv(tok, input_r);
        let send_data = init_data + recv_data as uN[PARAM_A];
        let tok = send(tok, output_s, send_data);
    }
}

#[test_proc]
proc test_derived_parametrics_proc {
    terminator: chan<bool> out;
    data8_s: chan<u8> out;
    data32_r: chan<u32> in;

    config(terminator: chan<bool> out) {
        let (data8_s, data8_r) = chan<u8>;
        let (data32_s, data32_r) = chan<u32>;
        // spawn derived_parametrics_proc<u32:8, u32:32>(data8_r, data32_s); // <- This works
        spawn derived_parametrics_proc(data8_r, data32_s);
// Fails with error message: ~~~~~~~~~~^-----^ XlsTypeError: chan(uN[PARAM_B], dir=in) vs chan(uN[8], dir=in): Mismatch between parameter and argument types (after instantiation).
        (terminator, data8_s, data32_r)
    }

    init {}

    next(tok: token, state: ()) {
        let tok = send(tok, data8_s, u8:4);
        let tok = send(tok, data8_s, u8:3);
        let tok = send(tok, data8_s, u8:2);
        let tok = send(tok, data8_s, u8:1);
        let tok = send(tok, data8_s, u8:0);

        let (tok, received_data) = recv(tok, data32_r);
        assert_eq(received_data, u32:5);
        let (tok, received_data) = recv(tok, data32_r);
        assert_eq(received_data, u32:4);
        let (tok, received_data) = recv(tok, data32_r);
        assert_eq(received_data, u32:3);
        let (tok, received_data) = recv(tok, data32_r);
        assert_eq(received_data, u32:2);
        let (tok, received_data) = recv(tok, data32_r);
        assert_eq(received_data, u32:1);

        send(tok, terminator, true);
    }
}
