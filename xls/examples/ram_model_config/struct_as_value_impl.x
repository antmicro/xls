#![feature(type_inference_v2)]
#![feature(generics)]

// Same wrapper as struct_as_value.x, in impl style. Hypothetical: `fn new`
// spawns the old-style ram::RamModel via a classic `spawn` statement, but
// deriving `fn new`'s ProcInitializer uses an evaluator that doesn't
// support `spawn` -- unrelated to struct-as-parametric substitution. See
// struct_as_value.x for a working version of this pattern.
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

proc ConfiguredRamModel<CONFIG: RamModelConfig> {
    read_req: chan<ram::ReadReq<{std::clog2(CONFIG.size)},
        {ram::num_partitions(CONFIG.word_partition_size, CONFIG.data_width)}>> in,
    read_resp: chan<ram::ReadResp<{CONFIG.data_width}>> out,
    write_req: chan<ram::WriteReq<{std::clog2(CONFIG.size)}, {CONFIG.data_width},
        {ram::num_partitions(CONFIG.word_partition_size, CONFIG.data_width)}>> in,
    write_resp: chan<ram::WriteResp> out,
}

impl ConfiguredRamModel<CONFIG> {
    fn new(read_req: chan<ram::ReadReq<{std::clog2(CONFIG.size)},
               {ram::num_partitions(CONFIG.word_partition_size, CONFIG.data_width)}>> in,
           read_resp: chan<ram::ReadResp<{CONFIG.data_width}>> out,
           write_req: chan<ram::WriteReq<{std::clog2(CONFIG.size)}, {CONFIG.data_width},
               {ram::num_partitions(CONFIG.word_partition_size, CONFIG.data_width)}>> in,
           write_resp: chan<ram::WriteResp> out) -> Self {
        spawn ram::RamModel<
            {CONFIG.data_width}, {CONFIG.size}, {CONFIG.word_partition_size},
            {CONFIG.simultaneous_read_write_behavior}, {CONFIG.initialized}, {CONFIG.assert_valid_read}>(
            read_req, read_resp, write_req, write_resp);
        ConfiguredRamModel { read_req, read_resp, write_req, write_resp }
    }

    fn next(self) { }
}

#[test]
proc Outer {
    read_req: chan<ram::ReadReq<8, 32>> out,
    read_resp: chan<ram::ReadResp<32>> in,
    write_req: chan<ram::WriteReq<8, 32, 32>> out,
    write_resp: chan<ram::WriteResp> in,
    terminator: chan<bool> out,
}

impl Outer {
    fn new(terminator: chan<bool> out) -> Self {
        let (read_req_s, read_req_r) = chan<ram::ReadReq<8, 32>>("read_req");
        let (read_resp_s, read_resp_r) = chan<ram::ReadResp<32>>("read_resp");
        let (write_req_s, write_req_r) = chan<ram::WriteReq<8, 32, 32>>("write_req");
        let (write_resp_s, write_resp_r) = chan<ram::WriteResp>("write_resp");

        const CONFIG = RamModelConfig {
            data_width: u32:32, size: u32:256, assert_valid_read: false,
            ..DEFAULT_RAM_MODEL_CONFIG
        };
        ConfiguredRamModel<CONFIG>::new(read_req_r, read_resp_s, write_req_r, write_resp_s).spawn();
        Outer {
            read_req: read_req_s, read_resp: read_resp_r,
            write_req: write_req_s, write_resp: write_resp_r, terminator,
        }
    }

    fn next(self) {
        let tok = send(join(), self.read_req, ram::ReadWordReq<u32:32>(u8:5));
        let (tok, read_data) = recv(tok, self.read_resp);
        assert_eq(read_data.data, u32:0);
        send(tok, self.terminator, true);
    }
}
