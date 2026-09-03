#![feature(type_inference_v2)]
#![feature(traits)]
#![feature(generics)]

// Realistic-scale exercise of a proc generic over an unconstrained
// `<T: type>` bound to a struct implementing a trait: multiple associated
// consts (including an enum-typed one), read both in channel types and in
// a spawn's parametric argument list, plus a proc-body const derived from
// them. Covers both a struct that overrides every const (`WideRam`) and one
// that overrides none, relying entirely on the trait's defaults
// (`SmallRam`).
import std;
import xls.examples.ram;

trait RamConfig {
    const DATA_WIDTH: u32 = u32:32;
    const SIZE: u32 = u32:256;
    const WORD_PARTITION_SIZE: u32 = u32:1;
    const SIMULTANEOUS_READ_WRITE_BEHAVIOR: ram::SimultaneousReadWriteBehavior =
        ram::SimultaneousReadWriteBehavior::READ_BEFORE_WRITE;
    const INITIALIZED: bool = false;
    const ASSERT_VALID_READ: bool = false;
}

// Overrides every const.
struct WideRam {}
impl RamConfig for WideRam {
    const DATA_WIDTH = u32:128;
    const SIZE = u32:4096;
    const WORD_PARTITION_SIZE = u32:8;
    const SIMULTANEOUS_READ_WRITE_BEHAVIOR = ram::SimultaneousReadWriteBehavior::WRITE_BEFORE_READ;
}

// Overrides none; every const falls back to the trait's default.
struct SmallRam {}
impl RamConfig for SmallRam {}

pub proc ConfiguredRamModel<T: type> {
    const ADDR_WIDTH = std::clog2(T::SIZE);
    const NUM_PARTITIONS = ram::num_partitions(T::WORD_PARTITION_SIZE, T::DATA_WIDTH);

    read_req: chan<ram::ReadReq<ADDR_WIDTH, NUM_PARTITIONS>> in;
    read_resp: chan<ram::ReadResp<T::DATA_WIDTH>> out;
    write_req: chan<ram::WriteReq<ADDR_WIDTH, T::DATA_WIDTH, NUM_PARTITIONS>> in;
    write_resp: chan<ram::WriteResp> out;

    config(read_req: chan<ram::ReadReq<ADDR_WIDTH, NUM_PARTITIONS>> in,
           read_resp: chan<ram::ReadResp<T::DATA_WIDTH>> out,
           write_req: chan<ram::WriteReq<ADDR_WIDTH, T::DATA_WIDTH, NUM_PARTITIONS>> in,
           write_resp: chan<ram::WriteResp> out) {
        spawn ram::RamModel<
            T::DATA_WIDTH, T::SIZE, T::WORD_PARTITION_SIZE,
            T::SIMULTANEOUS_READ_WRITE_BEHAVIOR, T::INITIALIZED, T::ASSERT_VALID_READ,
            ADDR_WIDTH, NUM_PARTITIONS>(read_req, read_resp, write_req, write_resp);
        (read_req, read_resp, write_req, write_resp)
    }
    init { () }
    next(state: ()) { () }
}

#[test_proc]
proc OverrideCase {
    read_req: chan<ram::ReadReq<12, 16>> out;
    read_resp: chan<ram::ReadResp<128>> in;
    write_req: chan<ram::WriteReq<12, 128, 16>> out;
    write_resp: chan<ram::WriteResp> in;
    terminator: chan<bool> out;

    config(terminator: chan<bool> out) {
        let (read_req_s, read_req_r) = chan<ram::ReadReq<12, 16>>("read_req");
        let (read_resp_s, read_resp_r) = chan<ram::ReadResp<128>>("read_resp");
        let (write_req_s, write_req_r) = chan<ram::WriteReq<12, 128, 16>>("write_req");
        let (write_resp_s, write_resp_r) = chan<ram::WriteResp>("write_resp");
        spawn ConfiguredRamModel<WideRam>(read_req_r, read_resp_s, write_req_r, write_resp_s);
        (read_req_s, read_resp_r, write_req_s, write_resp_r, terminator)
    }

    init { () }

    next(state: ()) {
        let tok = send(join(), write_req, ram::WriteWordReq<16, 12, 128>(u12:5, uN[128]:0xAB));
        let (tok, _) = recv(tok, write_resp);
        let tok = send(tok, read_req, ram::ReadWordReq<16, 12>(u12:5));
        let (tok, read_data) = recv(tok, read_resp);
        assert_eq(read_data.data, uN[128]:0xAB);
        let tok = send(tok, terminator, true);
    }
}

#[test_proc]
proc FallbackCase {
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
        spawn ConfiguredRamModel<SmallRam>(read_req_r, read_resp_s, write_req_r, write_resp_s);
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
