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

// This file contains implementation of a Buffer structure that acts as
// a simple FIFO. Additionally, the file provides various functions that
// can simplify access to the stored.
//
// The utility functions containing the `_checked` suffix serve two purposes:
// they perform the actual operation and return information on whether
// the operation was successful. If you are sure that the precondition is
// always true, you can use the function with the same name but without
// the `_checked` suffix.

import std

// Structure to hold the buffered data
pub struct Buffer<CAPACITY: u32> {
    content: bits[CAPACITY],
    length: u32
}

// Status values reported by the functions operating on a Buffer
pub enum BufferStatus : u2 {
    OK = 0,
    NO_ENOUGH_SPACE = 1,
    NO_ENOUGH_DATA = 2,
}

// Structure for returning Buffer and BufferStatus together
pub struct BufferResult<CAPACITY: u32> {
    buffer: Buffer<CAPACITY>,
    status: BufferStatus
}

// Checks whether a `buffer` has at least `length` amount of data
pub fn buffer_has_at_least<CAPACITY: u32>(buffer: Buffer<CAPACITY>, length: u32) -> bool {
    length <= buffer.length
}

#[test]
fn test_buffer_has_at_least() {
    let buffer = Buffer { content: u32:0, length: u32:0 };
    assert_eq(buffer_has_at_least(buffer, u32:0), true);
    assert_eq(buffer_has_at_least(buffer, u32:16), false);
    assert_eq(buffer_has_at_least(buffer, u32:32), false);
    assert_eq(buffer_has_at_least(buffer, u32:33), false);

    let buffer = Buffer { content: u32:0, length: u32:16 };
    assert_eq(buffer_has_at_least(buffer, u32:0), true);
    assert_eq(buffer_has_at_least(buffer, u32:16), true);
    assert_eq(buffer_has_at_least(buffer, u32:32), false);
    assert_eq(buffer_has_at_least(buffer, u32:33), false);

    let buffer = Buffer { content: u32:0, length: u32:32 };
    assert_eq(buffer_has_at_least(buffer, u32:0), true);
    assert_eq(buffer_has_at_least(buffer, u32:16), true);
    assert_eq(buffer_has_at_least(buffer, u32:32), true);
    assert_eq(buffer_has_at_least(buffer, u32:33), false);
}

// Returns `length` amount of data from a `buffer` and a new buffer with
// the data removed. Since the Buffer structure acts as a simple FIFO,
// it pops the data in the same order as they were added to the buffer.
// If the buffer does not have enough data to meet the specified length,
// the function will fail. For calls that need better error handling,
// check `buffer_pop_checked`.
pub fn buffer_pop<CAPACITY: u32>(buffer: Buffer<CAPACITY>, length: u32) -> (Buffer<CAPACITY>, bits[CAPACITY]) {
    if buffer_has_at_least(buffer, length) == false {
        trace_fmt!("Not enough data in the buffer!");
        fail!("not_enough_data", (buffer, bits[CAPACITY]:0))
    } else {
        let mask = (bits[CAPACITY]:1 << length) - bits[CAPACITY]:1;
        (
            Buffer {
                content: buffer.content >> length,
                length: buffer.length - length
            },
            buffer.content & mask
        )
    }
}

#[test]
fn test_buffer_pop() {
    let buffer = Buffer { content: u32:0xDEADBEEF, length: u32:32 };
    let (buffer, data) = buffer_pop(buffer, u32:16);
    assert_eq(data, u32:0xBEEF);
    assert_eq(buffer, Buffer { content: u32:0xDEAD, length: u32:16 });
    let (buffer, data) = buffer_pop(buffer, u32:16);
    assert_eq(data, u32:0xDEAD);
    assert_eq(buffer, Buffer { content: u32:0, length: u32:0 });
}

pub fn buffer128_pop32(buffer: Buffer<128>) -> (Buffer<128>, bits[128]) {
    buffer_pop(buffer, u32:32)
}

// Behaves like `buffer_pop` except that the length of the popped data can be
// set using a DSIZE function parameter. For calls that need better error
// handling, check `buffer_fixed_pop_checked`.
pub fn buffer_fixed_pop<CAPACITY: u32, DSIZE: u32> (buffer: Buffer<CAPACITY>) -> (Buffer<CAPACITY>, bits[DSIZE]) {
    if buffer_has_at_least(buffer, DSIZE) == false {
        trace_fmt!("Not enough data in the buffer!");
        fail!("not_enough_data", (buffer, bits[DSIZE]:0))
    } else {
        (
            Buffer {
                content: buffer.content >> DSIZE,
                length: buffer.length - DSIZE
            },
            buffer.content[0:DSIZE as s32] as bits[DSIZE]
        )
    }
}

#[test]
fn test_buffer_fixed_pop() {
    let buffer = Buffer { content: u32:0xDEADBEEF, length: u32:32 };
    let (buffer, data) = buffer_fixed_pop<u32:32, u32:16>(buffer);
    assert_eq(data, u16:0xBEEF);
    assert_eq(buffer, Buffer { content: u32:0xDEAD, length: u32:16 });
    let (buffer, data) = buffer_fixed_pop<u32:32, u32:16>(buffer);
    assert_eq(data, u16:0xDEAD);
    assert_eq(buffer, Buffer { content: u32:0, length: u32:0 });
}

pub fn buffer128_pop32_fixed(buffer: Buffer<128>) -> (Buffer<128>, bits[32]) {
    buffer_fixed_pop<u32:128, u32:32>(buffer)
}
