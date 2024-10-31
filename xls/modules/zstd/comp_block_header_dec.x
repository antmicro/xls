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

import xls.modules.zstd.memory.mem_reader;

pub struct CompressBlockHeaderDecoderReq {}
pub struct CompressBlockHeaderDecoderResp {}

pub proc CompressBlockHeaderDecoder<AXI_DATA_W: u32, AXI_ADDR_W: u32> {

    type Req = CompressBlockHeaderDecoderReq;
    type Resp = CompressBlockHeaderDecoderResp;

    type MemReaderReq  = mem_reader::MemReaderReq<AXI_ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<AXI_DATA_W, AXI_ADDR_W>;

    mem_rd_req_s: chan<MemReaderReq> out;
    mem_rd_resp_r: chan<MemReaderResp> in;

    req_r: chan<Req> in;
    resp_s: chan<Resp> out;

    init {}

    config(
        mem_rd_req_s: chan<MemReaderReq> out,
        mem_rd_resp_r: chan<MemReaderResp> in,

        req_r: chan<Req> in,
        resp_s: chan<Resp> out,
    ) {
        (mem_rd_req_s, mem_rd_resp_r, req_r, resp_s)
    }

    next(state: ()) {
        let tok = join();

        send_if(tok, mem_rd_req_s, false, zero!<MemReaderReq>());
        send_if(tok, resp_s, false, zero!<Resp>());

        recv_if(tok, mem_rd_resp_r, false, zero!<MemReaderResp>());
        recv_if(tok, req_r, false, zero!<Req>());

        state
    }
}

const TEST_AXI_DATA_W = u32:64;
const TEST_AXI_ADDR_W = u32:32;

#[test_proc]
proc CompressBlockHeaderDecoderTest {
    type Req = CompressBlockHeaderDecoderReq;
    type Resp = CompressBlockHeaderDecoderResp;

    type MemReaderReq  = mem_reader::MemReaderReq<TEST_AXI_ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<TEST_AXI_DATA_W, TEST_AXI_ADDR_W>;

    terminator: chan<bool> out;

    mem_rd_req_r: chan<MemReaderReq> in;
    mem_rd_resp_s: chan<MemReaderResp> out;
    req_s: chan<Req> out;
    resp_r: chan<Resp> in;

    init {}

    config(terminator: chan<bool> out) {

        let (mem_rd_req_s, mem_rd_req_r) = chan<MemReaderReq>("mem_rd_req");
        let (mem_rd_resp_s, mem_rd_resp_r) = chan<MemReaderResp>("mem_rd_resp");

        let (req_s, req_r) = chan<CompressBlockHeaderDecoderReq>("req");
        let (resp_s, resp_r) = chan<CompressBlockHeaderDecoderResp>("resp");

        spawn CompressBlockHeaderDecoder<TEST_AXI_DATA_W, TEST_AXI_ADDR_W> (
            mem_rd_req_s, mem_rd_resp_r, req_r, resp_s
        );

        (
            terminator,
            mem_rd_req_r, mem_rd_resp_s,
            req_s, resp_r
        )
    }

    next(state: ()) {
        send(join(), terminator, true);
    }
}
