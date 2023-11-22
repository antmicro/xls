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

// This file contains the DecoderMux Proc, which collects data from
// specialized Raw, RLE, and Compressed Block decoders and re-sends them in
// the correct order.

import std
import xls.modules.zstd.common as common

type BlockDataPacket = common::BlockDataPacket;
type BlockType = common::BlockType;

const MAX_ID = common::DATA_WIDTH;
const DATA_WIDTH = common::DATA_WIDTH;


struct DecoderMuxState {
    prev_id: u32,
    prev_last: bool,
    prev_valid: bool,
    raw_data: BlockDataPacket,
    raw_data_valid: bool,
    rle_data: BlockDataPacket,
    rle_data_valid: bool,
    compressed_data: BlockDataPacket,
    compressed_data_valid: bool,
}

const ZERO_DECODER_MUX_STATE = zero!<DecoderMuxState>();

pub proc DecoderMux {
    raw_r: chan<BlockDataPacket> in;
    rle_r: chan<BlockDataPacket> in;
    cmp_r: chan<BlockDataPacket> in;
    output_s: chan<bits[DATA_WIDTH]> out;

    init {(ZERO_DECODER_MUX_STATE)}

    config (
        raw_r: chan<BlockDataPacket> in,
        rle_r: chan<BlockDataPacket> in,
        cmp_r: chan<BlockDataPacket> in,
        output_s: chan<bits[DATA_WIDTH]> out,
    ) {(raw_r, rle_r, cmp_r, output_s)}

    next (tok: token, state: DecoderMuxState) {
        let (tok, raw_data, raw_data_valid) = recv_if_non_blocking(
            tok, raw_r, !state.raw_data_valid, zero!<BlockDataPacket>());
        let state = if (raw_data_valid) {
            DecoderMuxState {raw_data, raw_data_valid, ..state}
        } else { state };

        let (tok, rle_data, rle_data_valid) = recv_if_non_blocking(
            tok, rle_r, !state.rle_data_valid, zero!<BlockDataPacket>());
        let state = if (rle_data_valid) {
            DecoderMuxState { rle_data, rle_data_valid, ..state}
        } else { state };

        let (tok, compressed_data, compressed_data_valid) = recv_if_non_blocking(
            tok, cmp_r, !state.compressed_data_valid, zero!<BlockDataPacket>());
        let state = if (compressed_data_valid) {
            DecoderMuxState { compressed_data, compressed_data_valid, ..state}
        } else { state };

        let new_id = state.prev_valid && state.prev_last || !state.prev_last;
        let (do_send, data_to_send, state) = if !new_id {
            if state.raw_data_valid && (state.prev_id == state.raw_data.id) {
                (true, state.raw_data.data, DecoderMuxState {
                    raw_data_valid: false,
                    prev_valid : true,
                    prev_id: state.raw_data.id,
                    prev_last: state.raw_data.last,
                    ..state})
            } else if state.rle_data_valid && (state.prev_id == state.rle_data.id) {
                (true, state.rle_data.data, DecoderMuxState {
                    rle_data_valid: false,
                    prev_valid : true,
                    prev_id: state.rle_data.id,
                    prev_last: state.rle_data.last,
                    ..state})
            } else if state.compressed_data_valid && (state.prev_id == state.compressed_data.id) {
                (true, state.compressed_data.data, DecoderMuxState {
                    compressed_data_valid: false,
                    prev_valid : true,
                    prev_id: state.compressed_data.id,
                    prev_last: state.compressed_data.last,
                    ..state})
            } else {
                (false, bits[DATA_WIDTH]:0, state)
            }
        } else {
            let raw_id = if state.raw_data_valid { state.raw_data.id } else { MAX_ID };
            let rle_id = if state.rle_data_valid { state.rle_data.id } else { MAX_ID };
            let compressed_id = if state.compressed_data_valid { state.compressed_data.id } else { MAX_ID };

            if (state.prev_id >= (std::umin(std::umin(rle_id, raw_id), compressed_id))) && (state.prev_valid) {
                fail!("wrong_id", ())
            } else {()};

            if (state.raw_data_valid &&
               (state.raw_data.id < std::umin(rle_id, compressed_id))) {
                (true, state.raw_data.data, DecoderMuxState {
                    raw_data_valid: false,
                    ..state})
            } else if (state.rle_data_valid &&
                      (state.rle_data.id < std::umin(raw_id, compressed_id))) {
                (true, state.rle_data.data, DecoderMuxState {
                    rle_data_valid: false,
                    ..state})
            } else if (state.compressed_data_valid &&
                      (state.compressed_data.id < std::umin(raw_id, rle_id))) {
                (true, state.compressed_data.data, DecoderMuxState {
                    compressed_data_valid: false,
                    ..state})
            } else {
                (false, bits[DATA_WIDTH]:0, state)
            }
        };

        let tok = send_if(tok, output_s, do_send, data_to_send);
        if (do_send) {
            trace_fmt!("sent {:#x}", data_to_send);
        } else {()};
        state
    }
}

#[test_proc]
proc DecoderMuxTest {
  terminator: chan<bool> out;
  raw_s: chan<BlockDataPacket> out;
  rle_s: chan<BlockDataPacket> out;
  cmp_s: chan<BlockDataPacket> out;
  output_r: chan<bits[DATA_WIDTH]> in;

  init {}

  config (terminator: chan<bool> out) {
    let (raw_s, raw_r) = chan<BlockDataPacket>;
    let (rle_s, rle_r) = chan<BlockDataPacket>;
    let (cmp_s, cmp_r) = chan<BlockDataPacket>;
    let (output_s, output_r) = chan<bits[DATA_WIDTH]>;

    spawn DecoderMux(raw_r, rle_r, cmp_r, output_s);
    (terminator, raw_s, rle_s, cmp_s, output_r)
  }

  next(tok: token, state: ()) {
    let tok = send(tok, raw_s, BlockDataPacket { id: u32:1, last: bool: false, last_block: bool: false, data: bits[DATA_WIDTH]:0x11111111, length: u32:32 });
    let tok = send(tok, raw_s, BlockDataPacket { id: u32:1, last: bool: false, last_block: bool: false, data: bits[DATA_WIDTH]:0x22222222, length: u32:32 });
    let tok = send(tok, rle_s, BlockDataPacket { id: u32:2, last: bool: false, last_block: bool: false, data: bits[DATA_WIDTH]:0xAAAAAAAA, length: u32:32 });
    let tok = send(tok, raw_s, BlockDataPacket { id: u32:1, last: bool: true,  last_block: bool: false, data: bits[DATA_WIDTH]:0x33333333, length: u32:32 });
    let tok = send(tok, cmp_s, BlockDataPacket { id: u32:3, last: bool: false, last_block: bool: false, data: bits[DATA_WIDTH]:0x00000000, length: u32:32 });
    let tok = send(tok, rle_s, BlockDataPacket { id: u32:2, last: bool: true,  last_block: bool: true,  data: bits[DATA_WIDTH]:0xBBBBBBBB, length: u32:32 });

    let (tok, data) = recv(tok, output_r); assert_eq(data, bits[DATA_WIDTH]:0x11111111);
    let (tok, data) = recv(tok, output_r); assert_eq(data, bits[DATA_WIDTH]:0x22222222);
    let (tok, data) = recv(tok, output_r); assert_eq(data, bits[DATA_WIDTH]:0x33333333);
    let (tok, data) = recv(tok, output_r); assert_eq(data, bits[DATA_WIDTH]:0xAAAAAAAA);
    let (tok, data) = recv(tok, output_r); assert_eq(data, bits[DATA_WIDTH]:0xBBBBBBBB);
    let (tok, data) = recv(tok, output_r); assert_eq(data, bits[DATA_WIDTH]:0x00000000);

    send(tok, terminator, true);
  }
}
