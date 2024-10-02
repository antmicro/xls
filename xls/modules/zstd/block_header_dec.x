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

import xls.modules.zstd.block_header as block_header;
import xls.modules.zstd.common as common;
import xls.modules.zstd.memory.mem_reader as mem_reader;

type BlockSize = common::BlockSize;
type BlockType = common::BlockType;
type BlockHeader = block_header::BlockHeader;

pub struct BlockHeaderDecoderReq<ADDR_W: u32> {
    addr: uN[ADDR_W],
}

pub enum BlockHeaderDecoderStatus: u1 {
   OKAY = 0,
   CORRUPTED = 1,
}

pub struct BlockHeaderDecoderResp {
    status: BlockHeaderDecoderStatus,
    header: BlockHeader,
}

pub proc BlockHeaderDecoder<DATA_W: u32, ADDR_W: u32> {
    type DecoderReq = BlockHeaderDecoderReq<ADDR_W>;
    type DecoderResp = BlockHeaderDecoderResp<ADDR_W>;

    type MemReaderReq = mem_reader::MemReaderReq<ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<DATA_W, ADDR_W>;

    type Status = BlockHeaderDecoderStatus;

    req_r: chan<DecoderReq> in;
    resp_s: chan<DecoderResp> out;
    mem_req_s: chan<MemReaderReq> out;
    mem_resp_r: chan<MemReaderResp> in;

    config (
        req_r: chan<DecoderReq> in,
        resp_s: chan<DecoderResp> out,
        mem_req_s: chan<MemReaderReq> out,
        mem_resp_r: chan<MemReaderResp> in,
    ) {
        (req_r, resp_s, mem_req_s, mem_resp_r)
    }

    init { }

    next (state: ()) {
        let tok0 = join();

        // receive request
        let (tok1_0, req, req_valid) = recv_non_blocking(tok0, req_r, zero!<DecoderReq>());

        // send memory read request
        let mem_req = MemReaderReq {addr: req.addr, length: uN[ADDR_W]:3 };
        let tok2_0 = send_if(tok1_0, mem_req_s, req_valid, mem_req);

        // receive memory read response
        let (tok1_1, mem_resp, mem_resp_valid) = recv_non_blocking(tok0, mem_resp_r, zero!<MemReaderResp>());
        let header = block_header::extract_block_header(mem_resp.data as u24);

        let resp = match header.btype {
            BlockType::RAW => DecoderResp {
                status: Status::OKAY,
                header: BlockHeader { size: header.size + BlockSize:3, ..header },
            },
            BlockType::RLE => DecoderResp {
                status: Status::OKAY,
                header: BlockHeader { size: BlockSize:4, ..header },
            },
            BlockType::COMPRESSED => DecoderResp {
                status: Status::OKAY,
                header: BlockHeader { size: header.size + BlockSize:3, ..header }
            },
            BlockType::RESERVED   => DecoderResp {
                status: Status::CORRUPTED,
                header: zero!<BlockHeader>()
            },
            _ => fail!("impossible_case", zero!<DecoderResp>()),
        };

        // send parsed header
        let tok2_1 = send_if(tok1_1, resp_s, mem_resp_valid, resp);
    }
}

const INST_DATA_W = u32:32;
const INST_ADDR_W = u32:32;

proc BlockHeaderDecoderInst {
    type DecoderReq = BlockHeaderDecoderReq<INST_ADDR_W>;
    type DecoderResp = BlockHeaderDecoderResp;
    type MemReaderReq = mem_reader::MemReaderReq<INST_ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<INST_DATA_W, INST_ADDR_W>;

    config (
        req_r: chan<DecoderReq> in,
        resp_s: chan<DecoderResp> out,
        mem_req_s: chan<MemReaderReq> out,
        mem_resp_r: chan<MemReaderResp> in,
    ) {
        spawn BlockHeaderDecoder<INST_DATA_W, INST_ADDR_W>(
            req_r, resp_s, mem_req_s, mem_resp_r,
        );
    }

    init { }
    next (state: ()) { }
}


const TEST_DATA_W = u32:32;
const TEST_ADDR_W = u32:32;

type TestDecoderReq = BlockHeaderDecoderReq<INST_ADDR_W>;
type TestDecoderResp = BlockHeaderDecoderResp;

type TestMemReaderReq = mem_reader::MemReaderReq<TEST_ADDR_W>;
type TestMemReaderResp = mem_reader::MemReaderResp<TEST_DATA_W, TEST_ADDR_W>;

struct TestData {
    addr: uN[TEST_ADDR_W],
    header_enc: u24,
    header_dec: TestDecoderResp,
}

fn gen_test_data(addr: uN[TEST_ADDR_W], size: BlockSize, btype: BlockType, last: bool) -> TestData {
    let size_dec = if btype == BlockType::RLE { BlockSize:4 } else { size + BlockSize:3 };

    TestData {
        addr: addr,
        header_enc: size ++ (btype as u2) ++ last,
        header_dec: TestDecoderResp {
            status: BlockHeaderDecoderStatus::OKAY,
            header: BlockHeader { size: size_dec, btype: btype, last:last },
        }
    }
}

const TEST_DATA = TestData[2]:[
    gen_test_data(uN[TEST_ADDR_W]:0, BlockSize:32, BlockType::RAW, false),
    gen_test_data(uN[TEST_ADDR_W]:32, BlockSize:16, BlockType::RAW, false),
];

#[test_proc]
proc BlockHeaderDecoder_test {
    terminator: chan<bool> out;

    req_s: chan<TestDecoderReq> out;
    resp_r: chan<TestDecoderResp> in;

    mem_req_r: chan<TestMemReaderReq> in;
    mem_resp_s: chan<TestMemReaderResp> out;


    config (terminator: chan<bool> out) {
        let (req_s, req_r) = chan<TestDecoderReq>("req");
        let (resp_s, resp_r) = chan<TestDecoderResp>("resp");

        let (mem_req_s, mem_req_r) = chan<TestMemReaderReq>("mem_req");
        let (mem_resp_s, mem_resp_r) = chan<TestMemReaderResp>("mem_resp");

        spawn BlockHeaderDecoder<TEST_DATA_W, TEST_ADDR_W> (
            req_r, resp_s,
            mem_req_s, mem_resp_r,
        );

        (
            terminator,
            req_s, resp_r,
            mem_req_r, mem_resp_s,
        )
    }

    init { }

    next (state: ()) {
        let tok = join();

        let tok = for ((i, test_data), tok): ((u32, TestData), token) in enumerate(TEST_DATA) {

            let req = TestDecoderReq { addr: test_data.addr };
            let tok = send(tok, req_s, req);
            trace_fmt!("Send #{} req {:#x}", i + u32:1, req);

            let (tok, mem_req) = recv(tok, mem_req_r);
            trace_fmt!("Received #{} mem reader request {:#x}", i + u32:1, mem_req);
            let expected_mem_req = TestMemReaderReq { addr: test_data.addr, length: uN[TEST_ADDR_W]:24 };
            assert_eq(expected_mem_req, mem_req);

            let mem_resp = TestMemReaderResp {
                status: mem_reader::MemReaderStatus::OKAY,
                data: test_data.header_enc as u32,
                length: uN[TEST_ADDR_W]:24,
                last: true,
            };
            let tok = send(tok, mem_resp_s, mem_resp);
            trace_fmt!("Sent #{} mem resp {:#x}", i + u32:1, mem_resp);

            let (tok, resp) = recv(tok, resp_r);
            trace_fmt!("Received #{} response {:#x}", i + u32:1, resp);
            assert_eq(test_data.header_dec, resp);

            tok
        }(tok);

        send(tok, terminator, true);
    }
}
