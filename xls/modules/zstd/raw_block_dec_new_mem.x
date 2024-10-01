// Copyright 2024 The XLS Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// This file contains the implementation of RawBlockDecoder responsible for decoding
// ZSTD Raw Blocks. More information about Raw Block's format can be found in:
// https://datatracker.ietf.org/doc/html/rfc8878#section-3.1.1.2.2

import xls.modules.zstd.common as common;
import xls.modules.zstd.memory.mem_reader as mem_reader;

type BlockDataPacket = common::BlockDataPacket;
type BlockPacketLength = common::BlockPacketLength;
type BlockData = common::BlockData;
type ExtendedBlockDataPacket = common::ExtendedBlockDataPacket;
type CopyOrMatchContent = common::CopyOrMatchContent;
type CopyOrMatchLength = common::CopyOrMatchLength;
type SequenceExecutorMessageType = common::SequenceExecutorMessageType;

pub struct RawBlockDecoderReq<ADDR_W: u32> {
    id: u32,
    addr: uN[ADDR_W],
    length: uN[ADDR_W],
    last_block: bool,
}

pub enum RawBlockDecoderStatus: u1 {
    OKAY = 0,
    ERROR = 1,
}

pub struct RawBlockDecoderResp {
    status: RawBlockDecoderStatus,
}

struct RawBlockDecoderState {
    id: u32, // ID of the block
    last_block: bool, // if the block is the last one
}

// RawBlockDecoder is responsible for decoding Raw Blocks,
// it should be a part of the ZSTD Decoder pipeline.
pub proc RawBlockDecoder<DATA_W: u32, ADDR_W: u32> {
    type Req = RawBlockDecoderReq<ADDR_W>;
    type Resp = RawBlockDecoderResp;
    type Output = ExtendedBlockDataPacket;
    type Status = RawBlockDecoderStatus;

    type MemReaderReq = mem_reader::MemReaderReq<ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<DATA_W, ADDR_W>;
    type MemReaderStatus = mem_reader::MemReaderStatus;

    type State = RawBlockDecoderState;

    // decoder input
    req_r: chan<Req> in;
    resp_s: chan<Resp> out;

    // decoder output
    output_s: chan<Output> out;

    // memory interface
    mem_req_s: chan<MemReaderReq> out;
    mem_resp_r: chan<MemReaderResp> in;

    init { zero!<State>() }

    config(
        req_r: chan<Req> in,
        resp_s: chan<RawBlockDecoderResp> out,
        output_s: chan<ExtendedBlockDataPacket> out,

        mem_req_s: chan<MemReaderReq> out,
        mem_resp_r: chan<MemReaderResp> in,
    ) {
        (
            req_r, resp_s, output_s,
            mem_req_s, mem_resp_r,
        )
    }

    next(state: State) {
        let tok0 = join();

        // receive request
        let (tok1_0, req, req_valid) = recv_non_blocking(tok0, req_r, zero!<RawBlockDecoderReq<ADDR_W>>());

        // update ID and last in state
        let state = if req_valid {
            State { id: req.id, last_block: req.last_block}
        } else { state };

        // send memory read request
        let req = MemReaderReq { addr: req.addr, length: req.length };
        let tok2_0 = send_if(tok1_0, mem_req_s, req_valid, req);

        // receive memory read response
        let (tok1_1, mem_resp, mem_resp_valid) = recv_non_blocking(tok0, mem_resp_r, zero!<MemReaderResp>());
        let mem_resp_error = (mem_resp.status != MemReaderStatus::OKAY);

        // prepare output data, decoded RAW block is always a literal
        let output_data = ExtendedBlockDataPacket {
            msg_type: SequenceExecutorMessageType::LITERAL,
            packet: BlockDataPacket {
                last: mem_resp.last,
                last_block: state.last_block,
                id: state.id,
                data: checked_cast<BlockData>(mem_resp.data),
                length: checked_cast<BlockPacketLength>(mem_resp.length),
            },
        };

        // send output data
        let mem_resp_correct = mem_resp_valid && !mem_resp_error;
        let tok2_1 = send_if(tok1_1, output_s, mem_resp_correct, output_data);

        // send response after block end
        let resp = if mem_resp_correct {
            Resp { status: Status::OKAY }
        } else {
            Resp { status: Status::ERROR }
        };

        let do_send_resp = mem_resp_valid && mem_resp.last;
        let tok2_2 = send_if(tok1_1, resp_s, do_send_resp, resp);

        state
    }
}

const INST_DATA_W = u32:32;
const INST_ADDR_W = u32:32;

pub proc RawBlockDecoderInst {
    type Req = RawBlockDecoderReq<INST_ADDR_W>;
    type Resp = RawBlockDecoderResp;
    type Output = ExtendedBlockDataPacket;

    type MemReaderReq = mem_reader::MemReaderReq<INST_ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<INST_DATA_W, INST_ADDR_W>;

    config (
        req_r: chan<Req> in,
        resp_s: chan<Resp> out,
        output_s: chan<Output> out,
        mem_req_s: chan<MemReaderReq> out,
        mem_resp_r: chan<MemReaderResp> in,
    ) {
        spawn RawBlockDecoder<INST_DATA_W, INST_ADDR_W>(
            req_r, resp_s, output_s, mem_req_s, mem_resp_r
        );
    }

    init { }

    next (state: ()) { }
}

const TEST_DATA_W = u32:32;
const TEST_ADDR_W = u32:32;

type TestReq = RawBlockDecoderReq<TEST_ADDR_W>;
type TestResp = RawBlockDecoderResp;

type TestMemReaderReq = mem_reader::MemReaderReq<TEST_ADDR_W>;
type TestMemReaderResp = mem_reader::MemReaderResp<TEST_DATA_W, TEST_ADDR_W>;

type TestData = uN[TEST_DATA_W];
type TestAddr = uN[TEST_ADDR_W];
type TestLength = uN[TEST_ADDR_W];

struct TestRecord {
     id: u32,
     addr: TestAddr,
     length: TestLength,
     data: TestData,
     last_block: bool,
 }

//const TEST_DATA = TestData[8]:[
//    TestData { id: u32:0, last_block: false,  addr: TestAddr:0,   length: TestLength:8,  data: TestData:0xAB},
//    TestData { id: u32:0, last_block: false,  addr: TestAddr:8,   length: TestLength:8,  data: TestData:0xCD},
//    TestData { id: u32:1, last_block: false,  addr: TestAddr:512, length: TestLength:32, data: TestData:0x654A_BE67},
//    TestData { id: u32:1, last_block: false,  addr: TestAddr:544, length: TestLength:32, data: TestData:0x8C45_FB09},
//    TestData { id: u32:1, last_block: false,  addr: TestAddr:576, length: TestLength:32, data: TestData:0xE92A_429D},
//    TestData { id: u32:1, last_block: false,  addr: TestAddr:592, length: TestLength:16, data: TestData:0x071F},
//    TestData { id: u32:2, last_block: false,  addr: TestAddr:32,  length: TestLength:32, data: TestData:0x1234_5678},
//    TestData { id: u32:2, last_block:  true,  addr: TestAddr:64,  length: TestLength:24, data: TestData:0xABCD_DCBA},
//];

//#[test_proc]
//proc RawBlockDecoderTest {
//    terminator: chan<bool> out;
//
//    // decoder input
//    req_s: chan<TestReq> out;
//    resp_r: chan<TestRawBlockDecoderResp> in;
//    output_r: chan<ExtendedBlockDataPacket> in;
//
//    mem_req_r: chan<TestMemReaderReq> in;
//    mem_resp_s: chan<TestMemReaderResp> out;
//
//    // decoder output
//
//    config(terminator: chan<bool> out) {
//        let (ctrl_s, ctrl_r) = chan<RawBlockDecoderCtrl>("ctrl");
//        let (req_s, req_r) = chan<TestRawBlockDecoderReq>("req");
//
//        let (mem_req_s, mem_req_r) = chan<TestMemReaderReq>("mem_req");
//        let (mem_resp_s, mem_resp_r) = chan<TestMemReaderResp>("mem_resp");
//
//        let (resp_s, resp_r) = chan<RawBlockDecoderResp>("resp");
//        let (output_s, output_r) = chan<ExtendedBlockDataPacket>("output");
//
//        spawn RawBlockDecoder<TEST_DATA_W, TEST_ADDR_W>(
//            req_r, resp_s, output_s, mem_req_s, mem_resp_r
//        );
//
//        (
//            terminator,
//            req_s, resp_r, output_r,
//            mem_req_r, mem_resp_s
//        )
//    }
//
//    init {  }
//
//    next(state: ()) {
//        let tok = join();
//
//        let req = TestReq { id: u32:0, last_block: false, addr: TestAddr:0, length: TestLength:8 };
//        let tok = send(tok, req_s, req);
//
//        let (tok, mem_req) = recv(tok, mem_req_r);
//        assert_eq(mem_req, MemReaderReq {
//            addr: TestAddr:0,
//            lenght: TestLength:8
//        });
//
//
//        let req = TestReq { id: u32:0, last_block: false, addr: TestAddr:0, length: TestLength:8 };
//
//
//        let tok = for ((i, test_data), tok): ((u32, TestData), token) in enumerate(TEST_DATA) {
//            let req = TestRawBlockDecoderReq {
//                last: test_data.last,
//                last_block: test_data.last_block,
//                id: test_data.id,
//                addr: test_data.addr,
//                length: test_data.length,
//            };
//            let tok = send(tok, req_s, req);
//            trace_fmt!("Sent #{} request {:#x}", i + u32:1, req);
//
//            let (tok, mem_req) = recv(tok, mem_req_r);
//            trace_fmt!("Received #{} memory read request {:#x}", i + u32:1, mem_req);
//
//            assert_eq(test_data.addr, mem_req.addr);
//            assert_eq(test_data.length, mem_req.length);
//
//            let mem_resp = TestMemReaderResp {
//                status: mem_reader::MemReaderStatus::OKAY,
//                data: test_data.data,
//                length: test_data.length,
//                last: true,
//            };
//
//            let tok = send(tok, mem_resp_s, mem_resp);
//            trace_fmt!("Sent #{} memory response {:#x}", i + u32:1, mem_resp);
//
//            let (tok, output) = recv(tok, output_r);
//            trace_fmt!("Received #{} output {:#x}", i + u32:1, output);
//
//            assert_eq(SequenceExecutorMessageType::LITERAL, output.msg_type);
//            assert_eq(test_data.last, output.packet.last);
//            assert_eq(test_data.last_block, output.packet.last_block);
//            assert_eq(test_data.id, output.packet.id);
//            assert_eq(test_data.data as common::BlockData, output.packet.data);
//            assert_eq(test_data.length, output.packet.length);
//
//            let (tok, _) = recv_if(tok, resp_r, test_data.last, zero!<RawBlockDecoderResp>());
//
//            tok
//        }(tok);
//
//        send(tok, terminator, true);
//    }
//}
