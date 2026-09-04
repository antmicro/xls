#![feature(type_inference_v2)]

// Demonstrates overriding the same 3 `ram::RamModel` parametrics as
// old_style.x/impl_style.x (data_width, size, assert_valid_read), but
// directly at the spawn site via named parametric arguments -- no
// `RamModelConfig` struct or `ConfiguredRamModel` wrapper proc needed.
// `WORD_PARTITION_SIZE`, `SIMULTANEOUS_READ_WRITE_BEHAVIOR`, and
// `INITIALIZED` are left at their declared defaults.
import xls.examples.ram;

#[test_proc]
proc Outer {
    read_req: chan<ram::ReadReq<8, 32>> out;
    read_resp: chan<ram::ReadResp<32>> in;
    write_req: chan<ram::WriteReq<8, 32, 32>> out;
    write_resp: chan<ram::WriteResp> in;
    terminator: chan<bool> out;

    config(terminator: chan<bool> out) {
        let (read_req_s, read_req_r) = chan<ram::ReadReq<8, 32>>("read_req");
        let (read_resp_s, read_resp_r) = chan<ram::ReadResp<32>>("read_resp");
        let (write_req_s, write_req_r) = chan<ram::WriteReq<8, 32, 32>>("write_req");
        let (write_resp_s, write_resp_r) = chan<ram::WriteResp>("write_resp");

        spawn ram::RamModel<DATA_WIDTH = u32:32, SIZE = u32:256, ASSERT_VALID_READ = false>(
            read_req_r, read_resp_s, write_req_r, write_resp_s);
        (read_req_s, read_resp_r, write_req_s, write_resp_r, terminator)
    }

    init { () }

    next(state: ()) {
        let tok = send(join(), read_req, ram::ReadWordReq<u32:32>(u8:5));
        let (tok, read_data) = recv(tok, read_resp);
        assert_eq(read_data.data, u32:0);
        let tok = send(tok, terminator, true);
    }
}
