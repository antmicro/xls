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

import std;

import xls.examples.ram;
import xls.modules.zstd.common;
import xls.modules.zstd.memory.axi;
import xls.modules.zstd.memory.mem_reader;
import xls.modules.zstd.sequence_conf_dec;
import xls.modules.zstd.fse_lookup_dec;
import xls.modules.zstd.ram_demux3;
import xls.modules.zstd.ram_demux;
import xls.modules.zstd.refilling_shift_buffer;
import xls.modules.zstd.fse_dec;
import xls.modules.shift_buffer.shift_buffer;


enum SequenceDecoderStatus: u3 {
    OK = 0,
    ERROR = 1,
}

pub struct SequenceDecoderReq<ADDR_W: u32> {
    addr: uN[ADDR_W],
}

pub struct SequenceDecoderResp {
    status: SequenceDecoderStatus,
}

enum SequenceDecoderFSM: u3 {
    IDLE = 0,
    DECODE_SEQUENCE_HEADER = 1,
    PREPARE_LL_TABLE = 2,
    PREPARE_OF_TABLE = 3,
    PREPARE_ML_TABLE = 4,

    ERROR = 7,
}

struct SequenceDecoderState<ADDR_W: u32> {
    fsm: SequenceDecoderFSM,
    req: SequenceDecoderReq<ADDR_W>,
    conf_resp: sequence_conf_dec::SequenceConfDecoderResp,
}

type CommandConstructorData = common::CommandConstructorData;

pub proc SequenceDecoderCtrl<AXI_ADDR_W: u32> {
    type Req = SequenceDecoderReq<AXI_ADDR_W>;
    type Resp = SequenceDecoderResp;
    type State = SequenceDecoderState<AXI_ADDR_W>;
    type FSM = SequenceDecoderFSM;
    type Status = SequenceDecoderStatus;

    type CompressionMode = common::CompressionMode;
    type SequenceConfDecoderStatus = sequence_conf_dec::SequenceConfDecoderStatus;

    type SequenceConfDecoderReq = sequence_conf_dec::SequenceConfDecoderReq<AXI_ADDR_W>;
    type SequenceConfDecoderResp = sequence_conf_dec::SequenceConfDecoderResp;
    type FseLookupDecoderReq = fse_lookup_dec::FseLookupDecoderReq<AXI_ADDR_W>;
    type FseLookupDecoderResp = fse_lookup_dec::FseLookupDecoderResp;

    sd_req_r: chan<Req> in;
    sd_resp_s: chan<Resp> out;

    scd_req_s: chan<SequenceConfDecoderReq> out;
    scd_resp_r: chan<SequenceConfDecoderResp> in;

    fld_req_s: chan<FseLookupDecoderReq> out;
    fld_resp_r: chan<FseLookupDecoderResp> in;

    fse_demux_req_s: chan<u2> out;
    fse_demux_resp_r: chan<()> in;

    ll_demux_req_s: chan<u1> out;
    ll_demux_resp_r: chan<()> in;

    of_demux_req_s: chan<u1> out;
    of_demux_resp_r: chan<()> in;

    ml_demux_req_s: chan<u1> out;
    ml_demux_resp_r: chan<()> in;

    init { zero!<State>() }

    config(
        sd_req_r: chan<Req> in,
        sd_resp_s: chan<Resp> out,

        scd_req_s: chan<SequenceConfDecoderReq> out,
        scd_resp_r: chan<SequenceConfDecoderResp> in,

        fld_req_s: chan<FseLookupDecoderReq> out,
        fld_resp_r: chan<FseLookupDecoderResp> in,

        fse_demux_req_s: chan<u2> out,
        fse_demux_resp_r: chan<()> in,

        ll_demux_req_s: chan<u1> out,
        ll_demux_resp_r: chan<()> in,

        of_demux_req_s: chan<u1> out,
        of_demux_resp_r: chan<()> in,

        ml_demux_req_s: chan<u1> out,
        ml_demux_resp_r: chan<()> in,
    ) {
        (
            sd_req_r, sd_resp_s,
            scd_req_s, scd_resp_r,
            fld_req_s, fld_resp_r,
            fse_demux_req_s, fse_demux_resp_r,
            ll_demux_req_s, ll_demux_resp_r,
            of_demux_req_s, of_demux_resp_r,
            ml_demux_req_s, ml_demux_resp_r,
        )
    }

    next(state: State) {
        // FIXME: proc-scoped type aliases failure
        type State = SequenceDecoderState<AXI_ADDR_W>;

        let tok0 = join();

        let (tok1_0, req) = recv_if(tok0, sd_req_r, state.fsm == FSM::IDLE, zero!<Req>());
        if state.fsm == FSM::IDLE {
            trace_fmt!("[IDLE]: Received request {:#x}", req);
        } else {};

        let conf_req = SequenceConfDecoderReq { addr: state.req.addr };
        let tok1_1 = send_if(tok0, scd_req_s, state.fsm == FSM::DECODE_SEQUENCE_HEADER, conf_req);

        let (tok1_2, conf_resp, conf_resp_valid) = recv_if_non_blocking(tok0, scd_resp_r, state.fsm == FSM::DECODE_SEQUENCE_HEADER, zero!<SequenceConfDecoderResp>());
        if conf_resp_valid {
            trace_fmt!("[DECODE_SEQUENCE_HEADER]: {:#x}", conf_resp);
        } else {};

        //let tok1_3 = send_if(tok0, fld_req_s, false, zero!<FseLookupDecoderReq>());
        //let (tok1_4, _) = recv_if(tok0, fld_resp_r, false, zero!<FseLookupDecoderResp>());

        //let tok1_5 = send_if(tok0, sel_req_s, false, u2:0);
        //let (tok1_6, _) = recv_if(tok0, sel_resp_r, false, ());

        //let fail_resp = Resp { status: Status::ERROR };
        //let tok1_7 = send_if(tok0, sd_resp_s, state.fsm == FSM::ERROR, fail_resp);

        match state.fsm {
            FSM::IDLE => {
                State { fsm: FSM::DECODE_SEQUENCE_HEADER, req, ..state }
            },

            FSM::DECODE_SEQUENCE_HEADER => {
                match (conf_resp_valid, conf_resp.status) {
                    (true, SequenceConfDecoderStatus::OKAY) => State { fsm: FSM::PREPARE_LL_TABLE, conf_resp, ..state},
                    (true, _)                               => State { fsm: FSM::ERROR, conf_resp, ..state},
                    (_, _)                                  => state,
                }
            },

            FSM::PREPARE_LL_TABLE => {
                match (state.conf_resp.header.literals_mode) {
                    CompressionMode::PREDEFINED => {
                        trace_fmt!("[PREPARE_LL_TABLE] Predefined");
                        state
                    },
                    CompressionMode::RLE => {
                        trace_fmt!("[PREPARE_LL_TABLE] RLE");
                        state
                    },
                    CompressionMode::COMPRESSED => {
                        trace_fmt!("[PREPARE_LL_TABLE] COMPRESSED");
                        state
                    },
                    CompressionMode::REPEAT => {
                        trace_fmt!("[PREPARE_LL_TABLE] REPEAT");
                        state
                    },
                    _ => state,
                }
            },

            FSM::PREPARE_OF_TABLE => {
                trace_fmt!("[PREPARE_OF_TABLE]");
                state
            },

            FSM::PREPARE_ML_TABLE => {
                trace_fmt!("[PREPARE_ML_TABLE]");
                state
            },

            FSM::ERROR => {
                trace_fmt!("[ERROR]: FAIL!");
                state
            }
        }
    }
}

const SDC_TEST_AXI_ADDR_W = u32:32;

#[test_proc]
proc SequenceDecoderCtrlTest {

    type Req = SequenceDecoderReq<SDC_TEST_AXI_ADDR_W>;
    type Resp = SequenceDecoderResp;
    type Status = SequenceDecoderStatus;

    type CompressionMode = common::CompressionMode;
    type Addr = uN[SDC_TEST_AXI_ADDR_W];

    type SequenceConf = common::SequenceConf;
    type SequenceConfDecoderReq = sequence_conf_dec::SequenceConfDecoderReq<SDC_TEST_AXI_ADDR_W>;
    type SequenceConfDecoderResp = sequence_conf_dec::SequenceConfDecoderResp;
    type SequenceConfDecoderStatus = sequence_conf_dec::SequenceConfDecoderStatus;

    type FseLookupDecoderReq = fse_lookup_dec::FseLookupDecoderReq<SDC_TEST_AXI_ADDR_W>;
    type FseLookupDecoderResp = fse_lookup_dec::FseLookupDecoderResp;

    terminator: chan<bool> out;

    sd_req_s: chan<Req> out;
    sd_resp_r: chan<Resp> in;

    scd_req_r: chan<SequenceConfDecoderReq> in;
    scd_resp_s: chan<SequenceConfDecoderResp> out;

    fld_req_r: chan<FseLookupDecoderReq> in;
    fld_resp_s: chan<FseLookupDecoderResp> out;

    fse_demux_req_r: chan<u2> in;
    fse_demux_resp_s: chan<()> out;

    ll_demux_req_r: chan<u1> in;
    ll_demux_resp_s: chan<()> out;

    of_demux_req_r: chan<u1> in;
    of_demux_resp_s: chan<()> out;

    ml_demux_req_r: chan<u1> in;
    ml_demux_resp_s: chan<()> out;

    init { }

    config(terminator: chan<bool> out) {
        let (sd_req_s, sd_req_r) = chan<Req>("sd_req");
        let (sd_resp_s, sd_resp_r) = chan<Resp>("sd_resp");

        let (scd_req_s, scd_req_r) = chan<SequenceConfDecoderReq>("scd_req");
        let (scd_resp_s, scd_resp_r) = chan<SequenceConfDecoderResp>("scd_resp");

        let (fld_req_s, fld_req_r) = chan<FseLookupDecoderReq>("fld_req");
        let (fld_resp_s, fld_resp_r) = chan<FseLookupDecoderResp>("fld_resp");

        let (fse_demux_req_s, fse_demux_req_r) = chan<u2>("fse_demux_req");
        let (fse_demux_resp_s, fse_demux_resp_r) = chan<()>("fse_demux_resp");

        let (ll_demux_req_s, ll_demux_req_r) = chan<u1>("ll_demux_req");
        let (ll_demux_resp_s, ll_demux_resp_r) = chan<()>("ll_demux_resp");

        let (of_demux_req_s, of_demux_req_r) = chan<u1>("of_demux_req");
        let (of_demux_resp_s, of_demux_resp_r) = chan<()>("of_demux_resp");

        let (ml_demux_req_s, ml_demux_req_r) = chan<u1>("ml_demux_req");
        let (ml_demux_resp_s, ml_demux_resp_r) = chan<()>("ml_demux_resp");

        spawn SequenceDecoderCtrl<SDC_TEST_AXI_ADDR_W>(
            sd_req_r, sd_resp_s,
            scd_req_s, scd_resp_r,
            fld_req_s, fld_resp_r,
            fse_demux_req_s, fse_demux_resp_r,
            ll_demux_req_s, ll_demux_resp_r,
            of_demux_req_s, of_demux_resp_r,
            ml_demux_req_s, ml_demux_resp_r,
        );

        (
            terminator,
            sd_req_s, sd_resp_r,
            scd_req_r, scd_resp_s,
            fld_req_r, fld_resp_s,
            fse_demux_req_r, fse_demux_resp_s,
            ll_demux_req_r, ll_demux_resp_s,
            of_demux_req_r, of_demux_resp_s,
            ml_demux_req_r, ml_demux_resp_s,
        )
    }

    next(state: ()) {
        let tok = join();

        let tok = send(tok, sd_req_s, Req {addr: Addr:0x1000 });
        // let (tok, sd_resp) = recv(tok, sd_resp_r);
        // assert_eq(sd_resp, Resp {status: Status::ERROR});

        let (tok, scd_req) = recv(tok, scd_req_r);
        assert_eq(scd_req, SequenceConfDecoderReq { addr: Addr: 0x1000 });

        // let ss_resp = SequenceConfDecoderResp {
        //     header: SequenceConf {
        //         sequence_count: u17:1,
        //         literals_mode: CompressionMode::PREDEFINED,
        //         offset_mode: CompressionMode::RLE,
        //         match_mode: CompressionMode::COMPRESSED,
        //     },
        //     length: u3:5,
        //     status: SequenceConfDecoderStatus::OKAY
        // };

        // let tok = send(tok, ss_resp_s, ss_resp);
        // let (tok, _) = recv(tok, sd_resp_r);

        send(tok, terminator, true);
    }
}

pub proc SequenceDecoder<
    AXI_ADDR_W: u32, AXI_DATA_W: u32, AXI_DEST_W: u32, AXI_ID_W: u32,
    DPD_RAM_ADDR_W: u32, DPD_RAM_DATA_W: u32, DPD_RAM_NUM_PARTITIONS: u32,
    TMP_RAM_ADDR_W: u32, TMP_RAM_DATA_W: u32, TMP_RAM_NUM_PARTITIONS: u32,
    FSE_RAM_ADDR_W: u32, FSE_RAM_DATA_W: u32, FSE_RAM_NUM_PARTITIONS: u32,

    AXI_DATA_W_DIV8: u32 = {AXI_DATA_W / u32:8},
    REFILLING_SB_DATA_W: u32 = {AXI_DATA_W},
    REFILLING_SB_LENGTH_W: u32 = {refilling_shift_buffer::length_width(AXI_DATA_W)},
> {
    type Req = SequenceDecoderReq<AXI_ADDR_W>;
    type Resp = SequenceDecoderResp;

    type MemAxiAr = axi::AxiAr<AXI_ADDR_W, AXI_ID_W>;
    type MemAxiR = axi::AxiR<AXI_DATA_W, AXI_ID_W>;
    type MemAxiAw = axi::AxiAw<AXI_ADDR_W, AXI_ID_W>;
    type MemAxiW = axi::AxiW<AXI_DATA_W, AXI_DATA_W_DIV8>;
    type MemAxiB = axi::AxiB<AXI_ID_W>;

    type MemReaderStatus = mem_reader::MemReaderStatus;
    type MemReaderReq  = mem_reader::MemReaderReq<AXI_ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<AXI_DATA_W, AXI_ADDR_W>;

    type SequenceConfDecoderReq = sequence_conf_dec::SequenceConfDecoderReq<AXI_ADDR_W>;
    type SequenceConfDecoderResp = sequence_conf_dec::SequenceConfDecoderResp;

    type FseLookupDecoderReq =  fse_lookup_dec::FseLookupDecoderReq<AXI_ADDR_W>;
    type FseLookupDecoderResp = fse_lookup_dec::FseLookupDecoderResp;

    type FseDecoderCtrl = fse_dec::FseDecoderCtrl;
    type FseDecoderFinish = fse_dec::FseDecoderFinish;

    type RefillingShiftBufferStart = refilling_shift_buffer::RefillStart<AXI_ADDR_W>;
    type RefillingShiftBufferError = refilling_shift_buffer::RefillingShiftBufferInput<REFILLING_SB_DATA_W, REFILLING_SB_LENGTH_W>;
    type RefillingShiftBufferOutput = refilling_shift_buffer::RefillingShiftBufferOutput<REFILLING_SB_DATA_W, REFILLING_SB_LENGTH_W>;
    type RefillingShiftBufferCtrl = refilling_shift_buffer::RefillingShiftBufferCtrl<REFILLING_SB_LENGTH_W>;

    type DpdRamRdReq = ram::ReadReq<DPD_RAM_ADDR_W, DPD_RAM_NUM_PARTITIONS>;
    type DpdRamRdResp = ram::ReadResp<DPD_RAM_DATA_W>;
    type DpdRamWrReq = ram::WriteReq<DPD_RAM_ADDR_W, DPD_RAM_DATA_W, DPD_RAM_NUM_PARTITIONS>;
    type DpdRamWrResp = ram::WriteResp;

    type TmpRamRdReq = ram::ReadReq<TMP_RAM_ADDR_W, TMP_RAM_NUM_PARTITIONS>;
    type TmpRamRdResp = ram::ReadResp<TMP_RAM_DATA_W>;
    type TmpRamWrReq = ram::WriteReq<TMP_RAM_ADDR_W, TMP_RAM_DATA_W, TMP_RAM_NUM_PARTITIONS>;
    type TmpRamWrResp = ram::WriteResp;

    type FseRamRdReq = ram::ReadReq<FSE_RAM_ADDR_W, FSE_RAM_NUM_PARTITIONS>;
    type FseRamRdResp = ram::ReadResp<FSE_RAM_DATA_W>;
    type FseRamWrReq = ram::WriteReq<FSE_RAM_ADDR_W, FSE_RAM_DATA_W, FSE_RAM_NUM_PARTITIONS>;
    type FseRamWrResp = ram::WriteResp;

    init { }

    fd_ctrl_s: chan<FseDecoderCtrl> out;
    fd_finish_r: chan<FseDecoderFinish> in;

    fd_rsb_ctrl_r: chan<RefillingShiftBufferCtrl> in;
    fd_rsb_data_s: chan<RefillingShiftBufferOutput> out;

    config (
        // Sequence Conf Decoder (manager)
        scd_axi_ar_s: chan<MemAxiAr> out,
        scd_axi_r_r: chan<MemAxiR> in,

        // Fse Lookup Decoder (manager)
        fld_axi_ar_s: chan<MemAxiAr> out,
        fld_axi_r_r: chan<MemAxiR> in,

        // FSE decoder (manager)
        fd_axi_ar_s: chan<MemAxiAr> out,
        fd_axi_r_r: chan<MemAxiR> in,

        req_r: chan<Req> in,
        resp_s: chan<Resp> out,

        // RAMs

        dpd_rd_req_s: chan<DpdRamRdReq> out,
        dpd_rd_resp_r: chan<DpdRamRdResp> in,
        dpd_wr_req_s: chan<DpdRamWrReq> out,
        dpd_wr_resp_r: chan<DpdRamWrResp> in,

        tmp_rd_req_s: chan<TmpRamRdReq> out,
        tmp_rd_resp_r: chan<TmpRamRdResp> in,
        tmp_wr_req_s: chan<TmpRamWrReq> out,
        tmp_wr_resp_r: chan<TmpRamWrResp> in,

        ll_def_fse_rd_req_s: chan<FseRamRdReq> out,
        ll_def_fse_rd_resp_r: chan<FseRamRdResp> in,
        ll_def_fse_wr_req_s: chan<FseRamWrReq> out,
        ll_def_fse_wr_resp_r: chan<FseRamWrResp> in,

        ll_fse_rd_req_s: chan<FseRamRdReq> out,
        ll_fse_rd_resp_r: chan<FseRamRdResp> in,
        ll_fse_wr_req_s: chan<FseRamWrReq> out,
        ll_fse_wr_resp_r: chan<FseRamWrResp> in,

        ml_def_fse_rd_req_s: chan<FseRamRdReq> out,
        ml_def_fse_rd_resp_r: chan<FseRamRdResp> in,
        ml_def_fse_wr_req_s: chan<FseRamWrReq> out,
        ml_def_fse_wr_resp_r: chan<FseRamWrResp> in,

        ml_fse_rd_req_s: chan<FseRamRdReq> out,
        ml_fse_rd_resp_r: chan<FseRamRdResp> in,
        ml_fse_wr_req_s: chan<FseRamWrReq> out,
        ml_fse_wr_resp_r: chan<FseRamWrResp> in,

        of_def_fse_rd_req_s: chan<FseRamRdReq> out,
        of_def_fse_rd_resp_r: chan<FseRamRdResp> in,
        of_def_fse_wr_req_s: chan<FseRamWrReq> out,
        of_def_fse_wr_resp_r: chan<FseRamWrResp> in,

        of_fse_rd_req_s: chan<FseRamRdReq> out,
        of_fse_rd_resp_r: chan<FseRamRdResp> in,
        of_fse_wr_req_s: chan<FseRamWrReq> out,
        of_fse_wr_resp_r: chan<FseRamWrResp> in,
    ) {
        const CHANNEL_DEPTH = u32:1;

        // Sequence Section Decoder

        let (scd_mem_rd_req_s,  scd_mem_rd_req_r) = chan<MemReaderReq, CHANNEL_DEPTH>("scd_mem_rd_req");
        let (scd_mem_rd_resp_s, scd_mem_rd_resp_r) = chan<MemReaderResp, CHANNEL_DEPTH>("scd_mem_rd_resp");

        spawn mem_reader::MemReader<AXI_DATA_W, AXI_ADDR_W, AXI_DEST_W, AXI_ID_W, CHANNEL_DEPTH>(
           scd_mem_rd_req_r, scd_mem_rd_resp_s,
           scd_axi_ar_s, scd_axi_r_r,
        );

        let (scd_req_s, scd_req_r) = chan<SequenceConfDecoderReq, CHANNEL_DEPTH>("scd_req");
        let (scd_resp_s, scd_resp_r) = chan<SequenceConfDecoderResp, CHANNEL_DEPTH>("scd_resp");

        spawn sequence_conf_dec::SequenceConfDecoder<AXI_DATA_W, AXI_ADDR_W>(
            scd_mem_rd_req_s, scd_mem_rd_resp_r,
            scd_req_r, scd_resp_s,
        );

        // FseLookupDecoder

        let (fld_mem_rd_req_s,  fld_mem_rd_req_r) = chan<MemReaderReq, CHANNEL_DEPTH>("fld_mem_rd_req");
        let (fld_mem_rd_resp_s, fld_mem_rd_resp_r) = chan<MemReaderResp, CHANNEL_DEPTH>("fld_mem_rd_resp");

        spawn mem_reader::MemReader<AXI_DATA_W, AXI_ADDR_W, AXI_DEST_W, AXI_ID_W, CHANNEL_DEPTH>(
            fld_mem_rd_req_r, fld_mem_rd_resp_s,
            fld_axi_ar_s, fld_axi_r_r,
        );

        let (fld_rsb_start_req_s, fld_rsb_start_req_r) = chan<RefillingShiftBufferStart>("fld_rsb_start_req");
        let (fld_rsb_stop_flush_req_s, fld_rsb_stop_flush_req_r) = chan<()>("fld_rsb_stop_flush_req");
        let (fld_rsb_ctrl_s, fld_rsb_ctrl_r) = chan<RefillingShiftBufferCtrl>("fld_rsb_ctrl");
        let (fld_rsb_data_s, fld_rsb_data_r) = chan<RefillingShiftBufferOutput>("fld_rsb_data");
        let (fld_rsb_flushing_done_s, fld_rsb_flushing_done_r) = chan<()>("fld_rsb_flushing_done");

        spawn refilling_shift_buffer::RefillingShiftBuffer<AXI_DATA_W, AXI_ADDR_W> (
            fld_mem_rd_req_s, fld_mem_rd_resp_r,
            fld_rsb_start_req_r, fld_rsb_stop_flush_req_r,
            fld_rsb_ctrl_r, fld_rsb_data_s,
            fld_rsb_flushing_done_s,
        );

        let (fld_req_s, fld_req_r) = chan<FseLookupDecoderReq, CHANNEL_DEPTH>("fse_req");
        let (fld_resp_s, fld_resp_r) = chan<FseLookupDecoderResp, CHANNEL_DEPTH>("fse_resp");

        let (fse_rd_req_s, fse_rd_req_r) = chan<FseRamRdReq, CHANNEL_DEPTH>("fse_rd_req");
        let (fse_rd_resp_s, fse_rd_resp_r) = chan<FseRamRdResp, CHANNEL_DEPTH>("fse_rd_resp");
        let (fse_wr_req_s, fse_wr_req_r) = chan<FseRamWrReq, CHANNEL_DEPTH>("fse_wr_req");
        let (fse_wr_resp_s, fse_wr_resp_r) = chan<FseRamWrResp, CHANNEL_DEPTH>("fse_wr_resp");

        spawn fse_lookup_dec::FseLookupDecoder<
            AXI_DATA_W, AXI_ADDR_W,
            DPD_RAM_DATA_W, DPD_RAM_ADDR_W, DPD_RAM_NUM_PARTITIONS,
            TMP_RAM_DATA_W, TMP_RAM_ADDR_W, TMP_RAM_NUM_PARTITIONS,
            FSE_RAM_DATA_W, FSE_RAM_ADDR_W, FSE_RAM_NUM_PARTITIONS,
        >(
            fld_req_r, fld_resp_s,
            fld_mem_rd_req_s, fld_mem_rd_resp_r,
            dpd_rd_req_s, dpd_rd_resp_r, dpd_wr_req_s, dpd_wr_resp_r,
            tmp_rd_req_s, tmp_rd_resp_r, tmp_wr_req_s, tmp_wr_resp_r,
            fse_rd_req_s, fse_rd_resp_r, fse_wr_req_s, fse_wr_resp_r,
        );

        // RamDemux3
        let (fse_demux_req_s, fse_demux_req_r) = chan<u2>("fse_demux_req");
        let (fse_demux_resp_s, fse_demux_resp_r) = chan<()>("fse_demux_resp");

        spawn ram_demux3::RamDemux3<FSE_RAM_ADDR_W, FSE_RAM_DATA_W, FSE_RAM_NUM_PARTITIONS>(
            fse_demux_req_r, fse_demux_resp_s,
            fse_rd_req_r, fse_rd_resp_s, fse_wr_req_r, fse_wr_resp_s,
            ll_fse_rd_req_s, ll_fse_rd_resp_r, ll_fse_wr_req_s, ll_fse_wr_resp_r,
            of_fse_rd_req_s, of_fse_rd_resp_r, of_fse_wr_req_s, of_fse_wr_resp_r,
            ml_fse_rd_req_s, ml_fse_rd_resp_r, ml_fse_wr_req_s, ml_fse_wr_resp_r,
        );

        let (ll_demux_req_s, ll_demux_req_r) = chan<u1>("ll_demux_req");
        let (ll_demux_resp_s, ll_demux_resp_r) = chan<()>("ll_demux_resp");

        let (ll_rd_req_s, ll_rd_req_r) = chan<FseRamRdReq>("ll_rd_req");
        let (ll_rd_resp_s, ll_rd_resp_r) = chan<FseRamRdResp>("ll_rd_resp");
        let (ll_wr_req_s, ll_wr_req_r) = chan<FseRamWrReq>("ll_wr_req");
        let (ll_wr_resp_s, ll_wr_resp_r) = chan<FseRamWrResp>("ll_wr_resp");

        spawn ram_demux::RamDemux<
            FSE_RAM_ADDR_W, FSE_RAM_DATA_W, FSE_RAM_NUM_PARTITIONS
        > (
            ll_demux_req_r, ll_demux_resp_s,
            ll_rd_req_r, ll_rd_resp_s, ll_wr_req_r, ll_wr_resp_s,
            ll_def_fse_rd_req_s, ll_def_fse_rd_resp_r, ll_def_fse_wr_req_s, ll_def_fse_wr_resp_r,
            ll_fse_rd_req_s, ll_fse_rd_resp_r, ll_fse_wr_req_s, ll_fse_wr_resp_r,
        );

        let (ml_demux_req_s, ml_demux_req_r) = chan<u1>("ml_demux_req");
        let (ml_demux_resp_s, ml_demux_resp_r) = chan<()>("ml_demux_resp");

        let (ml_rd_req_s, ml_rd_req_r) = chan<FseRamRdReq>("ml_rd_req");
        let (ml_rd_resp_s, ml_rd_resp_r) = chan<FseRamRdResp>("ml_rd_resp");
        let (ml_wr_req_s, ml_wr_req_r) = chan<FseRamWrReq>("ml_wr_req");
        let (ml_wr_resp_s, ml_wr_resp_r) = chan<FseRamWrResp>("ml_wr_resp");

        spawn ram_demux::RamDemux<
            FSE_RAM_ADDR_W, FSE_RAM_DATA_W, FSE_RAM_NUM_PARTITIONS
        > (
            ml_demux_req_r, ml_demux_resp_s,
            ml_rd_req_r, ml_rd_resp_s, ml_wr_req_r, ml_wr_resp_s,
            ml_def_fse_rd_req_s, ml_def_fse_rd_resp_r, ml_def_fse_wr_req_s, ml_def_fse_wr_resp_r,
            ml_fse_rd_req_s, ml_fse_rd_resp_r, ml_fse_wr_req_s, ml_fse_wr_resp_r,
        );

        let (of_demux_req_s, of_demux_req_r) = chan<u1>("of_demux_req");
        let (of_demux_resp_s, of_demux_resp_r) = chan<()>("of_demux_resp");

        let (of_rd_req_s, of_rd_req_r) = chan<FseRamRdReq>("of_rd_req");
        let (of_rd_resp_s, of_rd_resp_r) = chan<FseRamRdResp>("of_rd_resp");
        let (of_wr_req_s, of_wr_req_r) = chan<FseRamWrReq>("of_wr_req");
        let (of_wr_resp_s, of_wr_resp_r) = chan<FseRamWrResp>("of_wr_resp");

        spawn ram_demux::RamDemux<
            FSE_RAM_ADDR_W, FSE_RAM_DATA_W, FSE_RAM_NUM_PARTITIONS
        > (
            of_demux_req_r, of_demux_resp_s,
            of_rd_req_r, of_rd_resp_s, of_wr_req_r, of_wr_resp_s,
            of_def_fse_rd_req_s, of_def_fse_rd_resp_r, of_def_fse_wr_req_s, of_def_fse_wr_resp_r,
            of_fse_rd_req_s, of_fse_rd_resp_r, of_fse_wr_req_s, of_fse_wr_resp_r,
        );

        let (fd_mem_rd_req_s,  fd_mem_rd_req_r) = chan<MemReaderReq, CHANNEL_DEPTH>("fd_mem_rd_req");
        let (fd_mem_rd_resp_s, fd_mem_rd_resp_r) = chan<MemReaderResp, CHANNEL_DEPTH>("fd_mem_rd_resp");

        spawn mem_reader::MemReader<AXI_DATA_W, AXI_ADDR_W, AXI_DEST_W, AXI_ID_W, CHANNEL_DEPTH>(
           fd_mem_rd_req_r, fd_mem_rd_resp_s,
           fd_axi_ar_s, fd_axi_r_r,
        );

        let (fd_rsb_start_req_s, fd_rsb_start_req_r) = chan<RefillingShiftBufferStart>("fd_rsb_start_req");
        let (fd_rsb_stop_flush_req_s, fd_rsb_stop_flush_req_r) = chan<()>("fd_rsb_stop_flush_req");
        let (fd_rsb_ctrl_s, fd_rsb_ctrl_r) = chan<RefillingShiftBufferCtrl>("fd_rsb_ctrl");
        let (fd_rsb_data_s, fd_rsb_data_r) = chan<RefillingShiftBufferOutput>("fd_rsb_data");
        let (fd_rsb_flushing_done_s, fd_rsb_flushing_done_r) = chan<()>("fd_rsb_flushing_done");

        spawn refilling_shift_buffer::RefillingShiftBuffer<AXI_DATA_W, AXI_ADDR_W> (
            fd_mem_rd_req_s, fd_mem_rd_resp_r,
            fd_rsb_start_req_r, fd_rsb_stop_flush_req_r,
            fd_rsb_ctrl_r, fd_rsb_data_s,
            fd_rsb_flushing_done_s,
        );

        let (fd_ctrl_s, fd_ctrl_r) = chan<FseDecoderCtrl>("fd_ctrl");
        let (fd_finish_s, fd_finish_r) = chan<FseDecoderFinish>("fd_finish");
        let (fd_command_s, fd_command_r) = chan<CommandConstructorData>("fd_command");

        spawn fse_dec::FseDecoder<
            FSE_RAM_DATA_W, FSE_RAM_ADDR_W, FSE_RAM_NUM_PARTITIONS, AXI_DATA_W,
        >(
            fd_ctrl_r, fd_finish_s,
            fd_rsb_ctrl_s, fd_rsb_data_r,
            fd_command_s,
            ll_rd_req_s, ll_rd_resp_r,
            ml_rd_req_s, ml_rd_resp_r,
            of_rd_req_s, of_rd_resp_r,
        );

        spawn SequenceDecoderCtrl<AXI_ADDR_W>(
            req_r, resp_s,
            scd_req_s, scd_resp_r,
            fld_req_s, fld_resp_r,
            fse_demux_req_s, fse_demux_resp_r,
            ll_demux_req_s, ll_demux_resp_r,
            of_demux_req_s, of_demux_resp_r,
            ml_demux_req_s, ml_demux_resp_r,
        );

        (
            fd_ctrl_s, fd_finish_r,
            fd_rsb_ctrl_r, fd_rsb_data_s,
        )
    }

    next(state: ()) {
        ()
    }
}

const TEST_AXI_ADDR_W = u32:32;
const TEST_AXI_DATA_W = u32:64;
const TEST_AXI_DEST_W = u32:8;
const TEST_AXI_ID_W = u32:8;

const TEST_DPD_RAM_DATA_W = u32:16;
const TEST_DPD_RAM_SIZE = u32:256;
const TEST_DPD_RAM_ADDR_W = std::clog2(TEST_DPD_RAM_SIZE);
const TEST_DPD_RAM_WORD_PARTITION_SIZE = TEST_DPD_RAM_DATA_W;
const TEST_DPD_RAM_NUM_PARTITIONS = ram::num_partitions(TEST_DPD_RAM_WORD_PARTITION_SIZE, TEST_DPD_RAM_DATA_W);

const TEST_FSE_RAM_DATA_W = u32:48;
const TEST_FSE_RAM_SIZE = u32:256;
const TEST_FSE_RAM_ADDR_W = std::clog2(TEST_FSE_RAM_SIZE);
const TEST_FSE_RAM_WORD_PARTITION_SIZE = TEST_FSE_RAM_DATA_W / u32:3;
const TEST_FSE_RAM_NUM_PARTITIONS = ram::num_partitions(TEST_FSE_RAM_WORD_PARTITION_SIZE, TEST_FSE_RAM_DATA_W);

const TEST_TMP_RAM_DATA_W = u32:16;
const TEST_TMP_RAM_SIZE = u32:256;
const TEST_TMP_RAM_ADDR_W = std::clog2(TEST_TMP_RAM_SIZE);
const TEST_TMP_RAM_WORD_PARTITION_SIZE = TEST_TMP_RAM_DATA_W;
const TEST_TMP_RAM_NUM_PARTITIONS = ram::num_partitions(TEST_TMP_RAM_WORD_PARTITION_SIZE, TEST_TMP_RAM_DATA_W);


#[test_proc]
proc SequenceDecoderTest {
    type Req = SequenceDecoderReq<TEST_AXI_ADDR_W>;
    type Resp = SequenceDecoderResp;

    type DpdRamRdReq = ram::ReadReq<TEST_DPD_RAM_ADDR_W, TEST_DPD_RAM_NUM_PARTITIONS>;
    type DpdRamRdResp = ram::ReadResp<TEST_DPD_RAM_DATA_W>;
    type DpdRamWrReq = ram::WriteReq<TEST_DPD_RAM_ADDR_W, TEST_DPD_RAM_DATA_W, TEST_DPD_RAM_NUM_PARTITIONS>;
    type DpdRamWrResp = ram::WriteResp;

    type TmpRamRdReq = ram::ReadReq<TEST_TMP_RAM_ADDR_W, TEST_TMP_RAM_NUM_PARTITIONS>;
    type TmpRamRdResp = ram::ReadResp<TEST_TMP_RAM_DATA_W>;
    type TmpRamWrReq = ram::WriteReq<TEST_TMP_RAM_ADDR_W, TEST_TMP_RAM_DATA_W, TEST_TMP_RAM_NUM_PARTITIONS>;
    type TmpRamWrResp = ram::WriteResp;

    type FseRamRdReq = ram::ReadReq<TEST_FSE_RAM_ADDR_W, TEST_FSE_RAM_NUM_PARTITIONS>;
    type FseRamRdResp = ram::ReadResp<TEST_FSE_RAM_DATA_W>;
    type FseRamWrReq = ram::WriteReq<TEST_FSE_RAM_ADDR_W, TEST_FSE_RAM_DATA_W, TEST_FSE_RAM_NUM_PARTITIONS>;
    type FseRamWrResp = ram::WriteResp;

    type MemAxiAr = axi::AxiAr<TEST_AXI_ADDR_W, TEST_AXI_ID_W>;
    type MemAxiR = axi::AxiR<TEST_AXI_DATA_W, TEST_AXI_ID_W>;

    terminator: chan<bool> out;

    req_s: chan<Req> out;
    resp_r: chan<Resp> in;

    ss_axi_ar_r: chan<MemAxiAr> in;
    ss_axi_r_s: chan<MemAxiR> out;

    fl_axi_ar_r: chan<MemAxiAr> in;
    fl_axi_r_s: chan<MemAxiR> out;

    fd_axi_ar_r: chan<MemAxiAr> in;
    fd_axi_r_s: chan<MemAxiR> out;

    init { }

    config(
        terminator: chan<bool> out
    ) {
        // RAM for probability distribution
        let (dpd_rd_req_s, dpd_rd_req_r) = chan<DpdRamRdReq>("dpd_rd_req");
        let (dpd_rd_resp_s, dpd_rd_resp_r) = chan<DpdRamRdResp>("dpd_rd_resp");
        let (dpd_wr_req_s, dpd_wr_req_r) = chan<DpdRamWrReq>("dpd_wr_req");
        let (dpd_wr_resp_s, dpd_wr_resp_r) = chan<DpdRamWrResp>("dpd_wr_resp");

        spawn ram::RamModel<
            TEST_DPD_RAM_DATA_W,
            TEST_DPD_RAM_SIZE,
            TEST_DPD_RAM_WORD_PARTITION_SIZE
        >(dpd_rd_req_r, dpd_rd_resp_s, dpd_wr_req_r, dpd_wr_resp_s);

        // RAMs for temporary values when decoding probability distribution
        let (tmp_rd_req_s, tmp_rd_req_r) = chan<TmpRamRdReq>("tmp_rd_req");
        let (tmp_rd_resp_s, tmp_rd_resp_r) = chan<TmpRamRdResp>("tmp_rd_resp");
        let (tmp_wr_req_s, tmp_wr_req_r) = chan<TmpRamWrReq>("tmp_wr_req");
        let (tmp_wr_resp_s, tmp_wr_resp_r) = chan<TmpRamWrResp>("tmp_wr_resp");

        spawn ram::RamModel<
            TEST_TMP_RAM_DATA_W,
            TEST_TMP_RAM_SIZE,
            TEST_TMP_RAM_WORD_PARTITION_SIZE
        >(tmp_rd_req_r, tmp_rd_resp_s, tmp_wr_req_r, tmp_wr_resp_s);

        // RAM with default FSE lookup for Literal Lengths
        let (ll_def_fse_rd_req_s, ll_def_fse_rd_req_r) = chan<FseRamRdReq>("ll_def_fse_rd_req");
        let (ll_def_fse_rd_resp_s, ll_def_fse_rd_resp_r) = chan<FseRamRdResp>("ll_def_fse_rd_resp");
        let (ll_def_fse_wr_req_s, ll_def_fse_wr_req_r) = chan<FseRamWrReq>("ll_def_fse_wr_req");
        let (ll_def_fse_wr_resp_s, ll_def_fse_wr_resp_r) = chan<FseRamWrResp>("ll_def_fse_wr_resp");

        spawn ram::RamModel<
            TEST_FSE_RAM_DATA_W,
            TEST_FSE_RAM_SIZE,
            TEST_FSE_RAM_WORD_PARTITION_SIZE
        >(ll_def_fse_rd_req_r, ll_def_fse_rd_resp_s, ll_def_fse_wr_req_r, ll_def_fse_wr_resp_s);

        // RAM for FSE lookup for Literal Lengths
        let (ll_fse_rd_req_s, ll_fse_rd_req_r) = chan<FseRamRdReq>("ll_fse_rd_req");
        let (ll_fse_rd_resp_s, ll_fse_rd_resp_r) = chan<FseRamRdResp>("ll_fse_rd_resp");
        let (ll_fse_wr_req_s, ll_fse_wr_req_r) = chan<FseRamWrReq>("ll_fse_wr_req");
        let (ll_fse_wr_resp_s, ll_fse_wr_resp_r) = chan<FseRamWrResp>("ll_fse_wr_resp");

        spawn ram::RamModel<
            TEST_FSE_RAM_DATA_W,
            TEST_FSE_RAM_SIZE,
            TEST_FSE_RAM_WORD_PARTITION_SIZE
        >(ll_fse_rd_req_r, ll_fse_rd_resp_s, ll_fse_wr_req_r, ll_fse_wr_resp_s);

        // RAM with default FSE lookup for Match Lengths
        let (ml_def_fse_rd_req_s, ml_def_fse_rd_req_r) = chan<FseRamRdReq>("ml_def_fse_rd_req");
        let (ml_def_fse_rd_resp_s, ml_def_fse_rd_resp_r) = chan<FseRamRdResp>("ml_def_fse_rd_resp");
        let (ml_def_fse_wr_req_s, ml_def_fse_wr_req_r) = chan<FseRamWrReq>("ml_def_fse_wr_req");
        let (ml_def_fse_wr_resp_s, ml_def_fse_wr_resp_r) = chan<FseRamWrResp>("ml_def_fse_wr_resp");

        spawn ram::RamModel<
            TEST_FSE_RAM_DATA_W,
            TEST_FSE_RAM_SIZE,
            TEST_FSE_RAM_WORD_PARTITION_SIZE
        >(ml_def_fse_rd_req_r, ml_def_fse_rd_resp_s, ml_def_fse_wr_req_r, ml_def_fse_wr_resp_s);

        // RAM for FSE lookup for Match Lengths
        let (ml_fse_rd_req_s, ml_fse_rd_req_r) = chan<FseRamRdReq>("ml_fse_rd_req");
        let (ml_fse_rd_resp_s, ml_fse_rd_resp_r) = chan<FseRamRdResp>("ml_fse_rd_resp");
        let (ml_fse_wr_req_s, ml_fse_wr_req_r) = chan<FseRamWrReq>("ml_fse_wr_req");
        let (ml_fse_wr_resp_s, ml_fse_wr_resp_r) = chan<FseRamWrResp>("ml_fse_wr_resp");

        spawn ram::RamModel<
            TEST_FSE_RAM_DATA_W,
            TEST_FSE_RAM_SIZE,
            TEST_FSE_RAM_WORD_PARTITION_SIZE
        >(ml_fse_rd_req_r, ml_fse_rd_resp_s, ml_fse_wr_req_r, ml_fse_wr_resp_s);

        // RAM with default FSE lookup for Offsets
        let (of_def_fse_rd_req_s, of_def_fse_rd_req_r) = chan<FseRamRdReq>("of_def_fse_rd_req");
        let (of_def_fse_rd_resp_s, of_def_fse_rd_resp_r) = chan<FseRamRdResp>("of_def_fse_rd_resp");
        let (of_def_fse_wr_req_s, of_def_fse_wr_req_r) = chan<FseRamWrReq>("of_def_fse_wr_req");
        let (of_def_fse_wr_resp_s, of_def_fse_wr_resp_r) = chan<FseRamWrResp>("of_def_fse_wr_resp");

        spawn ram::RamModel<
            TEST_FSE_RAM_DATA_W,
            TEST_FSE_RAM_SIZE,
            TEST_FSE_RAM_WORD_PARTITION_SIZE
        >(of_def_fse_rd_req_r, of_def_fse_rd_resp_s, of_def_fse_wr_req_r, of_def_fse_wr_resp_s);

        // RAM for FSE lookup for Offsets
        let (of_fse_rd_req_s, of_fse_rd_req_r) = chan<FseRamRdReq>("of_fse_rd_req");
        let (of_fse_rd_resp_s, of_fse_rd_resp_r) = chan<FseRamRdResp>("of_fse_rd_resp");
        let (of_fse_wr_req_s, of_fse_wr_req_r) = chan<FseRamWrReq>("of_fse_wr_req");
        let (of_fse_wr_resp_s, of_fse_wr_resp_r) = chan<FseRamWrResp>("of_fse_wr_resp");

        spawn ram::RamModel<
            TEST_FSE_RAM_DATA_W,
            TEST_FSE_RAM_SIZE,
            TEST_FSE_RAM_WORD_PARTITION_SIZE
        >(of_fse_rd_req_r, of_fse_rd_resp_s, of_fse_wr_req_r, of_fse_wr_resp_s);

        // Sequence Decoder

        let (req_s, req_r) = chan<Req>("req");
        let (resp_s, resp_r) = chan<Resp>("resp");

        let (ss_axi_ar_s, ss_axi_ar_r) = chan<MemAxiAr>("ss_axi_ar");
        let (ss_axi_r_s, ss_axi_r_r) = chan<MemAxiR>("ss_axi_r");

        let (fl_axi_ar_s, fl_axi_ar_r) = chan<MemAxiAr>("fl_axi_ar");
        let (fl_axi_r_s, fl_axi_r_r) = chan<MemAxiR>("fl_axi_r");

        let (fd_axi_ar_s, fd_axi_ar_r) = chan<MemAxiAr>("fd_axi_ar");
        let (fd_axi_r_s, fd_axi_r_r) = chan<MemAxiR>("fd_axi_r");


        spawn SequenceDecoder<
            TEST_AXI_ADDR_W, TEST_AXI_DATA_W, TEST_AXI_DEST_W, TEST_AXI_ID_W,
            TEST_DPD_RAM_ADDR_W, TEST_DPD_RAM_DATA_W, TEST_DPD_RAM_NUM_PARTITIONS,
            TEST_TMP_RAM_ADDR_W, TEST_TMP_RAM_DATA_W, TEST_TMP_RAM_NUM_PARTITIONS,
            TEST_FSE_RAM_ADDR_W, TEST_FSE_RAM_DATA_W, TEST_FSE_RAM_NUM_PARTITIONS,
        > (
            ss_axi_ar_s, ss_axi_r_r,
            fl_axi_ar_s, fl_axi_r_r,
            fd_axi_ar_s, fd_axi_r_r,

            req_r, resp_s,

            dpd_rd_req_s, dpd_rd_resp_r, dpd_wr_req_s, dpd_wr_resp_r,
            tmp_rd_req_s, tmp_rd_resp_r, tmp_wr_req_s, tmp_wr_resp_r,

            ll_def_fse_rd_req_s, ll_def_fse_rd_resp_r, ll_def_fse_wr_req_s, ll_def_fse_wr_resp_r,
            ll_fse_rd_req_s, ll_fse_rd_resp_r, ll_fse_wr_req_s, ll_fse_wr_resp_r,
            ml_def_fse_rd_req_s, ml_def_fse_rd_resp_r, ml_def_fse_wr_req_s, ml_def_fse_wr_resp_r,
            ml_fse_rd_req_s, ml_fse_rd_resp_r, ml_fse_wr_req_s, ml_fse_wr_resp_r,
            of_def_fse_rd_req_s, of_def_fse_rd_resp_r, of_def_fse_wr_req_s, of_def_fse_wr_resp_r,
            of_fse_rd_req_s, of_fse_rd_resp_r, of_fse_wr_req_s, of_fse_wr_resp_r,
        );

        (
            terminator,
            req_s, resp_r,
            ss_axi_ar_r, ss_axi_r_s,
            fl_axi_ar_r, fl_axi_r_s,
            fd_axi_ar_r, fd_axi_r_s,
        )
    }

    next(state: ()) {
        let tok = join();
        trace_fmt!("SequenceDecoderTest");
        send(tok, terminator, true);
    }
}
