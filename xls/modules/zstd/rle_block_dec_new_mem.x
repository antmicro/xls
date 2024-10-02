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

// This file contains the implementation of RleBlockDecoder responsible for decoding
// ZSTD RLE Blocks. More Information about Rle Block's format can be found in:
// https://datatracker.ietf.org/doc/html/rfc8878#section-3.1.1.2.2
//
// The implementation consist of 3 procs:
// * RleDataPacker
// * RunLengthDecoder
// * BatchPacker
// Connections between those is represented on the diagram below:
//
//                                RleBlockDecoder
//    ┌─────────────────────────────────────────────────────────────┐
//    │    RleDataPacker       RunLengthDecoder       BatchPacker   │
//    │  ┌───────────────┐   ┌──────────────────┐   ┌─────────────┐ │
// ───┼─►│               ├──►│                  ├──►│             ├─┼──►
//    │  └───────┬───────┘   └──────────────────┘   └─────────────┘ │
//    │          │                                         ▲        │
//    │          │            SynchronizationData          │        │
//    │          └─────────────────────────────────────────┘        │
//    └─────────────────────────────────────────────────────────────┘
//
// RleDataPacker is responsible for receiving the incoming packets of block data, converting
// those to format accepted by RunLengthDecoder and passing the data to the actual decoder block.
// It also extracts from the input packets the synchronization data like block_id and last_block
// and then passes those to BatchPacker proc.
// RunLengthDecoder decodes RLE blocks and outputs one symbol for each transaction on output
// channel.
// BatchPacker then gathers those symbols into packets, appends synchronization data received from
// RleDataPacker and passes such packets to the output of the RleBlockDecoder.

import std;

import xls.modules.zstd.common;
import xls.modules.rle.rle_dec_adv;
import xls.modules.rle.rle_common;
import xls.modules.zstd.memory.mem_reader;

const SYMBOL_WIDTH = common::SYMBOL_WIDTH;
const BLOCK_SIZE_WIDTH = common::BLOCK_SIZE_WIDTH;
const DATA_WIDTH = common::DATA_WIDTH;
const BATCH_SIZE = DATA_WIDTH / SYMBOL_WIDTH;

const TEST_DATA_W = u32:32;
const TEST_ADDR_W = u32:32;

const DATA_WIDTH_LOG2 = std::clog2(common::DATA_WIDTH + u32:1);

type BlockDataPacket = common::BlockDataPacket;
type BlockPacketLength = common::BlockPacketLength;
type BlockData = common::BlockData;
type BlockSize = common::BlockSize;

type ExtendedBlockDataPacket = common::ExtendedBlockDataPacket;
type CopyOrMatchContent = common::CopyOrMatchContent;
type CopyOrMatchLength = common::CopyOrMatchLength;
type SequenceExecutorMessageType = common::SequenceExecutorMessageType;

type RleInput = rle_common::CompressedData<SYMBOL_WIDTH, BLOCK_SIZE_WIDTH>;
type RleOutput = rle_common::PlainDataWithLen<common::DATA_WIDTH, DATA_WIDTH_LOG2>;
type Symbol = bits[SYMBOL_WIDTH];
type SymbolCount = BlockSize;

type TestMemReaderReq = mem_reader::MemReaderReq<TEST_ADDR_W>;
type TestMemReaderResp = mem_reader::MemReaderResp<TEST_DATA_W, TEST_ADDR_W>;

pub struct RleBlockDecoderReq<ADDR_W: u32> {
    id: u32,
    symbol: u8,
    length: uN[ADDR_W],
    last_block: bool,
}

pub enum RleBlockDecoderStatus: u1 {
    OKAY = 0,
}

pub struct RleBlockDecoderResp {
    status: RleBlockDecoderStatus
}

struct BlockSyncData {
    last_block: bool,
    count: SymbolCount,
    id: u32
}

struct RleDataPackerState<ADDR_W: u32> {
    last_block: bool,
    id: u32,
    length: uN[ADDR_W],
}

proc RleDataPacker<DATA_W: u32, ADDR_W: u32> {
    type Req = RleBlockDecoderReq<ADDR_W>;
    type State = RleDataPackerState<ADDR_W>;

    // input
    req_r: chan<Req> in;
    rle_data_s: chan<RleInput> out;
    sync_s: chan<BlockSyncData> out;

    config(
        req_r: chan<Req> in,
        rle_data_s: chan<RleInput> out,
        sync_s: chan<BlockSyncData> out
    ) {
        (req_r, rle_data_s, sync_s)
    }

    init { zero!<State>() }

    next(state: State) {
        // receive request
        let (tok, req, req_valid) = recv_non_blocking(join(), req_r, zero!<Req>());

        // update state
        let state = if req_valid {
            State {
                last_block: req.last_block,
                id: req.id,
                length: req.length
            }
        } else {
            state
        };

        // create RLE packet
        let rle_dec_data = RleInput {
            symbol: req.symbol as Symbol,
            count: state.length as SymbolCount,
            last: true
        };

        // send RLE packet for decoding unless it has symbol count == 0
        let do_send = req_valid && (rle_dec_data.count != SymbolCount:0);
        let tok = send_if(tok, rle_data_s, do_send, rle_dec_data);
        let sync_data = BlockSyncData { last_block: state.last_block, count: rle_dec_data.count, id: state.id };

        // send last block packet even if it has symbol count == 0
        send_if(tok, sync_s, (req_valid && (state.length == uN[ADDR_W]:0) && state.last_block), sync_data);

        state
    }
}

// struct RleDataPackerTestData {
//     last: bool,
//     last_block: bool,
//     id: u32,
//     addr: uN[TEST_ADDR_W],
//     length: uN[TEST_ADDR_W],
//     data: uN[TEST_DATA_W],
// }
//
// const RLE_DATA_PACKER_TEST_DATA = RleDataPackerTestData[12]:[
//     RleDataPackerTestData {last: false, last_block: false, id: u32:0, addr: uN[TEST_ADDR_W]:0, length: uN[TEST_ADDR_W]:8, data: uN[TEST_DATA_W]:0xAB},
//     RleDataPackerTestData {last: true,  last_block: false, id: u32:0, addr: uN[TEST_ADDR_W]:8, length: uN[TEST_ADDR_W]:5, data: uN[TEST_DATA_W]:0xCD},
//     RleDataPackerTestData {last: false, last_block: false, id: u32:1, addr: uN[TEST_ADDR_W]:512, length: uN[TEST_ADDR_W]:12, data: uN[TEST_DATA_W]:0x67},
//     RleDataPackerTestData {last: false, last_block: false, id: u32:1, addr: uN[TEST_ADDR_W]:544, length: uN[TEST_ADDR_W]:35, data: uN[TEST_DATA_W]:0x09},
//     RleDataPackerTestData {last: false, last_block: false, id: u32:1, addr: uN[TEST_ADDR_W]:576, length: uN[TEST_ADDR_W]:123, data: uN[TEST_DATA_W]:0x9D},
//     RleDataPackerTestData {last: true,  last_block: false, id: u32:1, addr: uN[TEST_ADDR_W]:592, length: uN[TEST_ADDR_W]:1, data: uN[TEST_DATA_W]:0x1F},
//     RleDataPackerTestData {last: false, last_block: false, id: u32:2, addr: uN[TEST_ADDR_W]:32, length: uN[TEST_ADDR_W]:0, data: uN[TEST_DATA_W]:0x12},
//     RleDataPackerTestData {last: true,  last_block: true, id: u32:2, addr: uN[TEST_ADDR_W]:64, length: uN[TEST_ADDR_W]:42, data: uN[TEST_DATA_W]:0xAA},
//     RleDataPackerTestData {last: false, last_block: false, id: u32:3, addr: uN[TEST_ADDR_W]:1242, length: uN[TEST_ADDR_W]:33, data: uN[TEST_DATA_W]:0x54},
//     RleDataPackerTestData {last: true,  last_block: false, id: u32:3, addr: uN[TEST_ADDR_W]:5432, length: uN[TEST_ADDR_W]:0, data: uN[TEST_DATA_W]:0xC0},
//     RleDataPackerTestData {last: false, last_block: false, id: u32:4, addr: uN[TEST_ADDR_W]:1024, length: uN[TEST_ADDR_W]:2, data: uN[TEST_DATA_W]:0xA3},
//     RleDataPackerTestData {last: true,  last_block: true, id: u32:4, addr: uN[TEST_ADDR_W]:2000, length: uN[TEST_ADDR_W]:0, data: uN[TEST_DATA_W]:0x83},
// ];
//
// #[test_proc]
// proc RleDataPacker_test {
//     type TestReq = RleBlockDecoderReq<TEST_ADDR_W>;
//
//     terminator: chan<bool> out;
//
//     req_s: chan<TestReq> out;
//
//     mem_req_r: chan<TestMemReaderReq> in;
//     mem_resp_s: chan<TestMemReaderResp> out;
//
//     out_r: chan<RleInput> in;
//     sync_r: chan<BlockSyncData> in;
//
//     config(terminator: chan<bool> out) {
//         let (req_s, req_r) = chan<TestReq>("req");
//
//         let (out_s, out_r) = chan<RleInput>("out");
//         let (sync_s, sync_r) = chan<BlockSyncData>("sync");
//
//         spawn RleDataPacker<TEST_DATA_W, TEST_ADDR_W>(req_r, out_s, sync_s);
//
//         (terminator, req_s, out_r, sync_r)
//     }
//
//     init {  }
//
//     next(state: ()) {
//         let tok = join();
//         let tok = for ((i, test_data), tok): ((u32, RleDataPackerTestData), token) in enumerate(RLE_DATA_PACKER_TEST_DATA) {
//             let req = TestReq {
//                 last: test_data.last,
//                 last_block: test_data.last_block,
//                 id: test_data.id,
//                 addr: test_data.addr,
//                 length: test_data.length,
//             };
//             let tok = send(tok, req_s, req);
//             trace_fmt!("Sent #{} request {:#x}", i + u32:1, req);
//
//             let tok = if test_data.length > uN[TEST_ADDR_W]:0 {
//                 let (tok, mem_req) = recv(tok, mem_req_r);
//                 trace_fmt!("Received #{} memory read request {:#x}", i + u32:1, mem_req);
//
//                 assert_eq(test_data.addr, mem_req.addr);
//                 assert_eq(uN[TEST_ADDR_W]:8, mem_req.length);
//
//                 let mem_resp = TestMemReaderResp {
//                     status: mem_reader::MemReaderStatus::OKAY,
//                     data: test_data.data,
//                     length: uN[TEST_ADDR_W]:8,
//                     last: true,
//                 };
//
//                 let tok = send(tok, mem_resp_s, mem_resp);
//                 trace_fmt!("Sent #{} memory response {:#x}", i + u32:1, mem_resp);
//
//                 let expected_output = RleInput {
//                     last: true, symbol: test_data.data as Symbol, count: test_data.length as BlockSize
//                 };
//                 let (tok, output) = recv(tok, out_r);
//                 trace_fmt!("Received #{} packed rle encoded block {:#x}", i + u32:1, output);
//                 assert_eq(expected_output, output);
//
//                 tok
//             } else { tok };
//
//             let tok = if test_data.length > uN[TEST_ADDR_W]:0 || test_data.last_block {
//                 let sync_out = BlockSyncData {
//                     id: test_data.id,
//                     last_block: test_data.last_block,
//                     count: test_data.length as SymbolCount,
//                 };
//                 let (tok, sync_output) = recv(tok, sync_r);
//                 trace_fmt!("Received #{} synchronization data {:#x}", i + u32:1, sync_output);
//                 assert_eq(sync_output, sync_out);
//                 tok
//             } else {
//                 tok
//             };
//
//             (tok)
//         }(tok);
//         send(tok, terminator, true);
//     }
// }

struct BatchPackerState {
    sync: BlockSyncData,
    symbols_in_block: BlockPacketLength,
}

const ZERO_BATCH_STATE = zero!<BatchPackerState>();
const ZERO_BLOCK_SYNC_DATA = zero!<BlockSyncData>();
const ZERO_RLE_OUTPUT = zero!<RleOutput>();
const EMPTY_RLE_OUTPUT = RleOutput {last: true, ..ZERO_RLE_OUTPUT};

proc BatchPacker {
    type State = BatchPackerState;

    rle_data_r: chan<RleOutput> in;
    sync_r: chan<BlockSyncData> in;
    resp_s: chan<RleBlockDecoderResp> out;
    block_data_s: chan<ExtendedBlockDataPacket> out;

    config(
        rle_data_r: chan<RleOutput> in,
        sync_r: chan<BlockSyncData> in,
        resp_s: chan<RleBlockDecoderResp> out,
        block_data_s: chan<ExtendedBlockDataPacket> out
    ) {
        (rle_data_r, sync_r, resp_s, block_data_s)
    }

    // Init the state to signal new batch to process
    init { zero!<State>() }

    next(state: State) {
        let tok = join();

        // receive sync
        let recv_sync = state.sync.count as BlockPacketLength == state.symbols_in_block;
        let (tok, sync_data) = recv_if(tok, sync_r, recv_sync, zero!<BlockSyncData>());

        if recv_sync {
            trace_fmt!("Received sync {:#x}", sync_data);
        } else {};

        // store sync in state, set symbols count to zero
        let state = if recv_sync {
            State {
                sync: sync_data,
                symbols_in_block: BlockPacketLength:0,
            }
        } else {
            state
        };

        // receive RLE output it not enought symbols sent
        let recv_rle_data = state.symbols_in_block < state.sync.count as BlockPacketLength;

        let (tok, rle_data) = recv_if(tok, rle_data_r, recv_rle_data, zero!<RleOutput>());

        if recv_rle_data {
            trace_fmt!("Received RLE decoder output {:#x}", rle_data);
        } else {};

        // prepare output
        let block_data = ExtendedBlockDataPacket {
            // Decoded RLE block is always a literal
            msg_type: SequenceExecutorMessageType::LITERAL,
            packet: BlockDataPacket {
                last: rle_data.last || (state.sync.count == SymbolCount:0 && state.sync.last_block),
                last_block: state.sync.last_block,
                id: state.sync.id,
                data: rle_data.symbols as BlockData,
                // length in bits
                length: rle_data.length as BlockPacketLength << 3,
            }
        };

        // send output if count was greater than zero or it is the last block
        let send_output = recv_rle_data || (recv_sync && state.sync.count == SymbolCount:0 && state.sync.last_block);

        let tok = send_if(tok, block_data_s, send_output, block_data);
        let tok = send_if(tok, resp_s, send_output, RleBlockDecoderResp {status: RleBlockDecoderStatus::OKAY});

        // update symbols count in state
        let state = State {
            symbols_in_block: state.symbols_in_block + rle_data.length as BlockPacketLength,
            ..state
        };

        state
    }
}

// const BATCH_PACKER_TEST_DATA_SYNC = BlockSyncData[14]:[
//     BlockSyncData { last_block: false, count: SymbolCount:1, id: u32:0 },
//     BlockSyncData { last_block: false, count: SymbolCount:2, id: u32:1 },
//     BlockSyncData { last_block: false, count: SymbolCount:4, id: u32:2 },
//     BlockSyncData { last_block: false, count: SymbolCount:8, id: u32:3 },
//     BlockSyncData { last_block: false, count: SymbolCount:16, id: u32:4 },
//     BlockSyncData { last_block: true, count: SymbolCount:31, id: u32:5 },
//     BlockSyncData { last_block: false, count: SymbolCount:0, id: u32:0 },
//     BlockSyncData { last_block: false, count: SymbolCount:1, id: u32:1 },
//     BlockSyncData { last_block: false, count: SymbolCount:0, id: u32:2 },
//     BlockSyncData { last_block: false, count: SymbolCount:4, id: u32:3 },
//     BlockSyncData { last_block: false, count: SymbolCount:0, id: u32:4 },
//     BlockSyncData { last_block: false, count: SymbolCount:16, id: u32:5 },
//     BlockSyncData { last_block: false, count: SymbolCount:0, id: u32:6 },
//     BlockSyncData { last_block: true, count: SymbolCount:0, id: u32:7 },
// ];
//
// const BATCH_PACKER_TEST_DATA_RLE = RleOutput[14]:[
//     // 1st block
//     RleOutput{ symbols: uN[common::DATA_WIDTH]:0x01, length: uN[DATA_WIDTH_LOG2]:1, last: true },
//     // 2nd block
//     RleOutput{ symbols: uN[common::DATA_WIDTH]:0x0202, length: uN[DATA_WIDTH_LOG2]:2, last: true },
//     // 3rd block
//     RleOutput{ symbols: uN[common::DATA_WIDTH]:0x0303_0303, length: uN[DATA_WIDTH_LOG2]:4, last: true },
//     // 4th block
//     RleOutput{ symbols: uN[common::DATA_WIDTH]:0x0404_0404_0404_0404, length: uN[DATA_WIDTH_LOG2]:8, last: true },
//     // 5th block
//     RleOutput{ symbols: uN[common::DATA_WIDTH]:0x0505_0505_0505_0505, length: uN[DATA_WIDTH_LOG2]:8, last: false },
//     RleOutput{ symbols: uN[common::DATA_WIDTH]:0x0505_0505_0505_0505, length: uN[DATA_WIDTH_LOG2]:8, last: true },
//     // 6th block
//     RleOutput{ symbols: uN[common::DATA_WIDTH]:0x0606_0606_0606_0606, length: uN[DATA_WIDTH_LOG2]:8, last: false },
//     RleOutput{ symbols: uN[common::DATA_WIDTH]:0x0606_0606_0606_0606, length: uN[DATA_WIDTH_LOG2]:8, last: false },
//     RleOutput{ symbols: uN[common::DATA_WIDTH]:0x0606_0606_0606_0606, length: uN[DATA_WIDTH_LOG2]:8, last: false },
//     RleOutput{ symbols: uN[common::DATA_WIDTH]:0x06_0606_0606_0606, length: uN[DATA_WIDTH_LOG2]:7, last: true },
//     // 7th block
//     // EMPTY
//     // 8th block
//     RleOutput{ symbols: uN[common::DATA_WIDTH]:0x08, length: uN[DATA_WIDTH_LOG2]:1, last: true },
//     // 9th block
//     // EMPTY
//     // 10th block
//     RleOutput{ symbols: uN[common::DATA_WIDTH]:0x0A0A_0A0A, length: uN[DATA_WIDTH_LOG2]:4, last: true },
//     // 11th block
//     // EMPTY
//     // 12th block
//     RleOutput{ symbols: uN[common::DATA_WIDTH]:0x0C0C_0C0C_0C0C_0C0C, length: uN[DATA_WIDTH_LOG2]:8, last: false },
//     RleOutput{ symbols: uN[common::DATA_WIDTH]:0x0C0C_0C0C_0C0C_0C0C, length: uN[DATA_WIDTH_LOG2]:8, last: true },
//     // 13th block
//     // EMPTY
//     // 14th block
//     // EMPTY
// ];
//
// const BATCH_PACKER_TEST_DATA_OUTPUT = ExtendedBlockDataPacket[15]:[
//     // 1st block
//     ExtendedBlockDataPacket {msg_type: SequenceExecutorMessageType::LITERAL, packet: BlockDataPacket {last: bool:true, last_block: bool:false, id: u32:0, data: BlockData:0x01, length: BlockPacketLength:8}},
//     // 2nd block
//     ExtendedBlockDataPacket {msg_type: SequenceExecutorMessageType::LITERAL, packet: BlockDataPacket {last: bool:true, last_block: bool:false, id: u32:1, data: BlockData:0x0202, length: BlockPacketLength:16}},
//     // 3rd block
//     ExtendedBlockDataPacket {msg_type: SequenceExecutorMessageType::LITERAL, packet: BlockDataPacket {last: bool:true, last_block: bool:false, id: u32:2, data: BlockData:0x0303_0303, length: BlockPacketLength:32}},
//     // 4th blck
//     ExtendedBlockDataPacket {msg_type: SequenceExecutorMessageType::LITERAL, packet: BlockDataPacket {last: bool:true, last_block: bool:false, id: u32:3, data: BlockData:0x0404_0404_0404_0404, length: BlockPacketLength:64}},
//     // 5th block
//     ExtendedBlockDataPacket {msg_type: SequenceExecutorMessageType::LITERAL, packet: BlockDataPacket {last: bool:false, last_block: bool:false, id: u32:4, data: BlockData:0x0505_0505_0505_0505, length: BlockPacketLength:64}},
//     ExtendedBlockDataPacket {msg_type: SequenceExecutorMessageType::LITERAL, packet: BlockDataPacket {last: bool:true, last_block: bool:false, id: u32:4, data: BlockData:0x0505_0505_0505_0505, length: BlockPacketLength:64}},
//     // 6th block
//     ExtendedBlockDataPacket {msg_type: SequenceExecutorMessageType::LITERAL, packet: BlockDataPacket {last: bool:false, last_block: bool:true, id: u32:5, data: BlockData:0x0606_0606_0606_0606, length: BlockPacketLength:64}},
//     ExtendedBlockDataPacket {msg_type: SequenceExecutorMessageType::LITERAL, packet: BlockDataPacket {last: bool:false, last_block: bool:true, id: u32:5, data: BlockData:0x0606_0606_0606_0606, length: BlockPacketLength:64}},
//     ExtendedBlockDataPacket {msg_type: SequenceExecutorMessageType::LITERAL, packet: BlockDataPacket {last: bool:false, last_block: bool:true, id: u32:5, data: BlockData:0x0606_0606_0606_0606, length: BlockPacketLength:64}},
//     ExtendedBlockDataPacket {msg_type: SequenceExecutorMessageType::LITERAL, packet: BlockDataPacket {last: bool:true, last_block: bool:true, id: u32:5, data: BlockData:0x06_0606_0606_0606, length: BlockPacketLength:56}},
//     // 7th block
//     // EMPTY
//     // 8th block
//     ExtendedBlockDataPacket {msg_type: SequenceExecutorMessageType::LITERAL, packet: BlockDataPacket {last: bool:true, last_block: bool:false, id: u32:1, data: BlockData:0x08, length: BlockPacketLength:8}},
//     // 9th block
//     // EMPTY
//     // 10th block
//     ExtendedBlockDataPacket {msg_type: SequenceExecutorMessageType::LITERAL, packet: BlockDataPacket {last: bool:true, last_block: bool:false, id: u32:3, data: BlockData:0x0A0_A0A0A, length: BlockPacketLength:32}},
//     // 11th block
//     // EMPTY
//     // 12th block
//     ExtendedBlockDataPacket {msg_type: SequenceExecutorMessageType::LITERAL, packet: BlockDataPacket {last: bool:false, last_block: bool:false, id: u32:5, data: BlockData:0x0C0C_0C0C_0C0C_0C0C, length: BlockPacketLength:64}},
//     ExtendedBlockDataPacket {msg_type: SequenceExecutorMessageType::LITERAL, packet: BlockDataPacket {last: bool:true, last_block: bool:false, id: u32:5, data: BlockData:0x0C0C_0C0C_0C0C_0C0C, length: BlockPacketLength:64}},
//     // 13th block
//     // EMPTY
//     // 14th block
//     // EMPTY with LAST_BLOCK
//     ExtendedBlockDataPacket {msg_type: SequenceExecutorMessageType::LITERAL, packet: BlockDataPacket {last: bool:true, last_block: bool:true, id: u32:7, data: BlockData:0x0, length: BlockPacketLength:0}},
// ];
//
// #[test_proc]
// proc BatchPacker_test {
//     terminator: chan<bool> out;
//     in_s: chan<RleOutput> out;
//     sync_s: chan<BlockSyncData> out;
//     resp_r: chan<RleBlockDecoderResp> in;
//     out_r: chan<ExtendedBlockDataPacket> in;
//
//     config(terminator: chan<bool> out) {
//         let (in_s, in_r) = chan<RleOutput>("in");
//         let (sync_s, sync_r) = chan<BlockSyncData>("sync");
//         let (resp_s, resp_r) = chan<RleBlockDecoderResp>("resp");
//         let (out_s, out_r) = chan<ExtendedBlockDataPacket>("out");
//
//         spawn BatchPacker(in_r, sync_r, resp_s, out_s);
//
//         (terminator, in_s, sync_s, resp_r, out_r)
//     }
//
//     init {  }
//
//     next(state: ()) {
//         let tok = join();
//
//         let tok = for ((i, test_data_rle), tok): ((u32, RleOutput), token) in enumerate(BATCH_PACKER_TEST_DATA_RLE) {
//             let tok = send(tok, in_s, test_data_rle);
//             trace_fmt!("Sent #{} RLE output {:#x}", i + u32:1, test_data_rle);
//             tok
//         }(tok);
//
//         let tok = for ((i, test_data_sync), tok): ((u32, BlockSyncData), token) in enumerate(BATCH_PACKER_TEST_DATA_SYNC) {
//             let tok = send(tok, sync_s, test_data_sync);
//             trace_fmt!("Send #{} sync {:#x}", i + u32:1, test_data_sync);
//
//             if test_data_sync.last_block || (test_data_sync.count > SymbolCount:0) {
//                 let (tok, resp) = recv(tok, resp_r);
//                 trace_fmt!("Received #{} response {:#x}", i + u32:1, resp);
//                 tok
//             } else {
//                 tok
//             }
//         }(tok);
//
//         let tok = for ((i, test_data_output), tok): ((u32, ExtendedBlockDataPacket), token) in enumerate(BATCH_PACKER_TEST_DATA_OUTPUT) {
//             let (tok, data) = recv(tok, out_r);
//             trace_fmt!("Received #{} output data {:#x}", i + u32:1, data);
//             assert_eq(test_data_output, data);
//             tok
//         }(tok);
//
//         send(tok, terminator, true);
//     }
// }

pub proc RleBlockDecoder<DATA_W: u32, ADDR_W: u32> {
    type Req = RleBlockDecoderReq<ADDR_W>;
    type Resp = RleBlockDecoderResp;
    type Output = ExtendedBlockDataPacket;

    config(
        req_r: chan<Req> in,
        resp_s: chan<Resp> out,
        output_s: chan<Output> out,
    ) {
        let (in_s, in_r) = chan<RleInput, u32:1>("in");
        let (out_s, out_r) = chan<RleOutput, u32:1>("out");
        let (sync_s, sync_r) = chan<BlockSyncData, u32:1>("sync");

        spawn RleDataPacker<DATA_W, ADDR_W>(req_r, in_s, sync_s);
        spawn rle_dec_adv::RunLengthDecoderAdv<SYMBOL_WIDTH, BLOCK_SIZE_WIDTH, common::DATA_WIDTH>(in_r, out_s);
        spawn BatchPacker(out_r, sync_r, resp_s, output_s);

        ()
    }

    init {  }

    next(state: ()) { }
}

const INST_DATA_W = u32:32;
const INST_ADDR_W = u32:32;

pub proc RleBlockDecoderInst {
    type Req = RleBlockDecoderReq<INST_ADDR_W>;
    type Resp = RleBlockDecoderResp;
    type Output = ExtendedBlockDataPacket;

    config(
        req_r: chan<Req> in,
        resp_s: chan<Resp> out,
        output_s: chan<Output> out,
    ) {
        spawn RleBlockDecoder<INST_DATA_W, INST_ADDR_W>(req_r, resp_s, output_s);
    }

    init { }

    next (state: ()) { }
}

//struct RleBlockDecoderTestData {
//    last_block: bool,
//    id: u32,
//    addr: uN[TEST_ADDR_W],
//    length: uN[TEST_ADDR_W],
//    data: uN[TEST_DATA_W],
//}
//
//const RLE_BLOCK_DECODER_TEST_DATA_MAX_LEN = u32:2048;
//
//const RLE_BLOCK_DECODER_TEST_DATA = RleBlockDecoderTestData[12]:[
//    RleBlockDecoderTestData {last_block: false, id: u32:0, addr: uN[TEST_ADDR_W]:0, length: uN[TEST_ADDR_W]:8, data: uN[TEST_DATA_W]:0xAB},
//    RleBlockDecoderTestData {last_block: false, id: u32:0, addr: uN[TEST_ADDR_W]:8, length: uN[TEST_ADDR_W]:5, data: uN[TEST_DATA_W]:0xCD},
//    RleBlockDecoderTestData {last_block: false, id: u32:1, addr: uN[TEST_ADDR_W]:512, length: uN[TEST_ADDR_W]:12, data: uN[TEST_DATA_W]:0x67},
//    RleBlockDecoderTestData {last_block: false, id: u32:1, addr: uN[TEST_ADDR_W]:544, length: uN[TEST_ADDR_W]:35, data: uN[TEST_DATA_W]:0x09},
//    RleBlockDecoderTestData {last_block: false, id: u32:1, addr: uN[TEST_ADDR_W]:576, length: uN[TEST_ADDR_W]:123, data: uN[TEST_DATA_W]:0x9D},
//    RleBlockDecoderTestData {last_block: false, id: u32:1, addr: uN[TEST_ADDR_W]:592, length: uN[TEST_ADDR_W]:1, data: uN[TEST_DATA_W]:0x1F},
//    RleBlockDecoderTestData {last_block: false, id: u32:2, addr: uN[TEST_ADDR_W]:32, length: uN[TEST_ADDR_W]:0, data: uN[TEST_DATA_W]:0x12},
//    RleBlockDecoderTestData {last_block: true, id: u32:2, addr: uN[TEST_ADDR_W]:64, length: uN[TEST_ADDR_W]:42, data: uN[TEST_DATA_W]:0xAA},
//    RleBlockDecoderTestData {last_block: false, id: u32:3, addr: uN[TEST_ADDR_W]:1242, length: uN[TEST_ADDR_W]:33, data: uN[TEST_DATA_W]:0x54},
//    RleBlockDecoderTestData {last_block: false, id: u32:3, addr: uN[TEST_ADDR_W]:5432, length: uN[TEST_ADDR_W]:0, data: uN[TEST_DATA_W]:0xC0},
//    RleBlockDecoderTestData {last_block: false, id: u32:4, addr: uN[TEST_ADDR_W]:1024, length: uN[TEST_ADDR_W]:2, data: uN[TEST_DATA_W]:0xA3},
//    RleBlockDecoderTestData {last_block: true, id: u32:4, addr: uN[TEST_ADDR_W]:2000, length: uN[TEST_ADDR_W]:0, data: uN[TEST_DATA_W]:0x83},
//];
//
//#[test_proc]
//proc RleBlockDecoderTest {
//    type TestReq = RleBlockDecoderReq<TEST_ADDR_W>;
//
//    terminator: chan<bool> out;
//
//    ctrl_s: chan<RleBlockDecoderCtrl> out;
//    req_s: chan<TestReq> out;
//
//    mem_req_r: chan<TestMemReaderReq> in;
//    mem_resp_s: chan<TestMemReaderResp> out;
//
//    output_r: chan<ExtendedBlockDataPacket> in;
//
//    config (terminator: chan<bool> out) {
//        let (ctrl_s, ctrl_r) = chan<RleBlockDecoderCtrl>("ctrl");
//        let (req_s, req_r) = chan<TestReq>("req");
//        let (mem_req_s, mem_req_r) = chan<TestMemReaderReq>("mem_req");
//        let (mem_resp_s, mem_resp_r) = chan<TestMemReaderResp>("mem_resp");
//        let (resp_s, resp_r) = chan<RleBlockDecoderResp>("resp");
//        let (output_s, output_r) = chan<ExtendedBlockDataPacket>("output");
//
//        spawn RleBlockDecoder<TEST_DATA_W, TEST_ADDR_W>(
//            ctrl_r, req_r,
//            mem_req_s, mem_resp_r,
//            resp_s, output_s
//        );
//
//        (
//            terminator,
//            ctrl_s, req_s,
//            mem_req_r, mem_resp_s,
//            resp_r, output_r,
//        )
//    }
//
//    init { }
//
//    next (state: ()) {
//        let tok = join();
//
//        let tok = for ((i, test_data), tok): ((u32, RleBlockDecoderTestData), token) in enumerate(RLE_BLOCK_DECODER_TEST_DATA) {
//            let req = TestReq {
//                last: true,
//                last_block: test_data.last_block,
//                id: test_data.id,
//                addr: test_data.addr,
//                length: test_data.length,
//            };
//            let tok = send(tok, req_s, req);
//            trace_fmt!("Sent #{} request {:#x}", i + u32:1, req);
//
//            let tok = if test_data.length > uN[TEST_ADDR_W]:0 {
//                let (tok, mem_req) = recv(tok, mem_req_r);
//                trace_fmt!("Received #{} memory read request {:#x}", i + u32:1, mem_req);
//
//                assert_eq(test_data.addr, mem_req.addr);
//                assert_eq(uN[TEST_ADDR_W]:8, mem_req.length);
//
//                let mem_resp = TestMemReaderResp {
//                    status: mem_reader::MemReaderStatus::OKAY,
//                    data: test_data.data,
//                    length: uN[TEST_ADDR_W]:8,
//                    last: true,
//                };
//
//                let tok = send(tok, mem_resp_s, mem_resp);
//                trace_fmt!("Sent #{} memory response {:#x}", i + u32:1, mem_resp);
//
//                tok
//            } else { tok };
//
//            let tok = if (test_data.length != uN[TEST_ADDR_W]:0) {
//                // non-empty block
//                for (j, tok): (u32, token) in range(u32:0, (RLE_BLOCK_DECODER_TEST_DATA_MAX_LEN * common::SYMBOL_WIDTH) / common::DATA_WIDTH) {
//                    let packets_num = ((test_data.length + common::SYMBOL_WIDTH - u32:1) / common::SYMBOL_WIDTH);
//                    if j < packets_num {
//                        let length = if (test_data.length - ((common::DATA_WIDTH / common::SYMBOL_WIDTH) * j as u32)) < (common::DATA_WIDTH / common::SYMBOL_WIDTH) {
//                            test_data.length % (common::DATA_WIDTH / common::SYMBOL_WIDTH)
//                        } else {
//                            common::DATA_WIDTH / BlockPacketLength:8
//                        };
//                        let data = for (k, data): (u32, BlockData) in range(u32:0, common::DATA_WIDTH / common::SYMBOL_WIDTH){
//                            if (k < length) {
//                                (data << common::SYMBOL_WIDTH) | (test_data.data as Symbol as BlockData)
//                            } else {
//                                data
//                            }
//                        }(BlockData:0);
//
//                        let expected_output = ExtendedBlockDataPacket {
//                            msg_type: common::SequenceExecutorMessageType::LITERAL,
//                            packet: BlockDataPacket {
//                                last: (j + u32:1) == packets_num,
//                                last_block: test_data.last_block,
//                                id: test_data.id,
//                                data: data,
//                                length: length * BlockPacketLength:8,
//                            },
//                        };
//
//                        let (tok, output) = recv(tok, output_r);
//                        trace_fmt!("Received #{}:{} output {:#x}", i + u32:1, j, output);
//
//                        assert_eq(expected_output, output);
//
//                        tok
//                    } else {
//                        tok
//                    }
//                }(tok)
//            } else if test_data.last_block {
//                // empty block with last
//                let expected_output = ExtendedBlockDataPacket {
//                    msg_type: common::SequenceExecutorMessageType::LITERAL,
//                    packet: BlockDataPacket {
//                        last: true,
//                        last_block: test_data.last_block,
//                        id: test_data.id,
//                        data: BlockData:0,
//                        length: BlockPacketLength:0,
//                    },
//                };
//
//                let (tok, output) = recv(tok, output_r);
//                trace_fmt!("Received #{} output {:#x}", i + u32:1, output);
//
//                assert_eq(expected_output, output);
//                tok
//            } else {
//                // empty block with no last
//                tok
//            };
//
//            let (tok, resp) = recv_if(tok, resp_r, req.last_block, zero!<RleBlockDecoderResp>());
//            if req.last_block {
//                trace_fmt!("Received #{} response {:#x}", i + u32:1, resp);
//            } else {};
//
//            tok
//        }(tok);
//
//        send(tok, terminator, true);
//    }
//}
