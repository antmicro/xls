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
    last: bool,
    last_block: bool,
    id: u32,
    addr: uN[ADDR_W],
    length: uN[ADDR_W],
}

pub enum RawBlockDecoderStatus: u1 {
    OKAY = 0,
    ERROR = 1,
}

pub struct RawBlockDecoderCtrl { }

pub struct RawBlockDecoderResp {
    status: RawBlockDecoderStatus,
}

struct RawBlockDecoderState {
    ctrl: RawBlockDecoderCtrl, // configuration data
    id: u32, // ID of the block
    last: bool, // if the packet was the last one that makes up the whole block
    last_block: bool, // if the block is the last one
    prev_valid: bool, // if prev_id and prev_last contain valid data
}

// RawBlockDecoder is responsible for decoding Raw Blocks,
// it should be a part of the ZSTD Decoder pipeline.
pub proc RawBlockDecoder<DATA_W: u32, ADDR_W: u32> {
    type Req = RawBlockDecoderReq<ADDR_W>;
    type MemReaderReq = mem_reader::MemReaderReq<ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<DATA_W, ADDR_W>;

    type State = RawBlockDecoderState;

    // decoder input
    ctrl_r: chan<RawBlockDecoderCtrl> in;
    req_r: chan<Req> in;

    // memory interface
    mem_req_s: chan<MemReaderReq> out;
    mem_resp_r: chan<MemReaderResp> in;

    // decoder output
    resp_s: chan<RawBlockDecoderResp> out;
    output_s: chan<ExtendedBlockDataPacket> out;

    init { zero!<State>() }

    config(
        ctrl_r: chan<RawBlockDecoderCtrl> in,
        req_r: chan<Req> in,
        mem_req_s: chan<MemReaderReq> out,
        mem_resp_r: chan<MemReaderResp> in,
        resp_s: chan<RawBlockDecoderResp> out,
        output_s: chan<ExtendedBlockDataPacket> out,
    ) {
        (
            ctrl_r, req_r,
            mem_req_s, mem_resp_r,
            resp_s, output_s,
        )
    }

    next(state: State) {
        let tok = join();

        // receive configuration data
        let (tok, ctrl, ctrl_valid) = recv_non_blocking(tok, ctrl_r, zero!<RawBlockDecoderCtrl>());

        let state = if ctrl_valid {
            State {
                ctrl: ctrl,
                ..state
            }
        } else { state };

        // receive request
        let (tok, req, req_valid) = recv_non_blocking(tok, req_r, zero!<RawBlockDecoderReq<ADDR_W>>());

        // validate request
        if req_valid && state.prev_valid && (req.id != state.id) && (state.last == false) {
            trace_fmt!("ID changed but previous packet have no last!");
            fail!("no_last", ());
        } else {};

        // update ID and last in state
        let state = if req_valid {
            State {
                prev_valid: true,
                id: req.id,
                last: req.last,
                last_block: req.last_block,
                ..state
            }
        } else { state };

        // send memory read request
        let tok = send_if(tok, mem_req_s, req_valid, MemReaderReq {
            addr: req.addr,
            length: req.length,
        });

        // receive memory read response
        let (tok, mem_resp, mem_resp_valid) = recv_non_blocking(tok, mem_resp_r, zero!<MemReaderResp>());

        // prepare output data
        let output_data = ExtendedBlockDataPacket {
            // Decoded RAW block is always a literal
            msg_type: SequenceExecutorMessageType::LITERAL,
            packet: BlockDataPacket {
                last: state.last,
                last_block: state.last_block,
                id: state.id,
                data: mem_resp.data as BlockData,
                length: mem_resp.length as BlockPacketLength,
            },
        };

        // send output data
        let tok = send_if(tok, output_s, mem_resp_valid, output_data);

        // send response after block end
        let tok = send_if(tok, resp_s, state.last, RawBlockDecoderResp {
            status: RawBlockDecoderStatus::OKAY,
        });

        state
    }
}

const INST_DATA_W = u32:32;
const INST_ADDR_W = u32:32;

pub proc RawBlockDecoderInst {
    type InstRawBlockDecoderReq = RawBlockDecoderReq<INST_ADDR_W>;

    type InstMemReaderReq = mem_reader::MemReaderReq<INST_ADDR_W>;
    type InstMemReaderResp = mem_reader::MemReaderResp<INST_DATA_W, INST_ADDR_W>;

    config (
        ctrl_r: chan<RawBlockDecoderCtrl> in,
        req_r: chan<InstRawBlockDecoderReq> in,
        mem_req_s: chan<InstMemReaderReq> out,
        mem_resp_r: chan<InstMemReaderResp> in,
        resp_s: chan<RawBlockDecoderResp> out,
        output_s: chan<ExtendedBlockDataPacket> out,
    ) {
        spawn RawBlockDecoder<INST_DATA_W, INST_ADDR_W>(
            ctrl_r, req_r,
            mem_req_s, mem_resp_r,
            resp_s, output_s,
        );
    }

    init { }

    next (state: ()) { }
}

const TEST_DATA_W = u32:32;
const TEST_ADDR_W = u32:32;

type TestRawBlockDecoderReq = RawBlockDecoderReq<TEST_ADDR_W>;

type TestMemReaderReq = mem_reader::MemReaderReq<TEST_ADDR_W>;
type TestMemReaderResp = mem_reader::MemReaderResp<TEST_DATA_W, TEST_ADDR_W>;

struct TestData {
    last: bool,
    last_block: bool,
    id: u32,
    addr: uN[TEST_ADDR_W],
    length: uN[TEST_ADDR_W],
    data: uN[TEST_DATA_W],
}

const TEST_DATA = TestData[8]:[
    TestData {last: false, last_block: false, id: u32:0, addr: uN[TEST_ADDR_W]:0, length: uN[TEST_ADDR_W]:8, data: uN[TEST_DATA_W]:0xAB},
    TestData {last: true, last_block: false, id: u32:0, addr: uN[TEST_ADDR_W]:8, length: uN[TEST_ADDR_W]:8, data: uN[TEST_DATA_W]:0xCD},
    TestData {last: false, last_block: false, id: u32:1, addr: uN[TEST_ADDR_W]:512, length: uN[TEST_ADDR_W]:32, data: uN[TEST_DATA_W]:0x654A_BE67},
    TestData {last: false, last_block: false, id: u32:1, addr: uN[TEST_ADDR_W]:544, length: uN[TEST_ADDR_W]:32, data: uN[TEST_DATA_W]:0x8C45_FB09},
    TestData {last: false, last_block: false, id: u32:1, addr: uN[TEST_ADDR_W]:576, length: uN[TEST_ADDR_W]:32, data: uN[TEST_DATA_W]:0xE92A_429D},
    TestData {last: true, last_block: false, id: u32:1, addr: uN[TEST_ADDR_W]:592, length: uN[TEST_ADDR_W]:16, data: uN[TEST_DATA_W]:0x071F},
    TestData {last: false, last_block: false, id: u32:2, addr: uN[TEST_ADDR_W]:32, length: uN[TEST_ADDR_W]:32, data: uN[TEST_DATA_W]:0x1234_5678},
    TestData {last: true, last_block: true, id: u32:2, addr: uN[TEST_ADDR_W]:64, length: uN[TEST_ADDR_W]:24, data: uN[TEST_DATA_W]:0xABCD_DCBA},
];

#[test_proc]
proc RawBlockDecoderTest {
    terminator: chan<bool> out;

    // decoder input
    ctrl_s: chan<RawBlockDecoderCtrl> out;
    req_s: chan<TestRawBlockDecoderReq> out;

    // memory interface
    mem_req_r: chan<TestMemReaderReq> in;
    mem_resp_s: chan<TestMemReaderResp> out;

    // decoder output
    resp_r: chan<RawBlockDecoderResp> in;
    output_r: chan<ExtendedBlockDataPacket> in;

    config(terminator: chan<bool> out) {
        let (ctrl_s, ctrl_r) = chan<RawBlockDecoderCtrl>("ctrl");
        let (req_s, req_r) = chan<TestRawBlockDecoderReq>("req");

        let (mem_req_s, mem_req_r) = chan<TestMemReaderReq>("mem_req");
        let (mem_resp_s, mem_resp_r) = chan<TestMemReaderResp>("mem_resp");

        let (resp_s, resp_r) = chan<RawBlockDecoderResp>("resp");
        let (output_s, output_r) = chan<ExtendedBlockDataPacket>("output");

        spawn RawBlockDecoder<TEST_DATA_W, TEST_ADDR_W>(
            ctrl_r, req_r,
            mem_req_s, mem_resp_r,
            resp_s, output_s,
        );

        (
            terminator,
            ctrl_s, req_s,
            mem_req_r, mem_resp_s,
            resp_r, output_r,
        )
    }

    init {  }

    next(state: ()) {
        let tok = join();

        let tok = for ((i, test_data), tok): ((u32, TestData), token) in enumerate(TEST_DATA) {
            let req = TestRawBlockDecoderReq {
                last: test_data.last,
                last_block: test_data.last_block,
                id: test_data.id,
                addr: test_data.addr,
                length: test_data.length,
            };
            let tok = send(tok, req_s, req);
            trace_fmt!("Sent #{} request {:#x}", i + u32:1, req);

            let (tok, mem_req) = recv(tok, mem_req_r);
            trace_fmt!("Received #{} memory read request {:#x}", i + u32:1, mem_req);

            assert_eq(test_data.addr, mem_req.addr);
            assert_eq(test_data.length, mem_req.length);

            let mem_resp = TestMemReaderResp {
                status: mem_reader::MemReaderStatus::OKAY,
                data: test_data.data,
                length: test_data.length,
                last: true,
            };

            let tok = send(tok, mem_resp_s, mem_resp);
            trace_fmt!("Sent #{} memory response {:#x}", i + u32:1, mem_resp);

            let (tok, output) = recv(tok, output_r);
            trace_fmt!("Received #{} output {:#x}", i + u32:1, output);

            assert_eq(SequenceExecutorMessageType::LITERAL, output.msg_type);
            assert_eq(test_data.last, output.packet.last);
            assert_eq(test_data.last_block, output.packet.last_block);
            assert_eq(test_data.id, output.packet.id);
            assert_eq(test_data.data as common::BlockData, output.packet.data);
            assert_eq(test_data.length, output.packet.length);

            let (tok, _) = recv_if(tok, resp_r, test_data.last, zero!<RawBlockDecoderResp>());

            tok
        }(tok);

        send(tok, terminator, true);
    }
}
