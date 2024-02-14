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

// This file contains implementation of a Buffer structure that acts as
// a simple FIFO. Additionally, the file provides various functions that
// can simplify access to the stored.
//
// The utility functions containing the `_checked` suffix serve two purposes:
// they perform the actual operation and return information on whether
// the operation was successful. If you are sure that the precondition is
// always true, you can use the function with the same name but without
// the `_checked` suffix.

import std;
import xls.modules.zstd.buffer as buff;

type Buffer = buff::Buffer;

// WindowBuffer is a simple Proc that uses the Buffer structure to aggregate data
// in transactions of <INPUT_WIDTH> length and output it in transactions of
// <OUTPUT_WIDTH> length. <BUFFER_SIZE> defines the maximal size of the buffer.

proc WindowBuffer<BUFFER_SIZE: u32, INPUT_WIDTH: u32, OUTPUT_WIDTH: u32> {
    input_r: chan<uN[INPUT_WIDTH]> in;
    output_s: chan<uN[OUTPUT_WIDTH]> out;

    config(
        input_r: chan<uN[INPUT_WIDTH]> in,
        output_s: chan<uN[OUTPUT_WIDTH]> out
    ) { (input_r, output_s) }

    init { buff::buffer_new<BUFFER_SIZE>() }

    next(tok: token, buffer: Buffer<BUFFER_SIZE>) {
        let (tok, recv_data) = recv(tok, input_r);
        let buffer = buff::buffer_append<BUFFER_SIZE>(buffer, recv_data);

        if buffer.length >= OUTPUT_WIDTH {
            let (buffer, data_to_send) = buff::buffer_fixed_pop<BUFFER_SIZE, OUTPUT_WIDTH>(buffer);
            let tok = send(tok, output_s, data_to_send);
            buffer
        } else {
            buffer
        }
    }
}

#[test_proc]
proc WindowBufferTest {
    terminator: chan<bool> out;
    data32_s: chan<u32> out;
    data48_r: chan<u48> in;

    config(terminator: chan<bool> out) {
        let (data32_s, data32_r) = chan<u32>;
        let (data48_s, data48_r) = chan<u48>;
        spawn WindowBuffer<u32:64, u32:32, u32:48>(data32_r, data48_s);
        (terminator, data32_s, data48_r)
    }

    init {}

    next(tok: token, state: ()) {
        let tok = send(tok, data32_s, u32:0xDEADBEEF);
        let tok = send(tok, data32_s, u32:0xBEEFCAFE);
        let tok = send(tok, data32_s, u32:0xCAFEDEAD);

        let (tok, received_data) = recv(tok, data48_r);
        assert_eq(received_data, u48:0xCAFE_DEAD_BEEF);
        let (tok, received_data) = recv(tok, data48_r);
        assert_eq(received_data, u48:0xCAFE_DEAD_BEEF);

        send(tok, terminator, true);
    }
}

// Sample for codegen
proc WindowBuffer64 {
    input_r: chan<u32> in;
    output_s: chan<u48> out;

    config(
        input_r: chan<u32> in,
        output_s: chan<u48> out
    ) {
        spawn WindowBuffer<u32:64, u32:32, u32:48>(input_r, output_s);
        (input_r, output_s)
    }

    init {}

    next(tok: token, state: ()) {}
}
