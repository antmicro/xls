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
import xls.modules.zstd.fse_table_creator;
import xls.modules.zstd.refilling_shift_buffer;
import xls.modules.zstd.fse_proba_freq_dec;
import xls.modules.shift_buffer.shift_buffer;

pub enum FseLookupDecoderStatus: u1 {
    OK = 0,
    ERROR = 1,
}

pub struct FseLookupDecoderReq<AXI_ADDR_W: u32> {
    addr: uN[AXI_ADDR_W]
}

pub struct FseLookupDecoderResp {
    status: FseLookupDecoderStatus
}

pub proc FseLookupDecoder<
    AXI_DATA_W: u32, AXI_ADDR_W: u32,
    DPD_RAM_ADDR_W: u32, DPD_RAM_DATA_W: u32, DPD_RAM_NUM_PARTITIONS: u32,
    TMP_RAM_ADDR_W: u32, TMP_RAM_DATA_W: u32, TMP_RAM_NUM_PARTITIONS: u32,
    FSE_RAM_ADDR_W: u32, FSE_RAM_DATA_W: u32, FSE_RAM_NUM_PARTITIONS: u32,
    SB_LENGTH_W: u32 = {shift_buffer::length_width(AXI_DATA_W)},
> {
    type Req = FseLookupDecoderReq<AXI_ADDR_W>;
    type Resp = FseLookupDecoderResp;
    type Status = FseLookupDecoderStatus;

    type FseTableStart = fse_table_creator::FseStartMsg;

    type MemReaderReq  = mem_reader::MemReaderReq<AXI_ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<AXI_DATA_W, AXI_ADDR_W>;
    type MemReaderStatus = mem_reader::MemReaderStatus;

    type DpdRamWriteReq = ram::WriteReq<DPD_RAM_ADDR_W, DPD_RAM_DATA_W, DPD_RAM_NUM_PARTITIONS>;
    type DpdRamWriteResp = ram::WriteResp;
    type DpdRamReadReq = ram::ReadReq<DPD_RAM_ADDR_W, DPD_RAM_NUM_PARTITIONS>;
    type DpdRamReadResp = ram::ReadResp<DPD_RAM_DATA_W>;

    type FseRamRdReq = ram::ReadReq<FSE_RAM_ADDR_W, FSE_RAM_NUM_PARTITIONS>;
    type FseRamRdResp = ram::ReadResp<FSE_RAM_DATA_W>;
    type FseRamWrReq = ram::WriteReq<FSE_RAM_ADDR_W, FSE_RAM_DATA_W, FSE_RAM_NUM_PARTITIONS>;
    type FseRamWrResp = ram::WriteResp;

    type TmpRamRdReq = ram::ReadReq<TMP_RAM_ADDR_W, TMP_RAM_NUM_PARTITIONS>;
    type TmpRamRdResp = ram::ReadResp<TMP_RAM_DATA_W>;
    type TmpRamWrReq = ram::WriteReq<TMP_RAM_ADDR_W, TMP_RAM_DATA_W, TMP_RAM_NUM_PARTITIONS>;
    type TmpRamWrResp = ram::WriteResp;

    type RefillerStartReq = refilling_shift_buffer::RefillStart<AXI_ADDR_W>;
    type RefillerError = refilling_shift_buffer::RefillError;
    type SBOutput = shift_buffer::ShiftBufferOutput<AXI_DATA_W, SB_LENGTH_W>;
    type SBCtrl = shift_buffer::ShiftBufferCtrl<SB_LENGTH_W>;

    type FsePFDecReq = fse_proba_freq_dec::FseProbaFreqDecoderReq;
    type FsePFDecResp = fse_proba_freq_dec::FseProbaFreqDecoderResp;
    type FsePFDecStatus = fse_proba_freq_dec::FseProbaFreqDecoderStatus;

    req_r: chan<Req> in;
    resp_s: chan<Resp> out;

    start_req_s: chan<RefillerStartReq> out;
    stop_flush_req_s: chan<()> out;
    error_r: chan<RefillerError> in;
    buffer_ctrl_s: chan<SBCtrl> out;
    buffer_data_out_r: chan<SBOutput> in;
    flushing_done_r: chan<()> in;
    fse_pf_dec_req_s: chan<FsePFDecReq> out;
    fse_pf_dec_resp_r: chan<FsePFDecResp> in;
    fse_table_start_s: chan<FseTableStart> out;
    fse_table_finish_r: chan<()> in;

    init {}

    config(
        req_r: chan<Req> in,
        resp_s: chan<Resp> out,

        mem_rd_req_s: chan<MemReaderReq> out,
        mem_rd_resp_r: chan<MemReaderResp> in,

        dpd_rd_req_s: chan<DpdRamReadReq> out,
        dpd_rd_resp_r: chan<DpdRamReadResp> in,
        dpd_wr_req_s: chan<DpdRamWriteReq> out,
        dpd_wr_resp_r: chan<DpdRamWriteResp> in,

        tmp_rd_req_s: chan<TmpRamRdReq> out,
        tmp_rd_resp_r: chan<TmpRamRdResp> in,
        tmp_wr_req_s: chan<TmpRamWrReq> out,
        tmp_wr_resp_r: chan<TmpRamWrResp> in,

        fse_rd_req_s: chan<FseRamRdReq> out,
        fse_rd_resp_r: chan<FseRamRdResp> in,
        fse_wr_req_s: chan<FseRamWrReq> out,
        fse_wr_resp_r: chan<FseRamWrResp> in,
    ) {
        let (fse_table_start_s, fse_table_start_r) = chan<FseTableStart>("fse_table_start");
        let (fse_table_finish_s, fse_table_finish_r) = chan<()>("fse_table_finish");

        spawn fse_table_creator::FseTableCreator<
            DPD_RAM_ADDR_W, DPD_RAM_DATA_W, DPD_RAM_NUM_PARTITIONS,
            TMP_RAM_ADDR_W, TMP_RAM_DATA_W, TMP_RAM_NUM_PARTITIONS,
            FSE_RAM_ADDR_W, FSE_RAM_DATA_W, FSE_RAM_NUM_PARTITIONS,
        >(
            fse_table_start_r, fse_table_finish_s,
            dpd_rd_req_s, dpd_rd_resp_r,
            fse_rd_req_s, fse_rd_resp_r, fse_wr_req_s, fse_wr_resp_r,
            tmp_rd_req_s, tmp_rd_resp_r, tmp_wr_req_s, tmp_wr_resp_r,
        );

        let (start_req_s, start_req_r) = chan<RefillerStartReq>("start_req");
        let (stop_flush_req_s, stop_flush_req_r) = chan<()>("stop_flush_req");
        let (error_s, error_r) = chan<RefillerError>("error");
        let (buffer_ctrl_s, buffer_ctrl_r) = chan<SBCtrl>("buffer_ctrl");
        let (buffer_data_out_s, buffer_data_out_r) = chan<SBOutput>("buffer_data_out");
        let (flushing_done_s, flushing_done_r) = chan<()>("flushing_done");

        spawn refilling_shift_buffer::RefillingShiftBuffer<AXI_DATA_W, AXI_ADDR_W>(
            mem_rd_req_s,
            mem_rd_resp_r,
            start_req_r,
            stop_flush_req_r,
            error_s,
            buffer_ctrl_r,
            buffer_data_out_s,
            flushing_done_s,
        );

        let (fse_pf_dec_req_s, fse_pf_dec_req_r) = chan<FsePFDecReq>("fse_pf_dec_req");
        let (fse_pf_dec_resp_s, fse_pf_dec_resp_r) = chan<FsePFDecResp>("fse_pf_dec_resp");

        spawn fse_proba_freq_dec::FseProbaFreqDecoder<
            DPD_RAM_ADDR_W, DPD_RAM_DATA_W, DPD_RAM_NUM_PARTITIONS,
        >(
            fse_pf_dec_req_r, fse_pf_dec_resp_s,
            buffer_ctrl_s, buffer_data_out_r,
            dpd_wr_req_s, dpd_wr_resp_r,
        );

        (
            req_r, resp_s,
            start_req_s,
            stop_flush_req_s,
            error_r,
            flushing_done_r,
            fse_pf_dec_req_s, fse_pf_dec_resp_r,
            fse_table_start_s, fse_table_finish_r,
        )
    }

    next(state: ()) {
        let tok = join();
        let (tok, start_req) = recv(tok, req_r);

        // start refilling shift buffer
        let tok_dec_pf1 = send(tok, start_req_s, RefillerStartReq {
            start_addr: start_req.addr
        });
        // start FSE probability frequency decoder
        let tok_dec_pf2 = send(tok, fse_pf_dec_req_s, FsePFDecReq {});

        // wait for completion from FSE probability frequency decoder
        let tok = join(tok_dec_pf1, tok_dec_pf2);
        let (tok_dec_resp, pf_dec_res) = recv(tok, fse_pf_dec_resp_r);

        // flush refilling shift buffer (regardless of any errors)
        let tok_flush = send(tok_dec_resp, stop_flush_req_s, ());
        recv(tok_flush, flushing_done_r);

        let pf_dec_ok = pf_dec_res.status == FsePFDecStatus::OK;
        // run FSE Table creation conditional or previous processing succeeding
        let tok = send_if(tok_dec_resp, fse_table_start_s, pf_dec_ok, FseTableStart {
            num_symbs: pf_dec_res.symbol_count,
            accuracy_log: pf_dec_res.accuracy_log,
        });
        // wait for completion from FSE table creator
        let (tok, ()) = recv_if(tok, fse_table_finish_r, pf_dec_ok, ());

        send(tok, resp_s, if pf_dec_ok { Status::OK } else { Status::ERROR });
    }
}

