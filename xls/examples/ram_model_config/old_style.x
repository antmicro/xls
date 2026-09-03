#![feature(type_inference_v2)]

// Wraps xls.examples.ram::RamModel in a single config struct, so any one
// parametric can be overridden via struct update regardless of position.
import std;
import xls.examples.ram;

pub struct RamModelConfig {
    data_width: u32,
    size: u32,
    word_partition_size: u32,
    simultaneous_read_write_behavior: ram::SimultaneousReadWriteBehavior,
    initialized: bool,
    assert_valid_read: bool,
}

pub const DEFAULT_RAM_MODEL_CONFIG = RamModelConfig {
    data_width: u32:0,
    size: u32:0,
    word_partition_size: u32:1,
    simultaneous_read_write_behavior: ram::SimultaneousReadWriteBehavior::READ_BEFORE_WRITE,
    initialized: false,
    assert_valid_read: true,
};

pub proc ConfiguredRamModel<CONFIG: RamModelConfig> {
    const ADDR_WIDTH = std::clog2(CONFIG.size);
    const NUM_PARTITIONS = ram::num_partitions(CONFIG.word_partition_size, CONFIG.data_width);
    type ReadReqT = ram::ReadReq<ADDR_WIDTH, NUM_PARTITIONS>;
    type ReadRespT = ram::ReadResp<{CONFIG.data_width}>;
    type WriteReqT = ram::WriteReq<ADDR_WIDTH, {CONFIG.data_width}, NUM_PARTITIONS>;
    type WriteRespT = ram::WriteResp;

    read_req: chan<ReadReqT> in;
    read_resp: chan<ReadRespT> out;
    write_req: chan<WriteReqT> in;
    write_resp: chan<WriteRespT> out;

    config(read_req: chan<ReadReqT> in, read_resp: chan<ReadRespT> out,
           write_req: chan<WriteReqT> in, write_resp: chan<WriteRespT> out) {
        spawn ram::RamModel<
            {CONFIG.data_width}, {CONFIG.size}, {CONFIG.word_partition_size},
            {CONFIG.simultaneous_read_write_behavior}, {CONFIG.initialized}, {CONFIG.assert_valid_read}>(
            read_req, read_resp, write_req, write_resp);
        (read_req, read_resp, write_req, write_resp)
    }

    init { () }

    next(state: ()) { () }
}

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

        const CONFIG = RamModelConfig {
            data_width: u32:32, size: u32:256, assert_valid_read: false,
            ..DEFAULT_RAM_MODEL_CONFIG
        };
        spawn ConfiguredRamModel<CONFIG>(read_req_r, read_resp_s, write_req_r, write_resp_s);
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
