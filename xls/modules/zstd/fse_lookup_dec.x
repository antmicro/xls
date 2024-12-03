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


import xls.examples.ram;
import xls.modules.zstd.memory.axi;
import xls.modules.zstd.memory.mem_reader;

pub struct FseLookupDecoderReq<AXI_ADDRW: u32> {}
pub struct FseLookupDecoderResp {}

pub proc FseLookupDecoder<
    AXI_DATA_W: u32, AXI_ADDR_W: u32,
    TMP_RAM_ADDR_W: u32, TMP_RAM_DATA_W: u32, TMP_RAM_NUM_PARTITIONS: u32,
    FSE_RAM_ADDR_W: u32, FSE_RAM_DATA_W: u32, FSE_RAM_NUM_PARTITIONS: u32,
> {
    type Req = FseLookupDecoderReq<AXI_ADDR_W>;
    type Resp = FseLookupDecoderResp;

    type MemReaderReq  = mem_reader::MemReaderReq<AXI_ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<AXI_DATA_W, AXI_ADDR_W>;
    type MemReaderStatus = mem_reader::MemReaderStatus;

    type FseRamRdReq = ram::ReadReq<FSE_RAM_ADDR_W, FSE_RAM_NUM_PARTITIONS>;
    type FseRamRdResp = ram::ReadResp<FSE_RAM_DATA_W>;
    type FseRamWrReq = ram::WriteReq<FSE_RAM_ADDR_W, FSE_RAM_DATA_W, FSE_RAM_NUM_PARTITIONS>;
    type FseRamWrResp = ram::WriteResp;

    type TmpRamRdReq = ram::ReadReq<TMP_RAM_ADDR_W, TMP_RAM_NUM_PARTITIONS>;
    type TmpRamRdResp = ram::ReadResp<TMP_RAM_DATA_W>;
    type TmpRamWrReq = ram::WriteReq<TMP_RAM_ADDR_W, TMP_RAM_DATA_W, TMP_RAM_NUM_PARTITIONS>;
    type TmpRamWrResp = ram::WriteResp;

    req_r: chan<Req> in;
    resp_s: chan<Resp> out;

    mem_rd_req_s: chan<MemReaderReq> out;
    mem_rd_resp_r: chan<MemReaderResp> in;

    tmp_rd_req_s: chan<TmpRamRdReq> out;
    tmp_rd_resp_r: chan<TmpRamRdResp> in;
    tmp_wr_req_s: chan<TmpRamWrReq> out;
    tmp_wr_resp_r: chan<TmpRamWrResp> in;

    fse_rd_req_s: chan<FseRamRdReq> out;
    fse_rd_resp_r: chan<FseRamRdResp> in;
    fse_wr_req_s: chan<FseRamWrReq> out;
    fse_wr_resp_r: chan<FseRamWrResp> in;

    init {}

    config(
        req_r: chan<Req> in,
        resp_s: chan<Resp> out,

        mem_rd_req_s: chan<MemReaderReq> out,
        mem_rd_resp_r: chan<MemReaderResp> in,

        tmp_rd_req_s: chan<TmpRamRdReq> out,
        tmp_rd_resp_r: chan<TmpRamRdResp> in,
        tmp_wr_req_s: chan<TmpRamWrReq> out,
        tmp_wr_resp_r: chan<TmpRamWrResp> in,

        fse_rd_req_s: chan<FseRamRdReq> out,
        fse_rd_resp_r: chan<FseRamRdResp> in,
        fse_wr_req_s: chan<FseRamWrReq> out,
        fse_wr_resp_r: chan<FseRamWrResp> in,
    ) {
        (
            req_r, resp_s,
            mem_rd_req_s, mem_rd_resp_r,
            tmp_rd_req_s, tmp_rd_resp_r, tmp_wr_req_s, tmp_wr_resp_r,
            fse_rd_req_s, fse_rd_resp_r, fse_wr_req_s, fse_wr_resp_r,
        )
    }

    next(state: ()) {
        let tok = join();

        send_if(tok, mem_rd_req_s, false, zero!<MemReaderReq>());
        recv_if(tok, mem_rd_resp_r, false, zero!<MemReaderResp>());

        send_if(tok, tmp_rd_req_s, false, zero!<TmpRamRdReq>());
        recv_if(tok, tmp_rd_resp_r, false, zero!<TmpRamRdResp>());
        send_if(tok, tmp_wr_req_s, false, zero!<TmpRamWrReq>());
        recv_if(tok, tmp_wr_resp_r, false, zero!<TmpRamWrResp>());

        send_if(tok, fse_rd_req_s, false, zero!<FseRamRdReq>());
        recv_if(tok, fse_rd_resp_r, false, zero!<FseRamRdResp>());
        send_if(tok, fse_wr_req_s, false, zero!<FseRamWrReq>());
        recv_if(tok, fse_wr_resp_r, false, zero!<FseRamWrResp>());

        recv_if(tok, req_r, false, zero!<Req>());
        send_if(tok, resp_s, false, zero!<Resp>());
    }
}
