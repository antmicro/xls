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
import xls.modules.zstd.huffman_literals_dec;
import xls.modules.zstd.parallel_rams;
import xls.modules.zstd.literals_buffer;
import xls.modules.zstd.sequence_dec;
import xls.modules.zstd.literals_block_header_dec;
import xls.modules.zstd.literals_decoder;
import xls.modules.zstd.command_constructor;
import xls.modules.zstd.memory.axi;
import xls.modules.zstd.memory.mem_reader;
import xls.modules.zstd.fse_proba_freq_dec;


struct CompressBlockDecoderReq<AXI_ADDR_W: u32> { 
    addr: uN[AXI_ADDR_W],
    length: uN[AXI_ADDR_W],
    id: u32,
    last_block: bool,
}
struct CompressBlockDecoderResp { }

proc CompressBlockDecoder<
    // AXI parameters
    AXI_DATA_W: u32, AXI_ADDR_W: u32, AXI_ID_W: u32, AXI_DEST_W: u32,

    // FSE lookup table RAMs
    DPD_RAM_ADDR_W: u32, DPD_RAM_DATA_W: u32, DPD_RAM_NUM_PARTITIONS: u32,
    TMP_RAM_ADDR_W: u32, TMP_RAM_DATA_W: u32, TMP_RAM_NUM_PARTITIONS: u32,
    FSE_RAM_ADDR_W: u32, FSE_RAM_DATA_W: u32, FSE_RAM_NUM_PARTITIONS: u32,

    // for literals decoder
    HISTORY_BUFFER_SIZE_KB: u32 = {common::HISTORY_BUFFER_SIZE_KB},

    // FSE proba
    FSE_PROBA_DIST_W: u32 = {u32:16},
    FSE_PROBA_MAX_DISTS: u32 = {u32:256},

    // constants
    AXI_DATA_W_DIV8: u32 = {AXI_DATA_W / u32:8},

    // Huffman weights memory parameters
    HUFFMAN_WEIGHTS_RAM_ADDR_WIDTH: u32 = {huffman_literals_dec::WEIGHTS_ADDR_WIDTH},
    HUFFMAN_WEIGHTS_RAM_DATA_WIDTH: u32 = {huffman_literals_dec::WEIGHTS_DATA_WIDTH},
    HUFFMAN_WEIGHTS_RAM_NUM_PARTITIONS: u32 = {huffman_literals_dec::WEIGHTS_NUM_PARTITIONS},
    // Huffman prescan memory parameters
    HUFFMAN_PRESCAN_RAM_ADDR_WIDTH: u32 = {huffman_literals_dec::PRESCAN_ADDR_WIDTH},
    HUFFMAN_PRESCAN_RAM_DATA_WIDTH: u32 = {huffman_literals_dec::PRESCAN_DATA_WIDTH},
    HUFFMAN_PRESCAN_RAM_NUM_PARTITIONS: u32 = {huffman_literals_dec::PRESCAN_NUM_PARTITIONS},
    // Literals buffer memory parameters
    LITERALS_BUFFER_RAM_ADDR_WIDTH: u32 = {parallel_rams::ram_addr_width(HISTORY_BUFFER_SIZE_KB)},
    LITERALS_BUFFER_RAM_DATA_WIDTH: u32 = {literals_buffer::RAM_DATA_WIDTH},
    LITERALS_BUFFER_RAM_NUM_PARTITIONS: u32 = {literals_buffer::RAM_NUM_PARTITIONS},
> {
    type Req = CompressBlockDecoderReq;
    type Resp = CompressBlockDecoderResp;

    type SequenceDecReq = sequence_dec::SequenceDecoderReq<AXI_ADDR_W>;
    type SequenceDecResp = sequence_dec::SequenceDecoderResp;

    type MemReaderReq  = mem_reader::MemReaderReq<AXI_ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<AXI_DATA_W, AXI_ADDR_W>;

    type MemAxiAr = axi::AxiAr<AXI_ADDR_W, AXI_ID_W>;
    type MemAxiR = axi::AxiR<AXI_DATA_W, AXI_ID_W>;
    type MemAxiAw = axi::AxiAw<AXI_ADDR_W, AXI_ID_W>;
    type MemAxiW = axi::AxiW<AXI_DATA_W, AXI_DATA_W_DIV8>;
    type MemAxiB = axi::AxiB<AXI_ID_W>;

    //type ShiftBufferInput = shift_buffer::ShiftBuffrInput<DATA_WIDTH, LENGTH_WIDTH>;
    //type ShiftBufferCtrl = shift_buffer::ShiftBufferCtrl<LENGTH_WIDTH>;
    //type ShiftBufferOutput = shift_buffer::ShiftBufferOutput<DATA_WIDTH, LENGTH_WIDTH>;

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

    type LiteralsHeaderDecoderResp = literals_block_header_dec::LiteralsHeaderDecoderResp;
    type LiteralsBlockType = literals_block_header_dec::LiteralsBlockType;
    type LiteralsDecReq = literals_decoder::LiteralsDecoderCtrlReq<AXI_ADDR_W>;
    type LiteralsDecResp = literals_decoder::LiteralsDecoderCtrlResp;
    type LiteralsBufCtrl = common::LiteralsBufferCtrl;
    type SequenceExecutorPacket = common::SequenceExecutorPacket<common::SYMBOL_WIDTH>;
    type CommandConstructorData = common::CommandConstructorData;

    type HuffmanWeightsReadReq    = ram::ReadReq<HUFFMAN_WEIGHTS_RAM_ADDR_WIDTH, HUFFMAN_WEIGHTS_RAM_NUM_PARTITIONS>;
    type HuffmanWeightsReadResp   = ram::ReadResp<HUFFMAN_WEIGHTS_RAM_DATA_WIDTH>;
    type HuffmanPrescanReadReq    = ram::ReadReq<HUFFMAN_PRESCAN_RAM_ADDR_WIDTH, HUFFMAN_PRESCAN_RAM_NUM_PARTITIONS>;
    type HuffmanPrescanReadResp   = ram::ReadResp<HUFFMAN_PRESCAN_RAM_DATA_WIDTH>;
    type HuffmanPrescanWriteReq   = ram::WriteReq<HUFFMAN_PRESCAN_RAM_ADDR_WIDTH, HUFFMAN_PRESCAN_RAM_DATA_WIDTH, HUFFMAN_PRESCAN_RAM_NUM_PARTITIONS>;
    type HuffmanPrescanWriteResp  = ram::WriteResp;

    type LitBufRamRdReq = ram::ReadReq<LITERALS_BUFFER_RAM_ADDR_WIDTH, LITERALS_BUFFER_RAM_NUM_PARTITIONS>;
    type LitBufRamRdResp = ram::ReadResp<LITERALS_BUFFER_RAM_DATA_WIDTH>;
    type LitBufRamWrReq = ram::WriteReq<LITERALS_BUFFER_RAM_ADDR_WIDTH, LITERALS_BUFFER_RAM_DATA_WIDTH, LITERALS_BUFFER_RAM_NUM_PARTITIONS>;
    type LitBufRamWrResp = ram::WriteResp;

    type AxiAddrW = uN[AXI_ADDR_W];

    req_r: chan<Req> in;
    resp_s: chan<Resp> out;

    lit_ctrl_req_s: chan<LiteralsDecReq> out;
    lit_header_r: chan<LiteralsHeaderDecoderResp> in;
    lit_ctrl_resp_r: chan<LiteralsDecResp> in;

    seq_dec_req_s: chan<SequenceDecReq> out;
    seq_dec_resp_r: chan<SequenceDecResp> in;

    init {}

    config(
        req_r: chan<Req> in,
        resp_s: chan<Resp> out,

        // output from Command constructor to Sequence executor
        cmd_constr_out_s: chan<SequenceExecutorPacket> out,

        // Sequence Decoder channels

        // Sequence Conf Decoder (manager)
        scd_axi_ar_s: chan<MemAxiAr> out,
        scd_axi_r_r: chan<MemAxiR> in,

        // Fse Lookup Decoder (manager)
        fld_axi_ar_s: chan<MemAxiAr> out,
        fld_axi_r_r: chan<MemAxiR> in,

        // FSE decoder (manager)
        fd_axi_ar_s: chan<MemAxiAr> out,
        fd_axi_r_r: chan<MemAxiR> in,

        // RAMs for FSE decoder
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

        // Literals decoder channels

        // AXI Literals Header Decoder (manager)
        lit_header_axi_ar_s: chan<MemAxiAr> out,
        lit_header_axi_r_r: chan<MemAxiR> in,

        // AXI Raw Literals Decoder (manager)
        raw_lit_axi_ar_s: chan<MemAxiAr> out,
        raw_lit_axi_r_r: chan<MemAxiR> in,

        // AXI Huffman Literals Decoder (manager)
        huffman_lit_axi_ar_s: chan<MemAxiAr> out,
        huffman_lit_axi_r_r: chan<MemAxiR> in,

        // Literals buffer internal memory
        rd_req_m0_s: chan<LitBufRamRdReq> out,
        rd_req_m1_s: chan<LitBufRamRdReq> out,
        rd_req_m2_s: chan<LitBufRamRdReq> out,
        rd_req_m3_s: chan<LitBufRamRdReq> out,
        rd_req_m4_s: chan<LitBufRamRdReq> out,
        rd_req_m5_s: chan<LitBufRamRdReq> out,
        rd_req_m6_s: chan<LitBufRamRdReq> out,
        rd_req_m7_s: chan<LitBufRamRdReq> out,
        rd_resp_m0_r: chan<LitBufRamRdResp> in,
        rd_resp_m1_r: chan<LitBufRamRdResp> in,
        rd_resp_m2_r: chan<LitBufRamRdResp> in,
        rd_resp_m3_r: chan<LitBufRamRdResp> in,
        rd_resp_m4_r: chan<LitBufRamRdResp> in,
        rd_resp_m5_r: chan<LitBufRamRdResp> in,
        rd_resp_m6_r: chan<LitBufRamRdResp> in,
        rd_resp_m7_r: chan<LitBufRamRdResp> in,
        wr_req_m0_s: chan<LitBufRamWrReq> out,
        wr_req_m1_s: chan<LitBufRamWrReq> out,
        wr_req_m2_s: chan<LitBufRamWrReq> out,
        wr_req_m3_s: chan<LitBufRamWrReq> out,
        wr_req_m4_s: chan<LitBufRamWrReq> out,
        wr_req_m5_s: chan<LitBufRamWrReq> out,
        wr_req_m6_s: chan<LitBufRamWrReq> out,
        wr_req_m7_s: chan<LitBufRamWrReq> out,
        wr_resp_m0_r: chan<LitBufRamWrResp> in,
        wr_resp_m1_r: chan<LitBufRamWrResp> in,
        wr_resp_m2_r: chan<LitBufRamWrResp> in,
        wr_resp_m3_r: chan<LitBufRamWrResp> in,
        wr_resp_m4_r: chan<LitBufRamWrResp> in,
        wr_resp_m5_r: chan<LitBufRamWrResp> in,
        wr_resp_m6_r: chan<LitBufRamWrResp> in,
        wr_resp_m7_r: chan<LitBufRamWrResp> in,

        // Huffman weights memory
        huffman_lit_weights_mem_rd_req_s: chan<HuffmanWeightsReadReq> out,
        huffman_lit_weights_mem_rd_resp_r: chan<HuffmanWeightsReadResp> in,

        // Huffman prescan memory
        huffman_lit_prescan_mem_rd_req_s: chan<HuffmanPrescanReadReq> out,
        huffman_lit_prescan_mem_rd_resp_r: chan<HuffmanPrescanReadResp> in,
        huffman_lit_prescan_mem_wr_req_s: chan<HuffmanPrescanWriteReq> out,
        huffman_lit_prescan_mem_wr_resp_r: chan<HuffmanPrescanWriteResp> in,

    ) {
        // TODO: for consistency all MemReaders should be in toplevel ZSTD decoder
        // so we should move them up in the hierarchy from LiteralsDecoder
        // and SequenceDecoder to the toplevel

        let (lit_ctrl_req_s, lit_ctrl_req_r) = chan<LiteralsDecReq>("lit_ctrl_req");
        let (lit_ctrl_resp_s, lit_ctrl_resp_r) = chan<LiteralsDecResp>("lit_ctrl_resp");
        let (lit_buf_ctrl_s, lit_buf_ctrl_r) = chan<LiteralsBufCtrl>("lit_buf_ctrl");
        let (lit_buf_out_s, lit_buf_out_r) = chan<SequenceExecutorPacket>("lit_buf_out");
        let (lit_header_s, lit_header_r) = chan<LiteralsHeaderDecoderResp>("lit_header");

        spawn literals_decoder::LiteralsDecoder<
            HISTORY_BUFFER_SIZE_KB,
            AXI_DATA_W, AXI_ADDR_W, AXI_ID_W, AXI_DEST_W
        >(
            // TODO: more axi channels to come
            lit_header_axi_ar_s, lit_header_axi_r_r,
            raw_lit_axi_ar_s, raw_lit_axi_r_r,
            huffman_lit_axi_ar_s, huffman_lit_axi_r_r,
            lit_ctrl_req_r, lit_ctrl_resp_s,
            lit_buf_ctrl_r, lit_buf_out_s,
            // TODO: LiteralsHeaderDecoderResp_s channel
            // lit_header_s
            rd_req_m0_s, rd_req_m1_s, rd_req_m2_s, rd_req_m3_s, rd_req_m4_s, rd_req_m5_s, rd_req_m6_s, rd_req_m7_s,
            rd_resp_m0_r, rd_resp_m1_r, rd_resp_m2_r, rd_resp_m3_r, rd_resp_m4_r, rd_resp_m5_r, rd_resp_m6_r, rd_resp_m7_r,
            wr_req_m0_s, wr_req_m1_s, wr_req_m2_s, wr_req_m3_s, wr_req_m4_s, wr_req_m5_s, wr_req_m6_s, wr_req_m7_s,
            wr_resp_m0_r, wr_resp_m1_r, wr_resp_m2_r, wr_resp_m3_r, wr_resp_m4_r, wr_resp_m5_r, wr_resp_m6_r, wr_resp_m7_r,
            huffman_lit_weights_mem_rd_req_s, huffman_lit_weights_mem_rd_resp_r,
            huffman_lit_prescan_mem_rd_req_s, huffman_lit_prescan_mem_rd_resp_r,
            huffman_lit_prescan_mem_wr_req_s, huffman_lit_prescan_mem_wr_resp_r,
        );

        let (seq_dec_req_s, seq_dec_req_r) = chan<SequenceDecReq>("seq_dec_req");
        let (seq_dec_resp_s, seq_dec_resp_r) = chan<SequenceDecResp>("seq_dec_resp");
        let (seq_dec_command_s, seq_dec_command_r) = chan<CommandConstructorData>("seq_dec_command");

        spawn sequence_dec::SequenceDecoder<
            AXI_ADDR_W, AXI_DATA_W, AXI_DEST_W, AXI_ID_W,
            DPD_RAM_ADDR_W, DPD_RAM_DATA_W, DPD_RAM_NUM_PARTITIONS,
            TMP_RAM_ADDR_W, TMP_RAM_DATA_W, TMP_RAM_NUM_PARTITIONS,
            FSE_RAM_ADDR_W, FSE_RAM_DATA_W, FSE_RAM_NUM_PARTITIONS,
        >(
            scd_axi_ar_s, scd_axi_r_r,
            fld_axi_ar_s, fld_axi_r_r,
            fd_axi_ar_s, fd_axi_r_r,
            seq_dec_req_r, seq_dec_resp_s,
            // FIXME: missing channel for arrow between FSE decoder and CommandConstructor
            // channel is called fd_command_s in SequenceDecoder
            // seq_dec_command_s,
            dpd_rd_req_s, dpd_rd_resp_r, dpd_wr_req_s, dpd_wr_resp_r,
            tmp_rd_req_s, tmp_rd_resp_r, tmp_wr_req_s, tmp_wr_resp_r,
            ll_def_fse_rd_req_s, ll_def_fse_rd_resp_r, ll_def_fse_wr_req_s, ll_def_fse_wr_resp_r,
            ll_fse_rd_req_s, ll_fse_rd_resp_r, ll_fse_wr_req_s, ll_fse_wr_resp_r,
            ml_def_fse_rd_req_s, ml_def_fse_rd_resp_r, ml_def_fse_wr_req_s, ml_def_fse_wr_resp_r,
            ml_fse_rd_req_s, ml_fse_rd_resp_r, ml_fse_wr_req_s, ml_fse_wr_resp_r,
            of_def_fse_rd_req_s, of_def_fse_rd_resp_r, of_def_fse_wr_req_s, of_def_fse_wr_resp_r,
            of_fse_rd_req_s, of_fse_rd_resp_r, of_fse_wr_req_s, of_fse_wr_resp_r,
        );

        spawn command_constructor::CommandConstructor(
            seq_dec_command_r,
            cmd_constr_out_s,
            lit_buf_out_r,
            lit_buf_ctrl_s,
        );

        (
            req_r, resp_s,
            lit_ctrl_req_s, lit_header_r, lit_ctrl_resp_r,
            seq_dec_req_s, seq_dec_resp_r,
        )
    }

    next(_: ()) {
        let tok = join();

        let (tok_req, req) = recv(tok, req_r);
        let tok_lit1 = send(tok_req, lit_ctrl_req_s, LiteralsDecReq {
            addr: req.addr,
            literals_last: req.last_block,
        });
        let (tok_lit2, lit_header) = recv(tok_lit1, lit_header_r);
        
        let seq_section_offset = lit_header.length as AxiAddrW + match (lit_header.header.literal_type) {
            LiteralsBlockType::RAW => lit_header.regenerated_size,
            LiteralsBlockType::RLE => AxiAddrW:1,
            LiteralsBlockType::COMP | LiteralsBlockType::COMP_4 => lit_header.compressed_size,
            LiteralsBlockType::TREELESS | LiteralsBlockType::TREELESS_4 => lit_header.compressed_size,
            _ => fail!("comp_block_dec_unreachable", AxiAddrW:0),
        } as AxiAddrW;
        let seq_section_start = req.addr + seq_section_offset;
         
        let tok_seq = send(tok_lit2, seq_dec_req_s, SequenceDecReq {
            addr: seq_section_start
        });

        let (tok_fin_lit, lit_resp) = recv(tok_lit1, lit_ctrl_resp_r);
        let (tok_fin_seq, seq_resp) = recv(tok_seq, seq_dec_resp_r);

        let tok_finish = join(tok_fin_lit, tok_fin_seq);
        send(tok_finish, resp_s, Resp {});
    }
}

const TEST_AXI_DATA_W = u32:64;
const TEST_AXI_ADDR_W = u32:32;
const TEST_AXI_ID_W = u32:4;
const TEST_AXI_DEST_W = u32:4;

#[test_proc]
proc CompressBlockDecoderTest {
    type Req = CompressBlockDecoderReq;
    type Resp = CompressBlockDecoderResp;

    type MemAxiAr = axi::AxiAr<TEST_AXI_ADDR_W, TEST_AXI_ID_W>;
    type MemAxiR = axi::AxiR<TEST_AXI_DATA_W, TEST_AXI_ID_W>;

    terminator: chan<bool> out;
    // req_s: chan<Req> out;
    // resp_r: chan<Resp> in;
    // scd_axi_ar_r: chan<MemAxiAr> in;
    // scd_axi_r_s: chan<MemAxiR> out;

    init {}
    config(terminator: chan<bool> out) {
        // let (req_s, req_r) = chan<Req>("req");
        // let (resp_s, resp_r) = chan<Resp>("resp");

        // let (scd_axi_ar_s, scd_axi_ar_r) = chan<MemAxiAr>("scd_axi_ar");
        // let (scd_axi_r_s, scd_axi_r_r) = chan<MemAxiR>("scd_axi_r");

        // spawn CompressBlockDecoder<
        //     TEST_AXI_DATA_W, TEST_AXI_ADDR_W, TEST_AXI_ID_W, TEST_AXI_DEST_W
        // >(
        //     req_r, resp_s,
        //     scd_axi_ar_s, scd_axi_r_r);

        // (
        //     terminator,
        //     req_s, resp_r,
        //     scd_axi_ar_r, scd_axi_r_s
        // )
        (terminator,)
    }

    next(state: ()) {
        let tok = join();
        send(tok, terminator, true);
    }
}

