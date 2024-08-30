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

import std;
import xls.modules.rle.rle_common as rle_common;


// structure to preserve the state of an RLE decoder
struct RunLengthDecoderAdvState<SYMBOL_WIDTH: u32, COUNT_WIDTH: u32> {
    // symbol to be repeated on output
    symbol: bits[SYMBOL_WIDTH],
    // count of symbols that has to be send
    count: bits[COUNT_WIDTH],
    // send last when repeat ends
    last: bool,
}

// RLE decoder implementation
pub proc RunLengthDecoderAdv<SYMBOL_WIDTH: u32, COUNT_WIDTH: u32, OUTPUT_WIDTH: u32> {
    // FIXME: replace with proc param SYMBOL_WIDTH, COUNT_WIDTH (https://github.com/google/xls/issues/1368)
    type DecInData  = rle_common::CompressedData<u32:8, u32:21>;
    // FIXME: replace with proc param OUTPUT_WIDTH (https://github.com/google/xls/issues/1368)
    type DecOutData = rle_common::PlainDataWithLen<u32:64, u32:7>;

    type State = RunLengthDecoderAdvState<SYMBOL_WIDTH, COUNT_WIDTH>;

    input_r: chan<DecInData> in;
    output_s: chan<DecOutData> out;

    config (
        input_r: chan<DecInData> in,
        output_s: chan<DecOutData> out,
    ) {(input_r, output_s)}

    init {(
        State {
            symbol: bits[SYMBOL_WIDTH]:0,
            count:  bits[COUNT_WIDTH]:0,
            last:   bool:false,
        }
    )}

    next (state: State) {
        const MAX_OUTPUT_SYMBOLS = (OUTPUT_WIDTH / SYMBOL_WIDTH) as uN[COUNT_WIDTH];
        const OUTPUT_WIDTH_LOG2 = std::clog2(OUTPUT_WIDTH + u32:1);

        let state_input = DecInData {
            symbol: state.symbol,
            count: state.count,
            last: state.last
        };

        // receive encoded symbol
        let recv_next_symbol = (state.count == bits[COUNT_WIDTH]:0);
        let (tok, input) = recv_if(join(), input_r, recv_next_symbol, state_input);

        // limit symbols to send
        let symbols_to_send = if (input.count > MAX_OUTPUT_SYMBOLS) {
            MAX_OUTPUT_SYMBOLS
        } else {
            input.count
        };

        let next_count = if input.count == bits[COUNT_WIDTH]:0 {
            fail!("invalid_count_0", input.count)
        } else {
            input.count - symbols_to_send
        };
        let done_sending = (next_count == bits[COUNT_WIDTH]:0);
        let send_last = input.last && done_sending;

        // concatenate symbols to max output width
        let output_symbols = for (i, output_symbols): (u32, uN[OUTPUT_WIDTH]) in range(u32:0, MAX_OUTPUT_SYMBOLS as u32) {
            bit_slice_update(output_symbols, i * SYMBOL_WIDTH, input.symbol)
        }(uN[OUTPUT_WIDTH]:0);

        // shift symbols
        let output_symbols = output_symbols & (!uN[OUTPUT_WIDTH]:0 >> ((MAX_OUTPUT_SYMBOLS - symbols_to_send) << u32:3));

        // send decoded symbol
        let data_out = DecOutData {
            symbols: output_symbols,
            length: symbols_to_send as uN[OUTPUT_WIDTH_LOG2],
            last: send_last
        };
        let data_tok = send(tok, output_s, data_out);

        trace_fmt!("Sent RLE decoded data {:#x}", data_out);

        if (send_last) {
            zero!<State>()
        } else {
            State {
                symbol: input.symbol,
                count: next_count,
                last: input.last,
            }
        }
    }
}

const INST_SYMBOL_WIDTH = u32:8;
const INST_COUNT_WIDTH = u32:21;
const INST_OUTPUT_WIDTH = u32:64;
const INST_OUTPUT_WIDTH_LOG2 = std::clog2(INST_OUTPUT_WIDTH + u32:1);

pub proc RunLengthDecoderAdvInst {
    type InstDecInData  = rle_common::CompressedData<INST_SYMBOL_WIDTH, INST_COUNT_WIDTH>;
    type InstDecOutData = rle_common::PlainDataWithLen<INST_OUTPUT_WIDTH, INST_OUTPUT_WIDTH_LOG2>;

    config (
        input_r: chan<InstDecInData> in,
        output_s: chan<InstDecOutData> out,
    ) {
        spawn RunLengthDecoderAdv<INST_SYMBOL_WIDTH, INST_COUNT_WIDTH, INST_OUTPUT_WIDTH>(
            input_r, output_s
        );
    }

    init { }

    next (state: ()) { }
}

const TEST_SYMBOL_WIDTH = u32:8;
const TEST_COUNT_WIDTH = u32:21;
const TEST_OUTPUT_WIDTH = u32:64;
const TEST_OUTPUT_WIDTH_LOG2 = std::clog2(TEST_OUTPUT_WIDTH + u32:1);

type TestDecInData  = rle_common::CompressedData<TEST_SYMBOL_WIDTH, TEST_COUNT_WIDTH>;
type TestDecOutData = rle_common::PlainDataWithLen<TEST_OUTPUT_WIDTH, TEST_OUTPUT_WIDTH_LOG2>;

const TEST_INPUT_DATA = TestDecInData[8]:[
    TestDecInData {symbol: uN[TEST_SYMBOL_WIDTH]:0x01, count: uN[TEST_COUNT_WIDTH]:10, last: false},
    TestDecInData {symbol: uN[TEST_SYMBOL_WIDTH]:0x23, count: uN[TEST_COUNT_WIDTH]:1, last: false},
    TestDecInData {symbol: uN[TEST_SYMBOL_WIDTH]:0x45, count: uN[TEST_COUNT_WIDTH]:20, last: false},
    TestDecInData {symbol: uN[TEST_SYMBOL_WIDTH]:0x67, count: uN[TEST_COUNT_WIDTH]:7, last: false},
    TestDecInData {symbol: uN[TEST_SYMBOL_WIDTH]:0x89, count: uN[TEST_COUNT_WIDTH]:32, last: true},
    TestDecInData {symbol: uN[TEST_SYMBOL_WIDTH]:0xAB, count: uN[TEST_COUNT_WIDTH]:8, last: false},
    TestDecInData {symbol: uN[TEST_SYMBOL_WIDTH]:0xCD, count: uN[TEST_COUNT_WIDTH]:5, last: false},
    TestDecInData {symbol: uN[TEST_SYMBOL_WIDTH]:0xEF, count: uN[TEST_COUNT_WIDTH]:12, last: true},
];

const TEST_OUTPUT_DATA = TestDecOutData[15]:[
    TestDecOutData {symbols: uN[TEST_OUTPUT_WIDTH]:0x0101_0101_0101_0101, length: uN[TEST_OUTPUT_WIDTH_LOG2]:8, last: false},
    TestDecOutData {symbols: uN[TEST_OUTPUT_WIDTH]:0x0000_0000_0000_0101, length: uN[TEST_OUTPUT_WIDTH_LOG2]:2, last: false},
    TestDecOutData {symbols: uN[TEST_OUTPUT_WIDTH]:0x0000_0000_0000_0023, length: uN[TEST_OUTPUT_WIDTH_LOG2]:1, last: false},
    TestDecOutData {symbols: uN[TEST_OUTPUT_WIDTH]:0x4545_4545_4545_4545, length: uN[TEST_OUTPUT_WIDTH_LOG2]:8, last: false},
    TestDecOutData {symbols: uN[TEST_OUTPUT_WIDTH]:0x4545_4545_4545_4545, length: uN[TEST_OUTPUT_WIDTH_LOG2]:8, last: false},
    TestDecOutData {symbols: uN[TEST_OUTPUT_WIDTH]:0x0000_0000_4545_4545, length: uN[TEST_OUTPUT_WIDTH_LOG2]:4, last: false},
    TestDecOutData {symbols: uN[TEST_OUTPUT_WIDTH]:0x0067_6767_6767_6767, length: uN[TEST_OUTPUT_WIDTH_LOG2]:7, last: false},
    TestDecOutData {symbols: uN[TEST_OUTPUT_WIDTH]:0x8989_8989_8989_8989, length: uN[TEST_OUTPUT_WIDTH_LOG2]:8, last: false},
    TestDecOutData {symbols: uN[TEST_OUTPUT_WIDTH]:0x8989_8989_8989_8989, length: uN[TEST_OUTPUT_WIDTH_LOG2]:8, last: false},
    TestDecOutData {symbols: uN[TEST_OUTPUT_WIDTH]:0x8989_8989_8989_8989, length: uN[TEST_OUTPUT_WIDTH_LOG2]:8, last: false},
    TestDecOutData {symbols: uN[TEST_OUTPUT_WIDTH]:0x8989_8989_8989_8989, length: uN[TEST_OUTPUT_WIDTH_LOG2]:8, last: true},
    TestDecOutData {symbols: uN[TEST_OUTPUT_WIDTH]:0xABAB_ABAB_ABAB_ABAB, length: uN[TEST_OUTPUT_WIDTH_LOG2]:8, last: false},
    TestDecOutData {symbols: uN[TEST_OUTPUT_WIDTH]:0x0000_00CD_CDCD_CDCD, length: uN[TEST_OUTPUT_WIDTH_LOG2]:5, last: false},
    TestDecOutData {symbols: uN[TEST_OUTPUT_WIDTH]:0xEFEF_EFEF_EFEF_EFEF, length: uN[TEST_OUTPUT_WIDTH_LOG2]:8, last: false},
    TestDecOutData {symbols: uN[TEST_OUTPUT_WIDTH]:0x0000_0000_EFEF_EFEF, length: uN[TEST_OUTPUT_WIDTH_LOG2]:4, last: true},
];

#[test_proc]
proc RunLengthDecoderAdv_test {
    terminator: chan<bool> out;

    input_s: chan<TestDecInData> out;
    output_r: chan<TestDecOutData> in;

    config (terminator: chan<bool> out) {
        let (input_s, input_r) = chan<TestDecInData>("input");
        let (output_s, output_r) = chan<TestDecOutData>("output");

        spawn RunLengthDecoderAdv<TEST_SYMBOL_WIDTH, TEST_COUNT_WIDTH, TEST_OUTPUT_WIDTH>(
            input_r, output_s
        );
        
        (terminator, input_s, output_r)
    }

    init { }

    next (state: ()) {
        let tok = join();

        let tok = for ((i, test_input_data), tok): ((u32, TestDecInData), token) in enumerate(TEST_INPUT_DATA) {
            let tok = send(tok, input_s, test_input_data);
            trace_fmt!("Sent #{} input {:#x}", i + u32:1, test_input_data);
            tok
        }(tok);

        let tok = for ((i, test_output_data), tok): ((u32, TestDecOutData), token) in enumerate(TEST_OUTPUT_DATA) {
            let (tok, output_data) = recv(tok, output_r);
            trace_fmt!("Received #{} input {:#x}", i + u32:1, output_data);
            assert_eq(test_output_data, output_data);
            tok
        }(tok);

        send(tok, terminator, true);
    }
}
