#![feature(type_inference_v2)]
#![feature(traits)]
#![feature(generics)]

// Same wrapper as old_style.x, using a trait-bound generic instead of a
// struct-valued parametric: each config is its own type implementing the
// trait, and only overridden consts need restating -- no struct-update
// splat needed, since unmentioned consts just fall back to the trait's
// own defaults.
//
// Unlike old_style.x, channel types here are inlined directly rather than
// declared via a proc-scope `type` alias (e.g. `type ReadRespT = ...`).
// Aliasing a plain bits-like type built from T::CONST works; aliasing a
// parametric struct type (like `ram::ReadReq<...>`) does not yet -- the
// same T::CONST gets resolved under two different, inconsistent contexts
// depending on which resolution attempt reaches it, and the wrong one can
// win. Not a limitation of the pattern itself, just of this one
// intermediate form of writing it.
import std;
import xls.examples.ram;

trait RamModelConfig {
    const DATA_WIDTH: u32 = u32:0;
    const SIZE: u32 = u32:0;
    const WORD_PARTITION_SIZE: u32 = u32:1;
    const SIMULTANEOUS_READ_WRITE_BEHAVIOR: ram::SimultaneousReadWriteBehavior =
        ram::SimultaneousReadWriteBehavior::READ_BEFORE_WRITE;
    const INITIALIZED: bool = false;
    const ASSERT_VALID_READ: bool = true;
}

struct DemoConfig {}
impl RamModelConfig for DemoConfig {
    const DATA_WIDTH = u32:32;
    const SIZE = u32:256;
    const ASSERT_VALID_READ = false;
}

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
            {T::DATA_WIDTH}, {T::SIZE}, {T::WORD_PARTITION_SIZE},
            {T::SIMULTANEOUS_READ_WRITE_BEHAVIOR}, {T::INITIALIZED}, {T::ASSERT_VALID_READ}>(
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
        spawn ConfiguredRamModel<DemoConfig>(read_req_r, read_resp_s, write_req_r, write_resp_s);
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
