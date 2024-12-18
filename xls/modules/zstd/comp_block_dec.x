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
import xls.modules.zstd.memory.axi_ram;
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
    type Req = CompressBlockDecoderReq<AXI_ADDR_W>;
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
        cmd_constr_out_s: chan<common::ExtendedBlockDataPacket> out,

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
            seq_dec_command_s,
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
            LiteralsBlockType::RAW => lit_header.header.regenerated_size,
            LiteralsBlockType::RLE => u20:1,
            LiteralsBlockType::COMP | LiteralsBlockType::COMP_4 => lit_header.header.compressed_size,
            LiteralsBlockType::TREELESS | LiteralsBlockType::TREELESS_4 => lit_header.header.compressed_size,
            _ => fail!("comp_block_dec_unreachable", u20:0),
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

const TEST_CASE_RAM_DATA_WIDTH = u32:64;
const TEST_CASE_RAM_SIZE = u32:256;
const TEST_CASE_RAM_ADDR_WIDTH = std::clog2(TEST_CASE_RAM_SIZE);
const TEST_CASE_RAM_WORD_PARTITION_SIZE = TEST_CASE_RAM_DATA_WIDTH / u32:8;
const TEST_CASE_RAM_NUM_PARTITIONS = ram::num_partitions(
    TEST_CASE_RAM_WORD_PARTITION_SIZE, TEST_CASE_RAM_DATA_WIDTH);
const TEST_CASE_RAM_BASE_ADDR = u32:0;

const TEST_AXI_DATA_W = u32:64;
const TEST_AXI_ADDR_W = u32:32;
const TEST_AXI_ID_W = u32:4;
const TEST_AXI_DEST_W = u32:4;
const TEST_AXI_DATA_W_DIV8 = TEST_AXI_DATA_W / u32:8;

const TEST_DPD_RAM_DATA_W = u32:16;
const TEST_DPD_RAM_SIZE = u32:256;
const TEST_DPD_RAM_ADDR_W = std::clog2(TEST_DPD_RAM_SIZE);
const TEST_DPD_RAM_WORD_PARTITION_SIZE = TEST_DPD_RAM_DATA_W;
const TEST_DPD_RAM_NUM_PARTITIONS = ram::num_partitions(
    TEST_DPD_RAM_WORD_PARTITION_SIZE, TEST_DPD_RAM_DATA_W);

const TEST_FSE_RAM_DATA_W = u32:48;
const TEST_FSE_RAM_SIZE = u32:256;
const TEST_FSE_RAM_ADDR_W = std::clog2(TEST_FSE_RAM_SIZE);
const TEST_FSE_RAM_WORD_PARTITION_SIZE = TEST_FSE_RAM_DATA_W / u32:3;
const TEST_FSE_RAM_NUM_PARTITIONS = ram::num_partitions(
    TEST_FSE_RAM_WORD_PARTITION_SIZE, TEST_FSE_RAM_DATA_W);

const TEST_TMP_RAM_DATA_W = u32:16;
const TEST_TMP_RAM_SIZE = u32:256;
const TEST_TMP_RAM_ADDR_W = std::clog2(TEST_TMP_RAM_SIZE);
const TEST_TMP_RAM_WORD_PARTITION_SIZE = TEST_TMP_RAM_DATA_W;
const TEST_TMP_RAM_NUM_PARTITIONS = ram::num_partitions(
    TEST_TMP_RAM_WORD_PARTITION_SIZE, TEST_TMP_RAM_DATA_W);

const HISTORY_BUFFER_SIZE_KB = common::HISTORY_BUFFER_SIZE_KB;

const HUFFMAN_WEIGHTS_RAM_ADDR_WIDTH: u32 = huffman_literals_dec::WEIGHTS_ADDR_WIDTH;
const HUFFMAN_WEIGHTS_RAM_DATA_WIDTH: u32 = huffman_literals_dec::WEIGHTS_DATA_WIDTH;
const HUFFMAN_WEIGHTS_RAM_NUM_PARTITIONS: u32 = huffman_literals_dec::WEIGHTS_NUM_PARTITIONS;
// Huffman prescan memory parameters
const HUFFMAN_PRESCAN_RAM_ADDR_WIDTH: u32 = huffman_literals_dec::PRESCAN_ADDR_WIDTH;
const HUFFMAN_PRESCAN_RAM_DATA_WIDTH: u32 = huffman_literals_dec::PRESCAN_DATA_WIDTH;
const HUFFMAN_PRESCAN_RAM_NUM_PARTITIONS: u32 = huffman_literals_dec::PRESCAN_NUM_PARTITIONS;
// Literals buffer memory parameters
const LITERALS_BUFFER_RAM_ADDR_WIDTH: u32 = parallel_rams::ram_addr_width(HISTORY_BUFFER_SIZE_KB);
const LITERALS_BUFFER_RAM_SIZE: u32 = parallel_rams::ram_size(HISTORY_BUFFER_SIZE_KB);
const LITERALS_BUFFER_RAM_DATA_WIDTH: u32 = literals_buffer::RAM_DATA_WIDTH;
const LITERALS_BUFFER_RAM_NUM_PARTITIONS: u32 = literals_buffer::RAM_NUM_PARTITIONS;
const LITERALS_BUFFER_RAM_WORD_PARTITION_SIZE: u32 = LITERALS_BUFFER_RAM_DATA_WIDTH;

const AXI_CHAN_N = u32:6;

type ExtendedPacket = common::ExtendedBlockDataPacket;

const COMP_BLOCK_DEC_TESTCASES: (u64[64], ExtendedPacket[128])[1] = [
    (
        u64[64]:[
            u64:0xff1d25c00e109236,
            u64:0x8aad541ff47ffebb,
            u64:0xc000b000b2687,
            u64:0x98ff7fffffd7ffdf,
            u64:0xffbeff7f7fb3fff3,
            u64:0x8d77dbebfdb9ffbe,
            u64:0xf3ef7dfafdfeceeb,
            u64:0x6fcfe7fff7fbfd7f,
            u64:0x40a8161fb9fdffff,
            u64:0xc0a84df134544ca,
            u64:0x100eec609988403b,
            u64:0xfd6b1ca24d0ce438,
            u64:0xb66651065104a4df,
            u64:0xc84d93392e00e0e9,
            u64:0x2f8e8c7f1081493f,
            u64:0xda8df0c39e029d53,
            u64:0x1ed58bc5d9b01637,
            u64:0x1e85af,
            u64:0, ...
        ],
        ExtendedPacket[128]:[zero!<ExtendedPacket>(), ...])
];

#[test_proc]
proc CompressBlockDecoderTest {
    type Req = CompressBlockDecoderReq<TEST_AXI_ADDR_W>;
    type Resp = CompressBlockDecoderResp;

    type SequenceDecReq = sequence_dec::SequenceDecoderReq<TEST_AXI_ADDR_W>;
    type SequenceDecResp = sequence_dec::SequenceDecoderResp;

    type MemReaderReq  = mem_reader::MemReaderReq<TEST_AXI_ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<TEST_AXI_DATA_W, TEST_AXI_ADDR_W>;

    type MemAxiAr = axi::AxiAr<TEST_AXI_ADDR_W, TEST_AXI_ID_W>;
    type MemAxiR = axi::AxiR<TEST_AXI_DATA_W, TEST_AXI_ID_W>;
    type MemAxiAw = axi::AxiAw<TEST_AXI_ADDR_W, TEST_AXI_ID_W>;
    type MemAxiW = axi::AxiW<TEST_AXI_DATA_W, TEST_AXI_DATA_W_DIV8>;
    type MemAxiB = axi::AxiB<TEST_AXI_ID_W>;

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

    type LiteralsHeaderDecoderResp = literals_block_header_dec::LiteralsHeaderDecoderResp;
    type LiteralsBlockType = literals_block_header_dec::LiteralsBlockType;
    type LiteralsDecReq = literals_decoder::LiteralsDecoderCtrlReq<TEST_AXI_ADDR_W>;
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

    type TestcaseRamRdReq = ram::ReadReq<TEST_CASE_RAM_ADDR_WIDTH, TEST_CASE_RAM_NUM_PARTITIONS>;
    type TestcaseRamRdResp = ram::ReadResp<TEST_CASE_RAM_DATA_WIDTH>;
    type TestcaseRamWrReq = ram::WriteReq<TEST_CASE_RAM_ADDR_WIDTH, TEST_CASE_RAM_DATA_WIDTH, TEST_CASE_RAM_NUM_PARTITIONS>;
    type TestcaseRamWrResp = ram::WriteResp;

    terminator: chan<bool> out;
    req_s: chan<Req> out;
    resp_r: chan<Resp> in;
    cmd_constr_out_r: chan<ExtendedPacket> in;
    axi_ram_wr_req_s: chan<TestcaseRamWrReq>[AXI_CHAN_N] out;
    axi_ram_wr_resp_r: chan<TestcaseRamWrResp>[AXI_CHAN_N] in;

    init {}
    config(terminator: chan<bool> out) {
        let (req_s, req_r) = chan<Req>("req");
        let (resp_s, resp_r) = chan<Resp>("resp");

        // output from Command constructor to Sequence executor
        let (cmd_constr_out_s, cmd_constr_out_r) = chan<ExtendedPacket>("cmd_constr_out");

        // Huffman weights memory
        let (huffman_lit_weights_mem_rd_req_s, _huffman_lit_weights_mem_rd_req_r) = chan<HuffmanWeightsReadReq>("huffman_lit_weights_mem_rd_req");
        let (_huffman_lit_weights_mem_rd_resp_s, huffman_lit_weights_mem_rd_resp_r) = chan<HuffmanWeightsReadResp>("huffman_lit_weights_mem_rd_resp");

        // Huffman prescan memory
        let (huffman_lit_prescan_mem_rd_req_s, _huffman_lit_prescan_mem_rd_req_r) = chan<HuffmanPrescanReadReq>("huffman_lit_prescan_mem_rd_req");
        let (_huffman_lit_prescan_mem_rd_resp_s, huffman_lit_prescan_mem_rd_resp_r) = chan<HuffmanPrescanReadResp>("huffman_lit_prescan_mem_rd_resp");
        let (huffman_lit_prescan_mem_wr_req_s, _huffman_lit_prescan_mem_wr_req_r) = chan<HuffmanPrescanWriteReq>("huffman_lit_prescan_mem_wr_req");
        let (_huffman_lit_prescan_mem_wr_resp_s, huffman_lit_prescan_mem_wr_resp_r) = chan<HuffmanPrescanWriteResp>("huffman_lit_prescan_mem_wr_resp");
        
        // AXI channels for various blocks
        let (axi_ram_rd_req_s, axi_ram_rd_req_r) = chan<TestcaseRamRdReq>[AXI_CHAN_N]("axi_ram_rd_req");
        let (axi_ram_rd_resp_s, axi_ram_rd_resp_r) = chan<TestcaseRamRdResp>[AXI_CHAN_N]("axi_ram_rd_resp");
        let (axi_ram_wr_req_s, axi_ram_wr_req_r) = chan<TestcaseRamWrReq>[AXI_CHAN_N]("axi_ram_wr_req");
        let (axi_ram_wr_resp_s, axi_ram_wr_resp_r) = chan<TestcaseRamWrResp>[AXI_CHAN_N]("axi_ram_wr_resp");
        let (axi_ram_ar_s, axi_ram_ar_r) = chan<MemAxiAr>[AXI_CHAN_N]("axi_ram_ar");
        let (axi_ram_r_s, axi_ram_r_r) = chan<MemAxiR>[AXI_CHAN_N]("axi_ram_r");
        unroll_for! (i, ()): (u32, ()) in range(u32:0, AXI_CHAN_N) {
            spawn ram::RamModel<TEST_CASE_RAM_DATA_WIDTH, TEST_CASE_RAM_SIZE, TEST_CASE_RAM_WORD_PARTITION_SIZE>(
                axi_ram_rd_req_r[i], axi_ram_rd_resp_s[i], axi_ram_wr_req_r[i], axi_ram_wr_resp_s[i]  
            );
            spawn axi_ram::AxiRamReader<
                TEST_AXI_ADDR_W, TEST_AXI_DATA_W, TEST_AXI_DEST_W, TEST_AXI_ID_W, TEST_CASE_RAM_SIZE,
                TEST_CASE_RAM_BASE_ADDR, TEST_CASE_RAM_DATA_WIDTH, TEST_CASE_RAM_ADDR_WIDTH
            >(
                axi_ram_ar_r[i], axi_ram_r_s[i], axi_ram_rd_req_s[i], axi_ram_rd_resp_r[i]
            );
        }(());

        // Literals buffer RAMs
        let (litbuf_rd_req_s,  litbuf_rd_req_r) = chan<LitBufRamRdReq>[u32:8]("litbuf_rd_req");
        let (litbuf_rd_resp_s, litbuf_rd_resp_r) = chan<LitBufRamRdResp>[u32:8]("litbuf_rd_resp");
        let (litbuf_wr_req_s,  litbuf_wr_req_r) = chan<LitBufRamWrReq>[u32:8]("litbuf_wr_req");
        let (litbuf_wr_resp_s, litbuf_wr_resp_r) = chan<LitBufRamWrResp>[u32:8]("litbuf_wr_resp");
        unroll_for! (i, ()): (u32, ()) in range(u32:0, u32:8) {
            spawn ram::RamModel<LITERALS_BUFFER_RAM_DATA_WIDTH, LITERALS_BUFFER_RAM_SIZE, LITERALS_BUFFER_RAM_WORD_PARTITION_SIZE>(
                litbuf_rd_req_r[i], litbuf_rd_resp_s[i], litbuf_wr_req_r[i], litbuf_wr_resp_s[i]
            );
        }(());

        // RAMs for FSE decoder
        // DPD RAM
        let (dpd_rd_req_s, dpd_rd_req_r) = chan<DpdRamRdReq>("dpd_rd_req");
        let (dpd_rd_resp_s, dpd_rd_resp_r) = chan<DpdRamRdResp>("dpd_rd_resp");
        let (dpd_wr_req_s, dpd_wr_req_r) = chan<DpdRamWrReq>("dpd_wr_req");
        let (dpd_wr_resp_s, dpd_wr_resp_r) = chan<DpdRamWrResp>("dpd_wr_resp");
        spawn ram::RamModel<TEST_DPD_RAM_DATA_W, TEST_DPD_RAM_SIZE, TEST_DPD_RAM_WORD_PARTITION_SIZE>(
            dpd_rd_req_r, dpd_rd_resp_s, dpd_wr_req_r, dpd_wr_resp_s,
        );

        // TMP RAM
        let (tmp_rd_req_s, tmp_rd_req_r) = chan<TmpRamRdReq>("tmp_rd_req");
        let (tmp_rd_resp_s, tmp_rd_resp_r) = chan<TmpRamRdResp>("tmp_rd_resp");
        let (tmp_wr_req_s, tmp_wr_req_r) = chan<TmpRamWrReq>("tmp_wr_req");
        let (tmp_wr_resp_s, tmp_wr_resp_r) = chan<TmpRamWrResp>("tmp_wr_resp");
        spawn ram::RamModel<TEST_TMP_RAM_DATA_W, TEST_TMP_RAM_SIZE, TEST_TMP_RAM_WORD_PARTITION_SIZE>(
            tmp_rd_req_r, tmp_rd_resp_s, tmp_wr_req_r, tmp_wr_resp_s,
        );
        
        // FSE RAMs
        let (fse_rd_req_s, fse_rd_req_r) = chan<FseRamRdReq>[u32:6]("tmp_rd_req");
        let (fse_rd_resp_s, fse_rd_resp_r) = chan<FseRamRdResp>[u32:6]("tmp_rd_resp");
        let (fse_wr_req_s, fse_wr_req_r) = chan<FseRamWrReq>[u32:6]("tmp_wr_req");
        let (fse_wr_resp_s, fse_wr_resp_r) = chan<FseRamWrResp>[u32:6]("tmp_wr_resp");
        unroll_for! (i, ()): (u32, ()) in range(u32:0, u32:6) {
            spawn ram::RamModel<TEST_FSE_RAM_DATA_W, TEST_FSE_RAM_SIZE, TEST_FSE_RAM_WORD_PARTITION_SIZE>(
                fse_rd_req_r[i], fse_rd_resp_s[i], fse_wr_req_r[i], fse_wr_resp_s[i]
            );
        }(());

        spawn CompressBlockDecoder<
            TEST_AXI_DATA_W, TEST_AXI_ADDR_W, TEST_AXI_ID_W, TEST_AXI_DEST_W,
            // FSE lookup table RAMs
            TEST_DPD_RAM_ADDR_W, TEST_DPD_RAM_DATA_W, TEST_DPD_RAM_NUM_PARTITIONS,
            TEST_TMP_RAM_ADDR_W, TEST_TMP_RAM_DATA_W, TEST_TMP_RAM_NUM_PARTITIONS,
            TEST_FSE_RAM_ADDR_W, TEST_FSE_RAM_DATA_W, TEST_FSE_RAM_NUM_PARTITIONS,
        >(
            req_r, resp_s,
            cmd_constr_out_s,
            axi_ram_ar_s[0], axi_ram_r_r[0],
            axi_ram_ar_s[1], axi_ram_r_r[1],
            axi_ram_ar_s[2], axi_ram_r_r[2],
            dpd_rd_req_s, dpd_rd_resp_r, dpd_wr_req_s, dpd_wr_resp_r,
            tmp_rd_req_s, tmp_rd_resp_r, tmp_wr_req_s, tmp_wr_resp_r,
            fse_rd_req_s[0], fse_rd_resp_r[0], fse_wr_req_s[0], fse_wr_resp_r[0],
            fse_rd_req_s[1], fse_rd_resp_r[1], fse_wr_req_s[1], fse_wr_resp_r[1],
            fse_rd_req_s[2], fse_rd_resp_r[2], fse_wr_req_s[2], fse_wr_resp_r[2],
            fse_rd_req_s[3], fse_rd_resp_r[3], fse_wr_req_s[3], fse_wr_resp_r[3],
            fse_rd_req_s[4], fse_rd_resp_r[4], fse_wr_req_s[4], fse_wr_resp_r[4],
            fse_rd_req_s[5], fse_rd_resp_r[5], fse_wr_req_s[5], fse_wr_resp_r[5],
            axi_ram_ar_s[3], axi_ram_r_r[3],
            axi_ram_ar_s[4], axi_ram_r_r[4],
            axi_ram_ar_s[5], axi_ram_r_r[5],
            litbuf_rd_req_s[0], litbuf_rd_req_s[1], litbuf_rd_req_s[2], litbuf_rd_req_s[3],
            litbuf_rd_req_s[4], litbuf_rd_req_s[5], litbuf_rd_req_s[6], litbuf_rd_req_s[7],
            litbuf_rd_resp_r[0], litbuf_rd_resp_r[1], litbuf_rd_resp_r[2], litbuf_rd_resp_r[3],
            litbuf_rd_resp_r[4], litbuf_rd_resp_r[5], litbuf_rd_resp_r[6], litbuf_rd_resp_r[7],
            litbuf_wr_req_s[0], litbuf_wr_req_s[1], litbuf_wr_req_s[2], litbuf_wr_req_s[3],
            litbuf_wr_req_s[4], litbuf_wr_req_s[5], litbuf_wr_req_s[6], litbuf_wr_req_s[7],
            litbuf_wr_resp_r[0], litbuf_wr_resp_r[1], litbuf_wr_resp_r[2], litbuf_wr_resp_r[3],
            litbuf_wr_resp_r[4], litbuf_wr_resp_r[5], litbuf_wr_resp_r[6], litbuf_wr_resp_r[7],
            huffman_lit_weights_mem_rd_req_s, huffman_lit_weights_mem_rd_resp_r,
            huffman_lit_prescan_mem_rd_req_s, huffman_lit_prescan_mem_rd_resp_r,
            huffman_lit_prescan_mem_wr_req_s, huffman_lit_prescan_mem_wr_resp_r,
        );
        
        (terminator, req_s, resp_r, cmd_constr_out_r, axi_ram_wr_req_s, axi_ram_wr_resp_r)
    }

    next(state: ()) {
        let tok = join();

        let tok = unroll_for!(test_i, tok): (u32, token) in range(u32:0, array_size(COMP_BLOCK_DEC_TESTCASES)) {
            let (input, _) = COMP_BLOCK_DEC_TESTCASES[test_i];

            trace_fmt!("Loading testcase {:x}", test_i);
            let tok = for ((i, input_data), tok): ((u32, u64), token) in enumerate(input) {
                let req = TestcaseRamWrReq {
                    addr: i as uN[TEST_CASE_RAM_ADDR_WIDTH],
                    data: input_data as uN[TEST_CASE_RAM_DATA_WIDTH],
                    mask: uN[TEST_CASE_RAM_NUM_PARTITIONS]:0xF
                };
                // Write to all RAMs
                let tok = unroll_for! (j, tok): (u32, token) in range(u32:0, AXI_CHAN_N) {
                    let tok = send(tok, axi_ram_wr_req_s[j], req);
                    let (tok, _) = recv(tok, axi_ram_wr_resp_r[j]);
                    tok
                }(tok);
                tok
            }(tok);

            // let tok = send(tok, req_s, Req {
                // addr: uN[AXI_ADDR_W]:0x0,
                // length: uN[AXI_ADDR_W]:???,
                // id: u32:1234,
                // last_block: false,            
            // });
            // let (tok, resp) = recv(tok, resp_r);

            tok
        }(tok);

        send(tok, terminator, true);
    }
}

