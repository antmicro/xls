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

// This file contains Huffman literals decoder proc implementation.

import xls.modules.zstd.common as common;
import xls.modules.zstd.huffman_common as hcommon;
import xls.modules.zstd.huffman_axi_reader as axi_reader;
import xls.modules.zstd.huffman_code_builder as code_builder;
import xls.modules.zstd.huffman_data_preprocessor as data_preprocessor;
import xls.modules.zstd.huffman_decoder as decoder;
import xls.modules.zstd.huffman_prescan as prescan;
import xls.modules.zstd.huffman_ctrl as ctrl;
import xls.modules.zstd.memory.axi as axi;
import xls.examples.ram;

pub fn WeightPreScanMetaDataSize() -> u32 {
    prescan::WeightPreScanMetaDataSize()
}

pub type HuffmanLiteralsDecoderReq = ctrl::HuffmanControlAndSequenceCtrl;
pub type HuffmanLiteralsDecoderResp = ctrl::HuffmanControlAndSequenceResp;
pub type HuffmanLiteralsDecoderStatus = ctrl::HuffmanControlAndSequenceStatus;

pub proc HuffmanLiteralsDecoder<
    AXI_DATA_W: u32, AXI_ADDR_W: u32, AXI_ID_W: u32,
    WEIGHTS_RAM_ADDR_WIDTH: u32 = {prescan::RAM_ADDR_WIDTH},
    WEIGHTS_RAM_DATA_WIDTH: u32 = {prescan::RAM_ACCESS_WIDTH},
    WEIGHTS_RAM_NUM_PARTITIONS: u32 = {u32:1},
    PRESCAN_RAM_ADDR_WIDTH: u32 = {prescan::RAM_ADDR_WIDTH},
    PRESCAN_RAM_DATA_WIDTH: u32 = {prescan::WeightPreScanMetaDataSize()},
    PRESCAN_RAM_NUM_PARTITIONS: u32 = {u32:1},
    > {
    type AxiR = axi::AxiR<AXI_DATA_W, AXI_ID_W>;
    type AxiAr = axi::AxiAr<AXI_ADDR_W, AXI_ID_W>;

    type WeightsRamRdReq  = ram::ReadReq<WEIGHTS_RAM_ADDR_WIDTH, WEIGHTS_RAM_NUM_PARTITIONS>;
    type WeightsRamRdResp = ram::ReadResp<WEIGHTS_RAM_DATA_WIDTH>;
    type PrescanRamRdReq = ram::ReadReq<PRESCAN_RAM_ADDR_WIDTH, PRESCAN_RAM_NUM_PARTITIONS>;
    type PrescanRamRdResp = ram::ReadResp<PRESCAN_RAM_DATA_WIDTH>;
    type PrescanRamWrReq = ram::WriteReq<PRESCAN_RAM_ADDR_WIDTH, PRESCAN_RAM_DATA_WIDTH, PRESCAN_RAM_NUM_PARTITIONS>;
    type PrescanRamWrResp = ram::WriteResp;

    type HuffmanAxiReaderCtrl = axi_reader::HuffmanAxiReaderCtrl<AXI_ADDR_W>;

    type Ctrl = HuffmanLiteralsDecoderReq<AXI_ADDR_W>;
    type Resp = HuffmanLiteralsDecoderResp;

    config (
        // ctrl
        ctrl_r: chan<Ctrl> in,
        resp_s: chan<Resp> out,
        // output literals
        decoded_literals_s: chan<common::LiteralsDataWithSync> out,
        // AXI interface
        axi_ar_s: chan<AxiAr> out,
        axi_r_r: chan<AxiR> in,
        // weight memory
        weights_ram_rd_req_s: chan<WeightsRamRdReq> out,
        weights_ram_rd_resp_r: chan<WeightsRamRdResp> in,
        // prescan memory
        prescan_ram_rd_req_s: chan<PrescanRamRdReq> out,
        prescan_ram_rd_resp_r: chan<PrescanRamRdResp> in,
        prescan_ram_wr_req_s: chan<PrescanRamWrReq> out,
        prescan_ram_wr_resp_r: chan<PrescanRamWrResp> in,
    ) {
        let (prescan_start_s, prescan_start_r) = chan<bool, u32:1>("prescan_start");
        let (code_builder_start_s, code_builder_start_r) = chan<bool, u32:1>("code_buider");
        let (axi_reader_ctrl_s, axi_reader_ctrl_r) = chan<HuffmanAxiReaderCtrl, u32:1>("axi_reader_ctrl");
        let (data_preprocess_start_s, data_preprocess_start_r) = chan<data_preprocessor::HuffmanDataPreprocessorStart, u32:1>("data_preprocess_start");
        let (decoder_start_s, decoder_start_r) = chan<decoder::HuffmanDecoderStart, u32:1>("decoder_start");
        let (decoder_done_s, decoder_done_r) = chan<(), u32:1>("decoder_done");
        let (prescan_response_s, prescan_response_r) = chan<hcommon::WeightPreScanOutput, u32:1>("prescan_response");
        let (code_builder_codes_s, code_builder_codes_r) = chan<hcommon::CodeBuilderToDecoderOutput, u32:1>("code_builder_codes");
        let (lookahead_config_s, lookahead_config_r) = chan<hcommon::CodeBuilderToPreDecoderOutput, u32:1>("lookahead_config");
        let (axi_data_s, axi_data_r) = chan<axi_reader::HuffmanAxiReaderData, u32:1>("axi_data");
        let (preprocessed_data_s, preprocessed_data_r) = chan<data_preprocessor::HuffmanDataPreprocessorData, u32:1>("preprocessed_data");
        // code builder loopback
        let (weights_pow_sum_loopback_s, weights_pow_sum_loopback_r) = chan<uN[hcommon::MAX_WEIGHT + u32:2], u32:1>("weights_pow_sum_loopback");

        spawn ctrl::HuffmanControlAndSequence<AXI_ADDR_W>(
            ctrl_r, resp_s,
            prescan_start_s,
            code_builder_start_s,
            axi_reader_ctrl_s,
            data_preprocess_start_s,
            decoder_start_s,
            decoder_done_r,
        );

        spawn prescan::WeightPreScan(
            prescan_start_r,
            weights_ram_rd_req_s,
            weights_ram_rd_resp_r,
            prescan_response_s,
            prescan_ram_rd_req_s,
            prescan_ram_rd_resp_r,
            prescan_ram_wr_req_s,
            prescan_ram_wr_resp_r,
        );

        spawn code_builder::WeightCodeBuilder(
            code_builder_start_r,
            prescan_response_r,
            code_builder_codes_s,
            lookahead_config_s,
            weights_pow_sum_loopback_s,
            weights_pow_sum_loopback_r,
        );

        spawn axi_reader::HuffmanAxiReader<AXI_DATA_W, AXI_ADDR_W, AXI_ID_W>(
            axi_reader_ctrl_r,
            axi_r_r,
            axi_ar_s,
            axi_data_s,
        );

        spawn data_preprocessor::HuffmanDataPreprocessor(
            data_preprocess_start_r,
            lookahead_config_r,
            axi_data_r,
            preprocessed_data_s,
        );

        spawn decoder::HuffmanDecoder(
            decoder_start_r,
            code_builder_codes_r,
            preprocessed_data_r,
            decoder_done_s,
            decoded_literals_s,
        );

        ()
    }

    init { }

    next (state: ()) { }
}

const INST_AXI_DATA_W = u32:64;
const INST_AXI_ADDR_W = u32:16;
const INST_AXI_ID_W = u32:4;

pub const INST_WEIGHTS_RAM_ADDR_WIDTH = prescan::RAM_ADDR_WIDTH;
pub const INST_WEIGHTS_RAM_DATA_WIDTH = prescan::RAM_ACCESS_WIDTH;
pub const INST_WEIGHTS_RAM_NUM_PARTITIONS = u32:1;
pub const INST_PRESCAN_RAM_ADDR_WIDTH = prescan::RAM_ADDR_WIDTH;
pub const INST_PRESCAN_RAM_DATA_WIDTH = prescan::WeightPreScanMetaDataSize();
pub const INST_PRESCAN_RAM_NUM_PARTITIONS = u32:1;

proc HuffmanLiteralsDecoderInst {
    type Ctrl = HuffmanLiteralsDecoderReq<INST_AXI_ADDR_W>;
    type Resp = HuffmanLiteralsDecoderResp;
    type AxiR = axi::AxiR<INST_AXI_DATA_W, INST_AXI_ID_W>;
    type AxiAr = axi::AxiAr<INST_AXI_ADDR_W, INST_AXI_ID_W>;

    type WeightsRamRdReq  = ram::ReadReq<INST_WEIGHTS_RAM_ADDR_WIDTH, INST_WEIGHTS_RAM_NUM_PARTITIONS>;
    type WeightsRamRdResp = ram::ReadResp<INST_WEIGHTS_RAM_DATA_WIDTH>;
    type PrescanRamRdReq = ram::ReadReq<INST_PRESCAN_RAM_ADDR_WIDTH, INST_PRESCAN_RAM_NUM_PARTITIONS>;
    type PrescanRamRdResp = ram::ReadResp<INST_PRESCAN_RAM_DATA_WIDTH>;
    type PrescanRamWrReq = ram::WriteReq<INST_PRESCAN_RAM_ADDR_WIDTH, INST_PRESCAN_RAM_DATA_WIDTH, INST_PRESCAN_RAM_NUM_PARTITIONS>;
    type PrescanRamWrResp = ram::WriteResp;

    config (
        ctrl_r: chan<Ctrl> in,
        resp_s: chan<Resp> out,
        decoded_literals_s: chan<common::LiteralsDataWithSync> out,
        axi_ar_s: chan<AxiAr> out,
        axi_r_r: chan<AxiR> in,
        weights_ram_rd_req_s: chan<WeightsRamRdReq> out,
        weights_ram_rd_resp_r: chan<WeightsRamRdResp> in,
        prescan_ram_rd_req_s: chan<PrescanRamRdReq> out,
        prescan_ram_rd_resp_r: chan<PrescanRamRdResp> in,
        prescan_ram_wr_req_s: chan<PrescanRamWrReq> out,
        prescan_ram_wr_resp_r: chan<PrescanRamWrResp> in,
    ) {
        spawn HuffmanLiteralsDecoder<
            INST_AXI_DATA_W, INST_AXI_ADDR_W, INST_AXI_ID_W,
            INST_WEIGHTS_RAM_ADDR_WIDTH, INST_WEIGHTS_RAM_DATA_WIDTH, INST_WEIGHTS_RAM_NUM_PARTITIONS,
            INST_PRESCAN_RAM_ADDR_WIDTH, INST_PRESCAN_RAM_DATA_WIDTH, INST_PRESCAN_RAM_NUM_PARTITIONS
            >(
            ctrl_r, resp_s,
            decoded_literals_s,
            axi_ar_s,
            axi_r_r,
            weights_ram_rd_req_s,
            weights_ram_rd_resp_r,
            prescan_ram_rd_req_s, prescan_ram_rd_resp_r,
            prescan_ram_wr_req_s, prescan_ram_wr_resp_r,
        );
    }

    init { }

    next (state: ()) { }
}

const TEST_AXI_DATA_W = u32:32;
const TEST_AXI_ADDR_W = u32:32;
const TEST_AXI_ID_W = u32:32;

pub const TEST_WEIGHTS_RAM_ADDR_WIDTH = prescan::RAM_ADDR_WIDTH;
pub const TEST_WEIGHTS_RAM_DATA_WIDTH = prescan::RAM_ACCESS_WIDTH;
pub const TEST_WEIGHTS_RAM_NUM_PARTITIONS = u32:1;
pub const TEST_PRESCAN_RAM_ADDR_WIDTH = prescan::RAM_ADDR_WIDTH;
pub const TEST_PRESCAN_RAM_DATA_WIDTH = prescan::WeightPreScanMetaDataSize();
pub const TEST_PRESCAN_RAM_NUM_PARTITIONS = u32:1;
pub const TEST_PRESCAN_RAM_SIZE = prescan::RAM_SIZE;
pub const TEST_PRESCAN_WORD_PARTITION_SIZE = prescan::WeightPreScanMetaDataSize();

type TestCtrl = HuffmanLiteralsDecoderReq<TEST_AXI_ADDR_W>;
type TestResp = HuffmanLiteralsDecoderResp;
type TestAxiR = axi::AxiR<TEST_AXI_DATA_W, TEST_AXI_ID_W>;
type TestAxiAr = axi::AxiAr<TEST_AXI_ADDR_W, TEST_AXI_ID_W>;

type TestWeightsRamRdReq  = ram::ReadReq<TEST_WEIGHTS_RAM_ADDR_WIDTH, TEST_WEIGHTS_RAM_NUM_PARTITIONS>;
type TestWeightsRamRdResp = ram::ReadResp<TEST_WEIGHTS_RAM_DATA_WIDTH>;
type TestPrescanRamRdReq = ram::ReadReq<TEST_PRESCAN_RAM_ADDR_WIDTH, TEST_PRESCAN_RAM_NUM_PARTITIONS>;
type TestPrescanRamRdResp = ram::ReadResp<TEST_PRESCAN_RAM_DATA_WIDTH>;
type TestPrescanRamWrReq = ram::WriteReq<TEST_PRESCAN_RAM_ADDR_WIDTH, TEST_PRESCAN_RAM_DATA_WIDTH, TEST_PRESCAN_RAM_NUM_PARTITIONS>;
type TestPrescanRamWrResp = ram::WriteResp;

type TestRamEntry = uN[TEST_WEIGHTS_RAM_DATA_WIDTH];

// data for test case #0
const TEST_CTRL_0 = TestCtrl {
    base_addr: uN[TEST_AXI_ADDR_W]:0x0,
    len: uN[TEST_AXI_ADDR_W]:0x8,
    new_config: true,
    id: u32:0,
    literals_last: false,
};

const TEST_DATA_LEN_0 = u32:64;
const TEST_DATA_0 = (
    u8:0b1_001_010_1 ++
    u8:0b01_010_1_01 ++
    u8:0b0100_001_0 ++
    u8:0b11_010_1_00 ++
    u8:0b001_010_1_0 ++
    u8:0b01_010_000 ++
    u8:0b11_1_1_0001 ++
    u8:0b001_1_010_0
);

// code         symbol  length  weight
// 0b1          0x47    1       9
// 0b001        0x41    3       7
// 0b010        0x8A    3       7
// 0b011        0xD2    3       7
// 0b000001     0x45    6       4
// 0b000010     0x7A    6       4
// 0b000011     0x89    6       4
// 0b000100     0x8D    6       4
// 0b000101     0xD1    6       4
// 0b000110     0xD3    6       4
// 0b000111     0xDA    6       4
// 0b000000000  0x12    9       1
// 0b000000001  0x8F    9       1
// 0b000000010  0xAC    9       1
// 0b000000011  0xD4    9       1
// 0b000000100  0xD7    9       1
// 0b000000101  0xDB    9       1
// 0b000000110  0xDE    9       1
// 0b000000111  0xFE    9       1

const TEST_WEIGHT_MEMORY_0 = TestRamEntry[32]:[
    //             x0 x1 x2 x3 x4 x5 x6 x7                 x8 x9 xA xB xC xD xE xF
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x0x
    TestRamEntry:0x_0__0__1__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x1x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x2x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x3x
    TestRamEntry:0x_0__7__0__0__0__4__0__9, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x4x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x5x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x6x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__4__0__0__0__0__0, // 0x7x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__4__7__0__0__4__0__1, // 0x8x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x9x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__1__0__0__0, // 0xAx
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0xBx
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0xCx
    TestRamEntry:0x_0__4__7__4__1__0__0__1, TestRamEntry:0x_0__0__4__1__0__0__1__0, // 0xDx
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0xEx
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__1__0, // 0xFx
];

const TEST_DECODED_LITERALS_0 = common::LiteralsDataWithSync[3]:[
    common::LiteralsDataWithSync {
        data: common::LitData:0x458A_D147_47D2_8A47,
        length: common::LitLength:8,
        last: false,
        id: u32:0,
        literals_last: false,
    },
    common::LiteralsDataWithSync {
        data: common::LitData:0x4141_8D47_8AD2_478A,
        length: common::LitLength:8,
        last: false,
        id: u32:0,
        literals_last: false,
    },
    common::LiteralsDataWithSync {
        data: common::LitData:0x478A_41D2_478A,
        length: common::LitLength:6,
        last: true,
        id: u32:0,
        literals_last: false,
    },
];

// data for test case #1 (same config)
const TEST_CTRL_1 = TestCtrl {
    base_addr: uN[TEST_AXI_ADDR_W]:0x20,
    len: uN[TEST_AXI_ADDR_W]:0x4,
    new_config: false,
    id: u32:1,
    literals_last: true,
};

const TEST_DATA_LEN_1 = u32:32;
const TEST_DATA_1 = (
    u8:0b0010_1_010 ++
    u8:0b000_0_000 ++
    u8:0b1_1_000000 ++
    u8:0b001_011_1_1
);

const TEST_DECODED_LITERALS_1 = common::LiteralsDataWithSync[2]:[
    common::LiteralsDataWithSync {
        data: common::LitData:0x47AC_1247_4747_47D2,
        length: common::LitLength:8,
        last: false,
        id: u32:1,
        literals_last: true,
    },
    common::LiteralsDataWithSync {
        data: common::LitData:0x8A,
        length: common::LitLength:1,
        last: true,
        id: u32:1,
        literals_last: true,
    },
];

// Data for test case #2
// Source: Example from RFC 8878, 4.2.2. Huffman-Coded Streams
// https://datatracker.ietf.org/doc/html/rfc8878#huffman_coded_streams
// Weights taken from Table 25
// Bitstream fixed to encode literal sequence "0145"
// See https://www.rfc-editor.org/errata/eid8195

const TEST_CTRL_2 = TestCtrl {
    base_addr: uN[TEST_AXI_ADDR_W]:0x0,
    len: uN[TEST_AXI_ADDR_W]:0x2,
    new_config: true,
    id: u32:0,
    literals_last: false,
};

const TEST_DATA_LEN_2 = u32:16;
const TEST_DATA_2 = u64:0b00000001_00001101;

// code         symbol  length  weight
// N/A          0x03    0       0
// 0b0000       0x04    4       1
// 0b0001       0x05    4       1
// 0b001        0x02    3       2
// 0b01         0x01    2       3
// 0b1          0x00    1       4

const TEST_WEIGHT_MEMORY_2 = TestRamEntry[32]:[
    //             x0 x1 x2 x3 x4 x5 x6 x7                 x8 x9 xA xB xC xD xE xF
    TestRamEntry:0x_4__3__2__0__1__1__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x0x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x1x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x2x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x3x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x4x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x5x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x6x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x7x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x8x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0x9x
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0xAx
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0xBx
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0xCx
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0xDx
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0xEx
    TestRamEntry:0x_0__0__0__0__0__0__0__0, TestRamEntry:0x_0__0__0__0__0__0__0__0, // 0xFx
];

const TEST_DECODED_LITERALS_2 = common::LiteralsDataWithSync[1]:[
    common::LiteralsDataWithSync {
        data: common::LitData:0x0504_0100,
        length: common::LitLength:4,
        last: true,
        id: u32:0,
        literals_last: false,
    },
];
#[test_proc]
proc HuffmanLiteralsDecoder_test {
    type Status = HuffmanLiteralsDecoderStatus;

    terminator: chan<bool> out;

    ctrl_s: chan<TestCtrl> out;
    resp_r: chan<TestResp> in;
    decoded_literals_r: chan<common::LiteralsDataWithSync> in;
    axi_ar_r: chan<TestAxiAr> in;
    axi_r_s: chan<TestAxiR> out;
    weights_ram_rd_req_r: chan<TestWeightsRamRdReq> in;
    weights_ram_rd_resp_s: chan<TestWeightsRamRdResp> out;

    config (terminator: chan<bool> out) {
        let (ctrl_s, ctrl_r) = chan<TestCtrl>("ctrl");
        let (resp_s, resp_r) = chan<TestResp>("resp");
        let (decoded_literals_s, decoded_literals_r) = chan<common::LiteralsDataWithSync>("decoded_literals");
        let (axi_ar_s, axi_ar_r) = chan<TestAxiAr>("axi_ar");
        let (axi_r_s, axi_r_r) = chan<TestAxiR>("axi_r");
        let (weights_ram_rd_req_s, weights_ram_rd_req_r) = chan<TestWeightsRamRdReq>("weights_ram_rd_req");
        let (weights_ram_rd_resp_s, weights_ram_rd_resp_r) = chan<TestWeightsRamRdResp>("weights_ram_rd_resp");

        // prescan internal memory
        let (prescan_ram_wr_req_s, prescan_ram_wr_req_r) = chan<TestPrescanRamWrReq, u32:1>("prescan_ram_wr_req");
        let (prescan_ram_wr_resp_s, prescan_ram_wr_resp_r) = chan<TestPrescanRamWrResp, u32:1>("prescan_ram_wr_resp");
        let (prescan_ram_rd_req_s, prescan_ram_rd_req_r) = chan<TestPrescanRamRdReq, u32:1>("prescan_ram_rd_req");
        let (prescan_ram_rd_resp_s, prescan_ram_rd_resp_r) = chan<TestPrescanRamRdResp, u32:1>("prescan_ram_rd_resp");

        spawn HuffmanLiteralsDecoder<
            TEST_AXI_DATA_W, TEST_AXI_ADDR_W, TEST_AXI_ID_W,
            TEST_WEIGHTS_RAM_ADDR_WIDTH, TEST_WEIGHTS_RAM_DATA_WIDTH, TEST_WEIGHTS_RAM_NUM_PARTITIONS,
            TEST_PRESCAN_RAM_ADDR_WIDTH, TEST_PRESCAN_RAM_DATA_WIDTH, TEST_PRESCAN_RAM_NUM_PARTITIONS
            >(
            ctrl_r, resp_s, decoded_literals_s,
            axi_ar_s, axi_r_r,
            weights_ram_rd_req_s, weights_ram_rd_resp_r,
            prescan_ram_rd_req_s, prescan_ram_rd_resp_r,
            prescan_ram_wr_req_s, prescan_ram_wr_resp_r,
        );

        spawn ram::RamModel<
            TEST_PRESCAN_RAM_DATA_WIDTH, TEST_PRESCAN_RAM_SIZE, TEST_PRESCAN_WORD_PARTITION_SIZE
            >(
            prescan_ram_rd_req_r, prescan_ram_rd_resp_s,
            prescan_ram_wr_req_r, prescan_ram_wr_resp_s,
        );

        (
            terminator,
            ctrl_s, resp_r, decoded_literals_r,
            axi_ar_r, axi_r_s,
            weights_ram_rd_req_r, weights_ram_rd_resp_s,
        )
    }

    init { }

    next (state: ()) {
        let tok = join();

        trace_fmt!("Test Case #1");
        // send ctrl
        let tok = send(tok, ctrl_s, TEST_CTRL_0);
        trace_fmt!("Sent #1 ctrl {:#x}", TEST_CTRL_0);

        // receive RAM read requests and send responses
        trace_fmt!("Sending weight memory content");
        let tok = for (_, tok): (u32, token) in range(u32:0, u32:2) {
            for (i, tok):(u32, token) in range(u32:0, array_size(TEST_WEIGHT_MEMORY_0)) {
                let (tok, weights_ram_rd_req) = recv(tok, weights_ram_rd_req_r);
                trace_fmt!("Received #{} ReadReq {:#x}", i + u32:1, weights_ram_rd_req);

                let read_resp = TestWeightsRamRdResp {
                    data: TEST_WEIGHT_MEMORY_0[weights_ram_rd_req.addr] as u32,
                };

                let tok = send(tok, weights_ram_rd_resp_s, read_resp);
                trace_fmt!("Sent #{} ReadResp {:#x}", i + u32:1, read_resp);

                tok
            }(tok)
        }(tok);

        // receive Axi requests and send responses
        trace_fmt!("Sending data from AXI");
        const AXI_READS_NUM  = (TEST_DATA_LEN_0 + u32:7) / u32:8;
        let tok = for (i, tok):(u32, token) in range(u32:0, AXI_READS_NUM) {
            let expected_axi_ar = TestAxiAr {
                addr: TEST_CTRL_0.base_addr + (AXI_READS_NUM - u32:1 - i) as uN[TEST_AXI_ADDR_W],
                ..zero!<TestAxiAr>()
            };
            let (tok, axi_ar) = recv(tok, axi_ar_r);
            trace_fmt!("Received #{} AxiAr {:#x}", i + u32:1, axi_ar);
            assert_eq(expected_axi_ar, axi_ar);

            let axi_r = TestAxiR {
                id: axi_ar.id,
                data: (TEST_DATA_0 >> (u32:8 * i)) as u32,
                resp: axi::AxiReadResp::OKAY,
                last: i == (AXI_READS_NUM - u32:1),
            };

            let tok = send(tok, axi_r_s, axi_r);
            trace_fmt!("Sent #{} AxiR {:#x}", i + u32:1, axi_r);

            tok
        }(tok);

        // receive decoded literals
        let tok = for ((i, test_decoded_literals), tok):((u32, common::LiteralsDataWithSync), token) in enumerate(TEST_DECODED_LITERALS_0) {
            let (tok, decoded_literals) = recv(tok, decoded_literals_r);
            trace_fmt!("Received #{} decoded literals {:#x}", i + u32:1, decoded_literals);
            assert_eq(test_decoded_literals, decoded_literals);
            tok
        }(tok);

        let (tok, resp) = recv(tok, resp_r);
        assert_eq(TestResp {status: Status::OKAY}, resp);

        trace_fmt!("Test Case #2");
        // send ctrl
        let tok = send(tok, ctrl_s, TEST_CTRL_1);
        trace_fmt!("Sent #2 ctrl {:#x}", TEST_CTRL_1);

        // receive Axi requests and send responses
        trace_fmt!("Sending data from AXI");
        const AXI_READS_NUM  = (TEST_DATA_LEN_1 + u32:7) / u32:8;
        let tok = for (i, tok):(u32, token) in range(u32:0, AXI_READS_NUM) {
            let expected_axi_ar = TestAxiAr {
                addr: TEST_CTRL_1.base_addr + (AXI_READS_NUM - u32:1 - i) as uN[TEST_AXI_ADDR_W],
                ..zero!<TestAxiAr>()
            };
            let (tok, axi_ar) = recv(tok, axi_ar_r);
            trace_fmt!("Received #{} AxiAr {:#x}", i + u32:1, axi_ar);
            assert_eq(expected_axi_ar, axi_ar);

            let axi_r = TestAxiR {
                id: axi_ar.id,
                data: (TEST_DATA_1 >> (u32:8 * i)) as u32,
                resp: axi::AxiReadResp::OKAY,
                last: i == (AXI_READS_NUM - u32:1),
            };

            let tok = send(tok, axi_r_s, axi_r);
            trace_fmt!("Sent #{} AxiR {:#x}", i + u32:1, axi_r);

            tok
        }(tok);

        // receive decoded literals
        let tok = for ((i, test_decoded_literals), tok):((u32, common::LiteralsDataWithSync), token) in enumerate(TEST_DECODED_LITERALS_1) {
            let (tok, decoded_literals) = recv(tok, decoded_literals_r);
            trace_fmt!("Received #{} decoded literals {:#x}", i + u32:1, decoded_literals);
            assert_eq(test_decoded_literals, decoded_literals);
            tok
        }(tok);

        let (tok, resp) = recv(tok, resp_r);
        assert_eq(TestResp {status: Status::OKAY}, resp);

        trace_fmt!("Test Case #3");
        // send ctrl
        let tok = send(tok, ctrl_s, TEST_CTRL_2);
        trace_fmt!("Sent #3 ctrl {:#x}", TEST_CTRL_2);

        // receive RAM read requests and send responses
        trace_fmt!("Sending weight memory content");
        let tok = for (_, tok): (u32, token) in range(u32:0, u32:2) {
            for (i, tok):(u32, token) in range(u32:0, array_size(TEST_WEIGHT_MEMORY_2)) {
                let (tok, weights_ram_rd_req) = recv(tok, weights_ram_rd_req_r);
                trace_fmt!("Received #{} ReadReq {:#x}", i + u32:1, weights_ram_rd_req);

                let read_resp = TestWeightsRamRdResp {
                    data: TEST_WEIGHT_MEMORY_2[weights_ram_rd_req.addr] as u32,
                };

                let tok = send(tok, weights_ram_rd_resp_s, read_resp);
                trace_fmt!("Sent #{} ReadResp {:#x}", i + u32:1, read_resp);

                tok
            }(tok)
        }(tok);

        // receive Axi requests and send responses
        trace_fmt!("Sending data from AXI");
        const AXI_READS_NUM  = (TEST_DATA_LEN_2 + u32:7) / u32:8;
        let tok = for (i, tok):(u32, token) in range(u32:0, AXI_READS_NUM) {
            let expected_axi_ar = TestAxiAr {
                addr: TEST_CTRL_2.base_addr + (AXI_READS_NUM - u32:1 - i) as uN[TEST_AXI_ADDR_W],
                ..zero!<TestAxiAr>()
            };
            let (tok, axi_ar) = recv(tok, axi_ar_r);
            trace_fmt!("Received #{} AxiAr {:#x}", i + u32:1, axi_ar);
            assert_eq(expected_axi_ar, axi_ar);

            let axi_r = TestAxiR {
                id: axi_ar.id,
                data: (TEST_DATA_2 >> (u32:8 * i)) as u32,
                resp: axi::AxiReadResp::OKAY,
                last: i == (AXI_READS_NUM - u32:1),
            };

            let tok = send(tok, axi_r_s, axi_r);
            trace_fmt!("Sent #{} AxiR {:#x}", i + u32:1, axi_r);

            tok
        }(tok);

        // receive decoded literals
        let tok = for ((i, test_decoded_literals), tok):((u32, common::LiteralsDataWithSync), token) in enumerate(TEST_DECODED_LITERALS_2) {
            let (tok, decoded_literals) = recv(tok, decoded_literals_r);
            trace_fmt!("Received #{} decoded literals {:#x}", i + u32:1, decoded_literals);
            assert_eq(test_decoded_literals, decoded_literals);
            tok
        }(tok);

        let (tok, resp) = recv(tok, resp_r);
        assert_eq(TestResp {status: Status::OKAY}, resp);

        send(tok, terminator, true);
    }
}
