// Copyright 2023 The XLS Authors
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

// This file contains work-in-progress ZSTD decoder implementation
// More information about ZSTD decoding can be found in:
// https://datatracker.ietf.org/doc/html/rfc8878

import std;
import xls.modules.zstd.block_header;
import xls.modules.zstd.block_dec;
import xls.modules.zstd.sequence_executor;
import xls.modules.zstd.buffer as buff;
import xls.modules.zstd.common;
import xls.modules.zstd.frame_header;
import xls.modules.zstd.frame_header_test;
import xls.modules.zstd.magic;
import xls.modules.zstd.repacketizer;
import xls.examples.ram;

type Buffer = buff::Buffer;
type BlockDataPacket = common::BlockDataPacket;
type BlockData = common::BlockData;
type BlockSize = common::BlockSize;
type SequenceExecutorPacket = common::SequenceExecutorPacket;
type ZstdDecodedPacket = common::ZstdDecodedPacket;

// TODO: all of this porboably should be in common.x
const TEST_WINDOW_LOG_MAX_LIBZSTD = frame_header_test::TEST_WINDOW_LOG_MAX_LIBZSTD;

const ZSTD_RAM_ADDR_WIDTH = sequence_executor::ZSTD_RAM_ADDR_WIDTH;
const RAM_DATA_WIDTH = sequence_executor::RAM_DATA_WIDTH;
const RAM_NUM_PARTITIONS = sequence_executor::RAM_NUM_PARTITIONS;
const ZSTD_HISTORY_BUFFER_SIZE_KB = sequence_executor::ZSTD_HISTORY_BUFFER_SIZE_KB;

const BUFFER_WIDTH = common::BUFFER_WIDTH;
const DATA_WIDTH = common::DATA_WIDTH;
const ZERO_FRAME_HEADER = frame_header::ZERO_FRAME_HEADER;
const ZERO_BLOCK_HEADER = block_header::ZERO_BLOCK_HEADER;

enum ZstdDecoderStatus : u8 {
  DECODE_MAGIC_NUMBER = 0,
  DECODE_FRAME_HEADER = 1,
  DECODE_BLOCK_HEADER = 2,
  FEED_BLOCK_DECODER = 3,
  DECODE_CHECKSUM = 4,
  ERROR = 255,
}

struct ZstdDecoderState {
    status: ZstdDecoderStatus,
    buffer: Buffer<BUFFER_WIDTH>,
    frame_header: frame_header::FrameHeader,
    block_size_bytes: BlockSize,
    last: bool,
    bytes_sent: BlockSize,
}

const ZERO_DECODER_STATE = zero!<ZstdDecoderState>();

fn decode_magic_number(state: ZstdDecoderState) -> (bool, BlockDataPacket, ZstdDecoderState) {
    trace_fmt!("zstd_dec: decode_magic_number: DECODING NEW FRAME");
    trace_fmt!("zstd_dec: decode_magic_number: state: {:#x}", state);
    trace_fmt!("zstd_dec: decode_magic_number: Decoding magic number");
    let magic_result = magic::parse_magic_number(state.buffer);
    trace_fmt!("zstd_dec: decode_magic_number: magic_result: {:#x}", magic_result);
    let new_state = match magic_result.status {
        magic::MagicStatus::OK => ZstdDecoderState {
            status: ZstdDecoderStatus::DECODE_FRAME_HEADER,
            buffer: magic_result.buffer,
            ..state
        },
        magic::MagicStatus::CORRUPTED => ZstdDecoderState {
            status: ZstdDecoderStatus::ERROR,
            ..ZERO_DECODER_STATE
        },
        magic::MagicStatus::NO_ENOUGH_DATA => state,
        _ => state,
    };
    trace_fmt!("zstd_dec: decode_magic_number: new_state: {:#x}", new_state);

    (false, zero!<BlockDataPacket>(), new_state)
}

fn decode_frame_header(state: ZstdDecoderState) -> (bool, BlockDataPacket, ZstdDecoderState) {
    trace_fmt!("zstd_dec: decode_frame_header: DECODING FRAME HEADER");
    trace_fmt!("zstd_dec: decode_frame_header: state: {:#x}", state);
    let frame_header_result = frame_header::parse_frame_header<TEST_WINDOW_LOG_MAX_LIBZSTD>(state.buffer);
    trace_fmt!("zstd_dec: decode_frame_header: frame_header_result: {:#x}", frame_header_result);
    let new_state = match frame_header_result.status {
        frame_header::FrameHeaderStatus::OK => ZstdDecoderState {
            status: ZstdDecoderStatus::DECODE_BLOCK_HEADER,
            buffer: frame_header_result.buffer,
            frame_header: frame_header_result.header,
            ..state
        },
        frame_header::FrameHeaderStatus::CORRUPTED => ZstdDecoderState {
            status: ZstdDecoderStatus::ERROR,
            ..ZERO_DECODER_STATE
        },
        frame_header::FrameHeaderStatus::NO_ENOUGH_DATA => state,
        frame_header::FrameHeaderStatus::UNSUPPORTED_WINDOW_SIZE => ZstdDecoderState {
            status: ZstdDecoderStatus::ERROR,
            ..ZERO_DECODER_STATE
        },
        _ => state,
    };
    trace_fmt!("zstd_dec: decode_frame_header: new_state: {:#x}", new_state);

    (false, zero!<BlockDataPacket>(), new_state)
}

fn decode_block_header(state: ZstdDecoderState) -> (bool, BlockDataPacket, ZstdDecoderState) {
    trace_fmt!("zstd_dec: decode_block_header: DECODING BLOCK HEADER");
    trace_fmt!("zstd_dec: decode_block_header: state: {:#x}", state);
    let block_header_result = block_header::parse_block_header(state.buffer);
    trace_fmt!("zstd_dec: decode_block_header: block_header_result: {:#x}", block_header_result);
    let new_state = match block_header_result.status {
        block_header::BlockHeaderStatus::OK => {
            trace_fmt!("zstd_dec: BlockHeader: {:#x}", block_header_result.header);
            match block_header_result.header.btype {
                common::BlockType::RAW => ZstdDecoderState {
                    status: ZstdDecoderStatus::FEED_BLOCK_DECODER,
                    buffer: state.buffer,
                    block_size_bytes: block_header_result.header.size as BlockSize + BlockSize:3,
                    last: block_header_result.header.last,
                    bytes_sent: BlockSize:0,
                    ..state
                },
                common::BlockType::RLE => ZstdDecoderState {
                    status: ZstdDecoderStatus::FEED_BLOCK_DECODER,
                    buffer: state.buffer,
                    block_size_bytes: BlockSize:4,
                    last: block_header_result.header.last,
                    bytes_sent: BlockSize:0,
                    ..state
                },
                common::BlockType::COMPRESSED => ZstdDecoderState {
                    status: ZstdDecoderStatus::FEED_BLOCK_DECODER,
                    buffer: state.buffer,
                    block_size_bytes: block_header_result.header.size as BlockSize + BlockSize:3,
                    last: block_header_result.header.last,
                    bytes_sent: BlockSize:0,
                    ..state
                },
                _ => {
                    fail!("impossible_case", state)
                }
            }
        },
        block_header::BlockHeaderStatus::CORRUPTED => ZstdDecoderState {
                status: ZstdDecoderStatus::ERROR,
                ..ZERO_DECODER_STATE
        },
        block_header::BlockHeaderStatus::NO_ENOUGH_DATA => state,
        _ => state,
    };
    trace_fmt!("zstd_dec: decode_block_header: new_state: {:#x}", new_state);

    (false, zero!<BlockDataPacket>(), new_state)
}

fn feed_block_decoder(state: ZstdDecoderState) -> (bool, BlockDataPacket, ZstdDecoderState) {
    trace_fmt!("zstd_dec: feed_block_decoder: FEEDING BLOCK DECODER");
    trace_fmt!("zstd_dec: feed_block_decoder: state: {:#x}", state);
    let remaining_bytes_to_send = state.block_size_bytes - state.bytes_sent;
    trace_fmt!("zstd_dec: feed_block_decoder: remaining_bytes_to_send: {}", remaining_bytes_to_send);
    let buffer_length_bytes = state.buffer.length >> 3;
    trace_fmt!("zstd_dec: feed_block_decoder: buffer_length_bytes: {}", buffer_length_bytes);
    let data_width_bytes = (DATA_WIDTH >> 3) as BlockSize;
    trace_fmt!("zstd_dec: feed_block_decoder: data_width_bytes: {}", data_width_bytes);
    let remaining_bytes_to_send_now = std::umin(remaining_bytes_to_send, data_width_bytes);
    trace_fmt!("zstd_dec: feed_block_decoder: remaining_bytes_to_send_now: {}", remaining_bytes_to_send_now);
    if (buffer_length_bytes >= remaining_bytes_to_send_now as u32) {
        let remaining_bits_to_send_now = (remaining_bytes_to_send_now as u32) << 3;
        trace_fmt!("zstd_dec: feed_block_decoder: remaining_bits_to_send_now: {}", remaining_bits_to_send_now);
        let last_packet = (remaining_bytes_to_send == remaining_bytes_to_send_now);
        trace_fmt!("zstd_dec: feed_block_decoder: last_packet: {}", last_packet);
        let (buffer_result, data_to_send) = buff::buffer_pop_checked(state.buffer, remaining_bits_to_send_now);
        match buffer_result.status {
            buff::BufferStatus::OK => {
                let decoder_channel_data = BlockDataPacket {
                    last: last_packet,
                    last_block: state.last,
                    id: u32:0,
                    data: data_to_send[0: DATA_WIDTH as s32],
                    length: remaining_bits_to_send_now,
                };
                let new_fsm_status = if (last_packet) {
                    if (state.last) {
                        if (state.frame_header.content_checksum_flag) {
                            ZstdDecoderStatus::DECODE_CHECKSUM
                        } else {
                            ZstdDecoderStatus::DECODE_MAGIC_NUMBER
                        }
                    } else {
                        ZstdDecoderStatus::DECODE_BLOCK_HEADER
                    }
                } else {
                    ZstdDecoderStatus::FEED_BLOCK_DECODER
                };
                trace_fmt!("zstd_dec: feed_block_decoder: packet to decode: {:#x}", decoder_channel_data);
                let new_state = (true, decoder_channel_data, ZstdDecoderState {
                    bytes_sent: state.bytes_sent + remaining_bytes_to_send_now,
                    buffer: buffer_result.buffer,
                    status: new_fsm_status,
                    ..state
                });
                trace_fmt!("zstd_dec: feed_block_decoder: new_state: {:#x}", new_state);
                new_state
            },
            _ => {
                fail!("should_not_happen_1", (false, zero!<BlockDataPacket>(), state))
            }
        }
    } else {
        trace_fmt!("zstd_dec: feed_block_decoder: Not enough data for intermediate FEED_BLOCK_DECODER block dump");
        (false, zero!<BlockDataPacket>(), state)
    }
}

fn decode_checksum(state: ZstdDecoderState) -> (bool, BlockDataPacket, ZstdDecoderState) {
    trace_fmt!("zstd_dec: decode_checksum: DECODE CHECKSUM");
    trace_fmt!("zstd_dec: decode_checksum: state: {:#x}", state);
    // Pop fixed checksum size of 4 bytes
    let (buffer_result, _) = buff::buffer_pop_checked(state.buffer, u32:32);

    let new_state = ZstdDecoderState {
            status: ZstdDecoderStatus::DECODE_MAGIC_NUMBER,
            buffer: buffer_result.buffer,
            ..state
    };
    trace_fmt!("zstd_dec: decode_checksum: new_state: {:#x}", new_state);

    (false, zero!<BlockDataPacket>(), new_state)
}

pub proc ZstdDecoder {
    input_r: chan<BlockData> in;
    block_dec_in_s: chan<BlockDataPacket> out;
    output_s: chan<ZstdDecodedPacket> out;
    looped_channel_r: chan<SequenceExecutorPacket> in;
    looped_channel_s: chan<SequenceExecutorPacket> out;
    ram_rd_req_0_s: chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>> out;
    ram_rd_req_1_s: chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>> out;
    ram_rd_req_2_s: chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>> out;
    ram_rd_req_3_s: chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>> out;
    ram_rd_req_4_s: chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>> out;
    ram_rd_req_5_s: chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>> out;
    ram_rd_req_6_s: chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>> out;
    ram_rd_req_7_s: chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>> out;
    ram_rd_resp_0_r: chan<ram::ReadResp<RAM_DATA_WIDTH>> in;
    ram_rd_resp_1_r: chan<ram::ReadResp<RAM_DATA_WIDTH>> in;
    ram_rd_resp_2_r: chan<ram::ReadResp<RAM_DATA_WIDTH>> in;
    ram_rd_resp_3_r: chan<ram::ReadResp<RAM_DATA_WIDTH>> in;
    ram_rd_resp_4_r: chan<ram::ReadResp<RAM_DATA_WIDTH>> in;
    ram_rd_resp_5_r: chan<ram::ReadResp<RAM_DATA_WIDTH>> in;
    ram_rd_resp_6_r: chan<ram::ReadResp<RAM_DATA_WIDTH>> in;
    ram_rd_resp_7_r: chan<ram::ReadResp<RAM_DATA_WIDTH>> in;
    ram_wr_req_0_s: chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>> out;
    ram_wr_req_1_s: chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>> out;
    ram_wr_req_2_s: chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>> out;
    ram_wr_req_3_s: chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>> out;
    ram_wr_req_4_s: chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>> out;
    ram_wr_req_5_s: chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>> out;
    ram_wr_req_6_s: chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>> out;
    ram_wr_req_7_s: chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>> out;
    ram_wr_resp_0_r: chan<ram::WriteResp> in;
    ram_wr_resp_1_r: chan<ram::WriteResp> in;
    ram_wr_resp_2_r: chan<ram::WriteResp> in;
    ram_wr_resp_3_r: chan<ram::WriteResp> in;
    ram_wr_resp_4_r: chan<ram::WriteResp> in;
    ram_wr_resp_5_r: chan<ram::WriteResp> in;
    ram_wr_resp_6_r: chan<ram::WriteResp> in;
    ram_wr_resp_7_r: chan<ram::WriteResp> in;

    init {(ZERO_DECODER_STATE)}

    config (
        input_r: chan<BlockData> in,
        output_s: chan<ZstdDecodedPacket> out,
        looped_channel_r: chan<SequenceExecutorPacket> in,
        looped_channel_s: chan<SequenceExecutorPacket> out,
        ram_rd_req_0_s: chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>> out,
        ram_rd_req_1_s: chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>> out,
        ram_rd_req_2_s: chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>> out,
        ram_rd_req_3_s: chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>> out,
        ram_rd_req_4_s: chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>> out,
        ram_rd_req_5_s: chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>> out,
        ram_rd_req_6_s: chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>> out,
        ram_rd_req_7_s: chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>> out,
        ram_rd_resp_0_r: chan<ram::ReadResp<RAM_DATA_WIDTH>> in,
        ram_rd_resp_1_r: chan<ram::ReadResp<RAM_DATA_WIDTH>> in,
        ram_rd_resp_2_r: chan<ram::ReadResp<RAM_DATA_WIDTH>> in,
        ram_rd_resp_3_r: chan<ram::ReadResp<RAM_DATA_WIDTH>> in,
        ram_rd_resp_4_r: chan<ram::ReadResp<RAM_DATA_WIDTH>> in,
        ram_rd_resp_5_r: chan<ram::ReadResp<RAM_DATA_WIDTH>> in,
        ram_rd_resp_6_r: chan<ram::ReadResp<RAM_DATA_WIDTH>> in,
        ram_rd_resp_7_r: chan<ram::ReadResp<RAM_DATA_WIDTH>> in,
        ram_wr_req_0_s: chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>> out,
        ram_wr_req_1_s: chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>> out,
        ram_wr_req_2_s: chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>> out,
        ram_wr_req_3_s: chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>> out,
        ram_wr_req_4_s: chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>> out,
        ram_wr_req_5_s: chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>> out,
        ram_wr_req_6_s: chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>> out,
        ram_wr_req_7_s: chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>> out,
        ram_wr_resp_0_r: chan<ram::WriteResp> in,
        ram_wr_resp_1_r: chan<ram::WriteResp> in,
        ram_wr_resp_2_r: chan<ram::WriteResp> in,
        ram_wr_resp_3_r: chan<ram::WriteResp> in,
        ram_wr_resp_4_r: chan<ram::WriteResp> in,
        ram_wr_resp_5_r: chan<ram::WriteResp> in,
        ram_wr_resp_6_r: chan<ram::WriteResp> in,
        ram_wr_resp_7_r: chan<ram::WriteResp> in,
    ) {
        let (block_dec_in_s, block_dec_in_r) = chan<BlockDataPacket, u32:1>("block_dec_in");
        let (seq_exec_in_s, seq_exec_in_r) = chan<SequenceExecutorPacket, u32:1>("seq_exec_in");
        let (repacketizer_in_s, repacketizer_in_r) = chan<ZstdDecodedPacket, u32:1>("repacketizer_in");

        spawn block_dec::BlockDecoder(block_dec_in_r, seq_exec_in_s);

        spawn sequence_executor::SequenceExecutor<ZSTD_HISTORY_BUFFER_SIZE_KB>(
            seq_exec_in_r, repacketizer_in_s,
            looped_channel_r, looped_channel_s,
            ram_rd_req_0_s,  ram_rd_req_1_s,  ram_rd_req_2_s,  ram_rd_req_3_s,
            ram_rd_req_4_s,  ram_rd_req_5_s,  ram_rd_req_6_s,  ram_rd_req_7_s,
            ram_rd_resp_0_r, ram_rd_resp_1_r, ram_rd_resp_2_r, ram_rd_resp_3_r,
            ram_rd_resp_4_r, ram_rd_resp_5_r, ram_rd_resp_6_r, ram_rd_resp_7_r,
            ram_wr_req_0_s,  ram_wr_req_1_s,  ram_wr_req_2_s,  ram_wr_req_3_s,
            ram_wr_req_4_s,  ram_wr_req_5_s,  ram_wr_req_6_s,  ram_wr_req_7_s,
            ram_wr_resp_0_r, ram_wr_resp_1_r, ram_wr_resp_2_r, ram_wr_resp_3_r,
            ram_wr_resp_4_r, ram_wr_resp_5_r, ram_wr_resp_6_r, ram_wr_resp_7_r,
        );

        spawn repacketizer::Repacketizer(repacketizer_in_r, output_s);

        (input_r, block_dec_in_s, output_s, looped_channel_r, looped_channel_s,
         ram_rd_req_0_s,  ram_rd_req_1_s,  ram_rd_req_2_s,  ram_rd_req_3_s,
         ram_rd_req_4_s,  ram_rd_req_5_s,  ram_rd_req_6_s,  ram_rd_req_7_s,
         ram_rd_resp_0_r, ram_rd_resp_1_r, ram_rd_resp_2_r, ram_rd_resp_3_r,
         ram_rd_resp_4_r, ram_rd_resp_5_r, ram_rd_resp_6_r, ram_rd_resp_7_r,
         ram_wr_req_0_s,  ram_wr_req_1_s,  ram_wr_req_2_s,  ram_wr_req_3_s,
         ram_wr_req_4_s,  ram_wr_req_5_s,  ram_wr_req_6_s,  ram_wr_req_7_s,
         ram_wr_resp_0_r, ram_wr_resp_1_r, ram_wr_resp_2_r, ram_wr_resp_3_r,
         ram_wr_resp_4_r, ram_wr_resp_5_r, ram_wr_resp_6_r, ram_wr_resp_7_r)
    }

    next (tok: token, state: ZstdDecoderState) {
        trace_fmt!("zstd_dec: next(): state: {:#x}", state);
        let can_fit = buff::buffer_can_fit(state.buffer, BlockData:0);
        trace_fmt!("zstd_dec: next(): can_fit: {}", can_fit);
        let (tok, data, recv_valid) = recv_if_non_blocking(tok, input_r, can_fit, BlockData:0);
        let state = if (can_fit && recv_valid) {
            let buffer = buff::buffer_append(state.buffer, data);
            trace_fmt!("zstd_dec: next(): received more data: {:#x}", data);
            ZstdDecoderState {buffer, ..state}
        } else {
            state
        };
        trace_fmt!("zstd_dec: next(): state after receive: {:#x}", state);

        let (do_send, data_to_send, state) = match state.status {
            ZstdDecoderStatus::DECODE_MAGIC_NUMBER =>
                decode_magic_number(state),
            ZstdDecoderStatus::DECODE_FRAME_HEADER =>
                decode_frame_header(state),
            ZstdDecoderStatus::DECODE_BLOCK_HEADER =>
                decode_block_header(state),
            ZstdDecoderStatus::FEED_BLOCK_DECODER =>
                feed_block_decoder(state),
            ZstdDecoderStatus::DECODE_CHECKSUM =>
                decode_checksum(state),
            _ => (false, zero!<BlockDataPacket>(), state)
        };

        trace_fmt!("zstd_dec: next(): do_send: {:#x}, data_to_send: {:#x}, state: {:#x}", do_send, data_to_send, state);
        let tok = send_if(tok, block_dec_in_s, do_send, data_to_send);

        state
    }
}

const TEST_RAM_SIZE = sequence_executor::ram_size(ZSTD_HISTORY_BUFFER_SIZE_KB);
const RAM_WORD_PARTITION_SIZE = sequence_executor::RAM_WORD_PARTITION_SIZE;
const TEST_RAM_SIMULTANEOUS_READ_WRITE_BEHAVIOR = sequence_executor::TEST_RAM_SIMULTANEOUS_READ_WRITE_BEHAVIOR;
const TEST_RAM_INITIALIZED = sequence_executor::TEST_RAM_INITIALIZED;
const TEST_RAM_ASSERT_VALID_READ:bool = {false};

pub proc ZstdDecoderTest {
    input_r: chan<BlockData> in;
    output_s: chan<ZstdDecodedPacket> out;

    init {()}

    config (
        input_r: chan<BlockData> in,
        output_s: chan<ZstdDecodedPacket> out,
    ) {
        let (looped_channel_s, looped_channel_r) = chan<SequenceExecutorPacket, u32:1>("looped_channel");

        let (ram_rd_req_0_s, ram_rd_req_0_r) = chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>, u32:1>("ram_rd_req_0");
        let (ram_rd_req_1_s, ram_rd_req_1_r) = chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>, u32:1>("ram_rd_req_1");
        let (ram_rd_req_2_s, ram_rd_req_2_r) = chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>, u32:1>("ram_rd_req_2");
        let (ram_rd_req_3_s, ram_rd_req_3_r) = chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>, u32:1>("ram_rd_req_3");
        let (ram_rd_req_4_s, ram_rd_req_4_r) = chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>, u32:1>("ram_rd_req_4");
        let (ram_rd_req_5_s, ram_rd_req_5_r) = chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>, u32:1>("ram_rd_req_5");
        let (ram_rd_req_6_s, ram_rd_req_6_r) = chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>, u32:1>("ram_rd_req_6");
        let (ram_rd_req_7_s, ram_rd_req_7_r) = chan<ram::ReadReq<ZSTD_RAM_ADDR_WIDTH, RAM_NUM_PARTITIONS>, u32:1>("ram_rd_req_7");

        let (ram_rd_resp_0_s, ram_rd_resp_0_r) = chan<ram::ReadResp<RAM_DATA_WIDTH>, u32:1>("ram_rd_resp_0");
        let (ram_rd_resp_1_s, ram_rd_resp_1_r) = chan<ram::ReadResp<RAM_DATA_WIDTH>, u32:1>("ram_rd_resp_1");
        let (ram_rd_resp_2_s, ram_rd_resp_2_r) = chan<ram::ReadResp<RAM_DATA_WIDTH>, u32:1>("ram_rd_resp_2");
        let (ram_rd_resp_3_s, ram_rd_resp_3_r) = chan<ram::ReadResp<RAM_DATA_WIDTH>, u32:1>("ram_rd_resp_3");
        let (ram_rd_resp_4_s, ram_rd_resp_4_r) = chan<ram::ReadResp<RAM_DATA_WIDTH>, u32:1>("ram_rd_resp_4");
        let (ram_rd_resp_5_s, ram_rd_resp_5_r) = chan<ram::ReadResp<RAM_DATA_WIDTH>, u32:1>("ram_rd_resp_5");
        let (ram_rd_resp_6_s, ram_rd_resp_6_r) = chan<ram::ReadResp<RAM_DATA_WIDTH>, u32:1>("ram_rd_resp_6");
        let (ram_rd_resp_7_s, ram_rd_resp_7_r) = chan<ram::ReadResp<RAM_DATA_WIDTH>, u32:1>("ram_rd_resp_7");

        let (ram_wr_req_0_s, ram_wr_req_0_r) = chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>, u32:1>("ram_wr_req_0");
        let (ram_wr_req_1_s, ram_wr_req_1_r) = chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>, u32:1>("ram_wr_req_1");
        let (ram_wr_req_2_s, ram_wr_req_2_r) = chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>, u32:1>("ram_wr_req_2");
        let (ram_wr_req_3_s, ram_wr_req_3_r) = chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>, u32:1>("ram_wr_req_3");
        let (ram_wr_req_4_s, ram_wr_req_4_r) = chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>, u32:1>("ram_wr_req_4");
        let (ram_wr_req_5_s, ram_wr_req_5_r) = chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>, u32:1>("ram_wr_req_5");
        let (ram_wr_req_6_s, ram_wr_req_6_r) = chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>, u32:1>("ram_wr_req_6");
        let (ram_wr_req_7_s, ram_wr_req_7_r) = chan<ram::WriteReq<ZSTD_RAM_ADDR_WIDTH, RAM_DATA_WIDTH, RAM_NUM_PARTITIONS>, u32:1>("ram_wr_req_7");

        let (ram_wr_resp_0_s, ram_wr_resp_0_r) = chan<ram::WriteResp, u32:1>("ram_wr_resp_0");
        let (ram_wr_resp_1_s, ram_wr_resp_1_r) = chan<ram::WriteResp, u32:1>("ram_wr_resp_1");
        let (ram_wr_resp_2_s, ram_wr_resp_2_r) = chan<ram::WriteResp, u32:1>("ram_wr_resp_2");
        let (ram_wr_resp_3_s, ram_wr_resp_3_r) = chan<ram::WriteResp, u32:1>("ram_wr_resp_3");
        let (ram_wr_resp_4_s, ram_wr_resp_4_r) = chan<ram::WriteResp, u32:1>("ram_wr_resp_4");
        let (ram_wr_resp_5_s, ram_wr_resp_5_r) = chan<ram::WriteResp, u32:1>("ram_wr_resp_5");
        let (ram_wr_resp_6_s, ram_wr_resp_6_r) = chan<ram::WriteResp, u32:1>("ram_wr_resp_6");
        let (ram_wr_resp_7_s, ram_wr_resp_7_r) = chan<ram::WriteResp, u32:1>("ram_wr_resp_7");

        spawn ZstdDecoder(
            input_r, output_s,
            looped_channel_r, looped_channel_s,
            ram_rd_req_0_s,  ram_rd_req_1_s,  ram_rd_req_2_s,  ram_rd_req_3_s,
            ram_rd_req_4_s,  ram_rd_req_5_s,  ram_rd_req_6_s,  ram_rd_req_7_s,
            ram_rd_resp_0_r, ram_rd_resp_1_r, ram_rd_resp_2_r, ram_rd_resp_3_r,
            ram_rd_resp_4_r, ram_rd_resp_5_r, ram_rd_resp_6_r, ram_rd_resp_7_r,
            ram_wr_req_0_s,  ram_wr_req_1_s,  ram_wr_req_2_s,  ram_wr_req_3_s,
            ram_wr_req_4_s,  ram_wr_req_5_s,  ram_wr_req_6_s,  ram_wr_req_7_s,
            ram_wr_resp_0_r, ram_wr_resp_1_r, ram_wr_resp_2_r, ram_wr_resp_3_r,
            ram_wr_resp_4_r, ram_wr_resp_5_r, ram_wr_resp_6_r, ram_wr_resp_7_r,
        );

        spawn ram::RamModel<
            RAM_DATA_WIDTH, TEST_RAM_SIZE, RAM_WORD_PARTITION_SIZE,
            TEST_RAM_SIMULTANEOUS_READ_WRITE_BEHAVIOR, TEST_RAM_INITIALIZED, TEST_RAM_ASSERT_VALID_READ>
            (ram_rd_req_0_r, ram_rd_resp_0_s, ram_wr_req_0_r, ram_wr_resp_0_s);
        spawn ram::RamModel<
            RAM_DATA_WIDTH, TEST_RAM_SIZE, RAM_WORD_PARTITION_SIZE,
            TEST_RAM_SIMULTANEOUS_READ_WRITE_BEHAVIOR, TEST_RAM_INITIALIZED, TEST_RAM_ASSERT_VALID_READ>
            (ram_rd_req_1_r, ram_rd_resp_1_s, ram_wr_req_1_r, ram_wr_resp_1_s);
        spawn ram::RamModel<
            RAM_DATA_WIDTH, TEST_RAM_SIZE, RAM_WORD_PARTITION_SIZE,
            TEST_RAM_SIMULTANEOUS_READ_WRITE_BEHAVIOR, TEST_RAM_INITIALIZED, TEST_RAM_ASSERT_VALID_READ>
            (ram_rd_req_2_r, ram_rd_resp_2_s, ram_wr_req_2_r, ram_wr_resp_2_s);
        spawn ram::RamModel<
            RAM_DATA_WIDTH, TEST_RAM_SIZE, RAM_WORD_PARTITION_SIZE,
            TEST_RAM_SIMULTANEOUS_READ_WRITE_BEHAVIOR, TEST_RAM_INITIALIZED, TEST_RAM_ASSERT_VALID_READ>
            (ram_rd_req_3_r, ram_rd_resp_3_s, ram_wr_req_3_r, ram_wr_resp_3_s);
        spawn ram::RamModel<
            RAM_DATA_WIDTH, TEST_RAM_SIZE, RAM_WORD_PARTITION_SIZE,
            TEST_RAM_SIMULTANEOUS_READ_WRITE_BEHAVIOR, TEST_RAM_INITIALIZED, TEST_RAM_ASSERT_VALID_READ>
            (ram_rd_req_4_r, ram_rd_resp_4_s, ram_wr_req_4_r, ram_wr_resp_4_s);
        spawn ram::RamModel<
            RAM_DATA_WIDTH, TEST_RAM_SIZE, RAM_WORD_PARTITION_SIZE,
            TEST_RAM_SIMULTANEOUS_READ_WRITE_BEHAVIOR, TEST_RAM_INITIALIZED, TEST_RAM_ASSERT_VALID_READ>
            (ram_rd_req_5_r, ram_rd_resp_5_s, ram_wr_req_5_r, ram_wr_resp_5_s);
        spawn ram::RamModel<
            RAM_DATA_WIDTH, TEST_RAM_SIZE, RAM_WORD_PARTITION_SIZE,
            TEST_RAM_SIMULTANEOUS_READ_WRITE_BEHAVIOR, TEST_RAM_INITIALIZED, TEST_RAM_ASSERT_VALID_READ>
            (ram_rd_req_6_r, ram_rd_resp_6_s, ram_wr_req_6_r, ram_wr_resp_6_s);
        spawn ram::RamModel<
            RAM_DATA_WIDTH, TEST_RAM_SIZE, RAM_WORD_PARTITION_SIZE,
            TEST_RAM_SIMULTANEOUS_READ_WRITE_BEHAVIOR, TEST_RAM_INITIALIZED, TEST_RAM_ASSERT_VALID_READ>
            (ram_rd_req_7_r, ram_rd_resp_7_s, ram_wr_req_7_r, ram_wr_resp_7_s);

        (input_r, output_s)
    }

    next (tok: token, state: ()) {}
}

#[test_proc]
proc ZstdDecoderDslxTest {
    terminator: chan<bool> out;
    input_s: chan<BlockData> out;
    output_r: chan<ZstdDecodedPacket> in;

    init {}

    config (terminator: chan<bool> out) {
        let (input_s, input_r) = chan<BlockData>("input");
        let (output_s, output_r) = chan<ZstdDecodedPacket>("output");

        spawn ZstdDecoderTest(input_r, output_s);

        (terminator, input_s, output_r)
    }

    next (tok: token, state: ()) {
        let EncodedData: BlockData[5] = [
            // frame #1 - RAW blocks only + empty blocks + frame end not aligned to 8 bytes
            //BlockData:0x0004_23c4_fd2f_b528,
            //BlockData:0x0020_0000_0000_0000,
            //BlockData:0x0000_007d_cf70_c100,
            //BlockData:0x0000_0000_0000_0000,
            //BlockData:0x0000_0000_0000_0000,
            //BlockData:0xbd7e_df00_0001_0000,
            //BlockData:0x0000_0000_0000_0031, // Decoder will end up in ERROR state after consuming
                                             // the checksum because there is no magic number of
                                             // the next frame after this one.
            // frame #2 - RAW blocks only + empty blocks + frame end not aligned to 8 bytes
            //BlockData:0x109d_5b84_fd2f_b528,
            //BlockData:0x1e4e_9900_c0e0_0000,
            //BlockData:0x88ae_263e_ebba_439f,
            //BlockData:0xd81d_9d33_821e_5cbe,
            //BlockData:0xd715_37f5_40af_ffc7,
            //BlockData:0x4540_59ed_e57d_4c32,
            //BlockData:0x0030_5049_e91f_b446,
            //BlockData:0x76e0_22ce_a35e_a1bf,
            //BlockData:0x9120_18cc_fab7_1370,
            //BlockData:0x4345_9b74_5728_5980,
            //BlockData:0x496f_c1c0_d785_a373,
            //BlockData:0x2ffc_8fac_a694_506d,
            //BlockData:0xe874_b26e_53df_8044,
            //BlockData:0x6bba_9f9f_c262_99dd,
            //BlockData:0xd2a4_ece9_64c6_c9f9,
            //BlockData:0x7a55_b0f7_e443_3962,
            //BlockData:0x5780_84cd_f872_3659,
            //BlockData:0x36df_6045_2053_27e6,
            //BlockData:0x63e9_1f97_45d3_d8e5,
            //BlockData:0x5190_1197_c7b3_11e4,
            //BlockData:0xe7eb_4fa6_b094_ed6d,
            //BlockData:0x5690_6c4c_de57_5700,
            //BlockData:0x24c6_4efb_e730_9f4f,
            //BlockData:0x3cbc_79af_5ce0_963c,
            //BlockData:0x5e13_c0e2_4caa_c218,
            //BlockData:0x1e62_92dd_37ad_92b5,
            //BlockData:0x475b_d126_6a8b_10a6,
            //BlockData:0x4c6d_7db6_9532_465c,
            //BlockData:0x60ce_bb38_1f50_844b,
            //BlockData:0x2f22_e4dc_a249_f892,
            //BlockData:0x1110_1d55_191d_3d31,
            //BlockData:0xb19e_a4bd_46b2_6258,
            //BlockData:0x89f8_678c_c0a2_36dc,
            //BlockData:0x1db2_8b5b_ed51_55d0,
            //BlockData:0xf7e1_d650_8f36_a47b,
            //BlockData:0x8950_8373_315a_e79f,
            //BlockData:0x2e77_1430_5f95_20f5,
            //BlockData:0x5e91_68d1_bf1d_1133,
            //BlockData:0x4498_898a_8f25_9b72,
            //BlockData:0xb7c5_2170_a85b_3d23,
            //BlockData:0x9f89_1295_3ebd_c531,
            //BlockData:0x37ed_d2b2_c0da_629c,
            //BlockData:0x5087_b584_b052_d85a,
            //BlockData:0x4ad3_96e0_b824_80ef,
            //BlockData:0xe4e3_f860_d499_8113,
            //BlockData:0x79d4_136f_6284_7be8,
            //BlockData:0xaf1f_4a41_aad1_89d4,
            //BlockData:0xfe5b_6a25_bcca_391b,
            //BlockData:0xc1ed_f1b1_613f_b241,
            //BlockData:0x83a3_8a62_6045_5775,
            //BlockData:0xda89_9993_3e7b_1d27,
            //BlockData:0xcc4b_3ea7_3f1c_00ac,
            //BlockData:0xa974_916d_bfe8_80c0,
            //BlockData:0xc300_0080_0000_0023,
            //BlockData:0x9e82_0000_1000_0000,
            //BlockData:0x0000_0000_0000_f684,

            // frame #3 - RLE blocks only + empty blocks
             BlockData:0x0081_3b84_fd2f_b528,
             BlockData:0x01ea_2500_01da_0000,
             BlockData:0x000a_9c00_0002_5c00,
             BlockData:0xe5b1_9d00_0043_2d00,
             BlockData:0x0000_0000_0000_3d2d,
        ];

        let tok = for ((counter, block_data), tok): ((u32, BlockData), token) in enumerate(EncodedData) {
            let tok = send(tok, input_s, block_data);
            trace_fmt!("Sent #{} encoded block data, {:#x}", counter + u32:1, block_data);
            (tok)
        }(tok);

        let tok = for (counter, tok): (u32, token) in range(u32:0, u32:17) {
            let (tok, decoded_packet) = recv(tok, output_r);
            trace_fmt!("Received #{} decoded packet, data: {:#x}", counter, decoded_packet);
            tok
        }(tok);

        send(tok, terminator, true);
    }
}
