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
import xls.modules.shift_buffer.fixme;
import xls.modules.shift_buffer.math;

pub enum ShiftBufferStatus : u1 {
    OK = 0,
    ERROR = 1,
}

pub fn length_width(data_width: u32) -> u32 {
    std::clog2(data_width + u32:1)
}

// Common definition for buffer input and output payload
pub struct ShiftBufferPacket<DATA_WIDTH: u32, LENGTH_WIDTH: u32> {
    data: uN[DATA_WIDTH],
    length: uN[LENGTH_WIDTH],
    last: bool,
}

// Output structure - packet with embedded status of the buffer operation
pub struct ShiftBufferOutput<DATA_WIDTH: u32, LENGTH_WIDTH: u32> {
    payload: ShiftBufferPacket<DATA_WIDTH, LENGTH_WIDTH>,
    status: ShiftBufferStatus,
}

// Buffer pop command
pub struct ShiftBufferCtrl<LENGTH_WIDTH: u32> {
    length: uN[LENGTH_WIDTH]
}

struct ShiftBufferAlignerState<LENGTH_WIDTH: u32> {
    ptr: uN[LENGTH_WIDTH]
}

proc ShiftBufferAligner<
    DATA_WIDTH: u32,
    LENGTH_WIDTH: u32 = {length_width(DATA_WIDTH)},
    DATA_WIDTH_X2: u32 = {DATA_WIDTH * u32:2},
> {
    type Length = uN[LENGTH_WIDTH];
    type Data = uN[DATA_WIDTH];
    type DataX2 = uN[DATA_WIDTH_X2];

    type State = ShiftBufferAlignerState<LENGTH_WIDTH>;
    type Input = ShiftBufferPacket<DATA_WIDTH, LENGTH_WIDTH>;
    type Inter = ShiftBufferPacket<DATA_WIDTH_X2, LENGTH_WIDTH>;

    input_r: chan<Input> in;
    inter_s: chan<Inter> out;

    config(input_r: chan<Input> in, inter_s: chan<Inter> out) { (input_r, inter_s) }

    init {zero!<State>()}

    next(state: State) {
        // FIXME: Remove when https://github.com/google/xls/issues/1368 is resolved
        type Inter = ShiftBufferPacket<DATA_WIDTH_X2, LENGTH_WIDTH>;

        let (tok, data) = recv(join(), input_r);
        let tok = send(tok, inter_s, Inter {
            length: data.length,
            data: math::logshiftl(data.data as DataX2, state.ptr),
            last: data.last
        });

        State {ptr: (state.ptr + data.length) % (DATA_WIDTH as Length) }
    }
}

const ALIGNER_TEST_DATA_WIDTH = u32:64;
const ALIGNER_TEST_LENGTH_WIDTH = length_width(ALIGNER_TEST_DATA_WIDTH);
const ALIGNER_TEST_DATA_WIDTH_X2 = ALIGNER_TEST_DATA_WIDTH * u32:2;

#[test_proc]
proc ShiftBufferAlignerTest {
    terminator: chan<bool> out;
    type Input = ShiftBufferPacket<ALIGNER_TEST_DATA_WIDTH, ALIGNER_TEST_LENGTH_WIDTH>;
    type Inter = ShiftBufferPacket<ALIGNER_TEST_DATA_WIDTH_X2, ALIGNER_TEST_LENGTH_WIDTH>;

    type Data = uN[ALIGNER_TEST_DATA_WIDTH];
    type Length = uN[ALIGNER_TEST_LENGTH_WIDTH];
    type DataX2 = uN[ALIGNER_TEST_DATA_WIDTH_X2];

    input_s: chan<Input> out;
    inter_r: chan<Inter> in;

    config(terminator: chan<bool> out) {
        let (input_s, input_r) = chan<Input>("input");
        let (inter_s, inter_r) = chan<Inter>("inter");

        spawn ShiftBufferAligner<ALIGNER_TEST_DATA_WIDTH>(input_r, inter_s);

        (terminator, input_s, inter_r)
    }

    init {  }

    next(state: ()) {
        let tok = send(join(), input_s, Input { data: Data:0xAABB_CCDD, length: Length:32, last: false});
        let tok = send(tok, input_s, Input { data: Data:0x1122, length: Length:16, last: false});
        let tok = send(tok, input_s, Input { data: Data:0x33, length: Length:8, last: false});
        let tok = send(tok, input_s, Input { data: Data:0x44, length: Length:8, last: false});
        let tok = send(tok, input_s, Input { data: Data:0xFFFF, length: Length:4, last: false});
        let tok = send(tok, input_s, Input { data: Data:0x0, length: Length:0, last: false});
        let tok = send(tok, input_s, Input { data: Data:0x0, length: Length:4, last: false});
        let tok = send(tok, input_s, Input { data: Data:0x1, length: Length:1, last: false});
        let tok = send(tok, input_s, Input { data: Data:0xF, length: Length:3, last: false});
        let tok = send(tok, input_s, Input { data: Data:0xF, length: Length:4, last: false});

        let (tok, data) = recv(tok, inter_r);
        assert_eq(data, Inter { data: DataX2: 0xAABB_CCDD, length: Length: 32, last: false});
        let (tok, data) = recv(tok, inter_r);
        assert_eq(data, Inter { data: DataX2: 0x1122_0000_0000, length: Length: 16, last: false});
        let (tok, data) = recv(tok, inter_r);
        assert_eq(data, Inter { data: DataX2: 0x33_0000_0000_0000, length: Length: 8, last: false});
        let (tok, data) = recv(tok, inter_r);
        assert_eq(data, Inter { data: DataX2: 0x4400_0000_0000_0000, length: Length: 8, last: false});
        let (tok, data) = recv(tok, inter_r);
        assert_eq(data, Inter { data: DataX2:0xFFFF, length: Length:4, last: false});
        let (tok, data) = recv(tok, inter_r);
        assert_eq(data, Inter { data: DataX2:0x0, length: Length:0, last: false});
        let (tok, data) = recv(tok, inter_r);
        assert_eq(data, Inter { data: DataX2:0x00, length: Length:4, last: false});
        let (tok, data) = recv(tok, inter_r);
        assert_eq(data, Inter { data: DataX2:0x100, length: Length:1, last: false});
        let (tok, data) = recv(tok, inter_r);
        assert_eq(data, Inter { data: DataX2:0x1E00, length: Length:3, last: false});
        let (tok, data) = recv(tok, inter_r);
        assert_eq(data, Inter { data: DataX2:0xF000, length: Length:4, last: false});

        send(tok, terminator, true);
    }
}

struct ShiftBufferStorageState<BUFFER_WIDTH: u32, LENGTH_WIDTH: u32> {
    buffer: bits[BUFFER_WIDTH],  // The storage element.
    buffer_cnt: bits[LENGTH_WIDTH + u32:2],  // Number of valid bits in the buffer.
    read_ptr: bits[LENGTH_WIDTH + u32:2],  // First occupied bit in the buffer when buffer_cnt > 0.
    write_ptr: bits[LENGTH_WIDTH + u32:2],  // First free bit in the buffer.
    last: bool,  // Received last value from shift proc.
    cmd: ShiftBufferCtrl<LENGTH_WIDTH>,  // Received command of ShiftBufferCtrl type.
    cmd_valid: bool,  // Field cmd is valid.
    status: ShiftBufferStatus,
}

proc ShiftBufferStorage<DATA_WIDTH: u32, LENGTH_WIDTH: u32> {
    type Buffer = bits[DATA_WIDTH * u32:3];
    type BufferLength = bits[LENGTH_WIDTH + u32:2];
    type Data = bits[DATA_WIDTH];
    type DataLength = bits[LENGTH_WIDTH];
    type State = ShiftBufferStorageState;
    type Ctrl = ShiftBufferCtrl;
    type Inter = ShiftBufferPacket;
    type Output = ShiftBufferOutput;
    ctrl: chan<Ctrl<LENGTH_WIDTH>> in;
    inter: chan<Inter<{DATA_WIDTH * u32:2}, LENGTH_WIDTH>> in;
    output: chan<Output<DATA_WIDTH, LENGTH_WIDTH>> out;

    config(ctrl: chan<Ctrl<LENGTH_WIDTH>> in,
           inter: chan<Inter<{DATA_WIDTH * u32:2}, LENGTH_WIDTH>> in,
           output: chan<Output<DATA_WIDTH, LENGTH_WIDTH>> out) {
        (ctrl, inter, output)
    }

    init {
        type State = ShiftBufferStorageState<{DATA_WIDTH * u32:3}, LENGTH_WIDTH>;
        zero!<State>()
    }

    next(state: State<{DATA_WIDTH * u32:3}, LENGTH_WIDTH>) {
        type State = ShiftBufferStorageState<{DATA_WIDTH * u32:3}, LENGTH_WIDTH>;
        type Ctrl = ShiftBufferCtrl<LENGTH_WIDTH>;
        type Inter = ShiftBufferPacket<{DATA_WIDTH * u32:2}, LENGTH_WIDTH>;
        type Output = ShiftBufferOutput<DATA_WIDTH, LENGTH_WIDTH>;
        type OutputPayload = ShiftBufferPacket<DATA_WIDTH, LENGTH_WIDTH>;
        type OutputStatus = ShiftBufferStatus;
        type DataLength = bits[LENGTH_WIDTH];
trace_fmt!("state: {:#x}", state);

        const MAX_BUFFER_CNT = (DATA_WIDTH * u32:3) as BufferLength;

        let status = if (state.last && state.cmd_valid && state.cmd.length as BufferLength > state.buffer_cnt || state.status == OutputStatus::ERROR) {
            OutputStatus::ERROR
        } else {
            OutputStatus::OK
        };
        let new_state = match state.status {
            OutputStatus::OK => {
                let shift_buffer_right = state.read_ptr >= (DATA_WIDTH as BufferLength);
                trace_fmt!("shift_buffer_right: {:#x}", shift_buffer_right);
                let shift_data_left =
                    state.write_ptr >= (DATA_WIDTH as BufferLength) && !shift_buffer_right;
                trace_fmt!("shift_data_left: {:#x}", shift_data_left);
                let recv_new_input = !state.last && state.write_ptr < (DATA_WIDTH * u32:2) as BufferLength;
                trace_fmt!("recv_new_input: {:#x}", recv_new_input);
                let recv_new_data = (state.cmd.length as BufferLength <= state.buffer_cnt);
                let send_response = state.cmd_valid && recv_new_data || (state.last && state.cmd_valid);
                trace_fmt!("send_response: {:#x}", send_response);
                let recv_new_cmd = !state.cmd_valid || send_response && (status != OutputStatus::ERROR);
                trace_fmt!("recv_new_cmd: {:#x}", recv_new_cmd);

                let tok = join();

                // Shift buffer if required
                let (new_buffer, new_read_ptr, new_write_ptr) = fixme::fast_if_tuple_3(shift_buffer_right,
                    {
                        (state.buffer >> DATA_WIDTH,
                        state.read_ptr - DATA_WIDTH as BufferLength,
                        state.write_ptr - DATA_WIDTH as BufferLength)
                    }, {
                        (state.buffer,
                        state.read_ptr,
                        state.write_ptr)
                    }
                );

                if (shift_buffer_right) {
                    trace_fmt!("Shifted data");
                    trace_fmt!("new_buffer: {:#x}", new_buffer);
                    trace_fmt!("new_read_ptr: {}", new_read_ptr);
                    trace_fmt!("new_write_ptr: {}", new_write_ptr);
                } else { () };

                // Handle incoming writes
                let (tok_input, wdata, wdata_valid) = recv_if_non_blocking(tok, inter, recv_new_input, zero!<Inter>());

                let (new_buffer, new_write_ptr, new_last) = fixme::fast_if_tuple_3(wdata_valid,
                    {
                        // Shift data if required
                        let new_data = fixme::fast_if(shift_data_left,
                            {
                                wdata.data as Buffer << DATA_WIDTH
                            }, {
                                wdata.data as Buffer
                            }
                        );
                        let new_buffer = new_buffer | new_data;
                        let new_write_ptr = new_write_ptr + wdata.length as BufferLength;
                        let new_last = wdata.last;

                        (new_buffer, new_write_ptr, new_last)
                    }, {
                        (new_buffer, new_write_ptr, state.last)
                    }
                );

                if (wdata_valid) {
                    trace_fmt!("Received aligned data {:#x}", wdata);
                    trace_fmt!("new_buffer: {:#x}", new_buffer);
                    trace_fmt!("new_write_ptr: {}", new_write_ptr);
                    trace_fmt!("new_last: {:#x}", new_last);
                } else { () };

                // Handle incoming reads
                let (tok_ctrl, new_cmd, new_cmd_valid) =
                    recv_if_non_blocking(tok, ctrl, recv_new_cmd, state.cmd);

                if (new_cmd_valid) {
                    trace_fmt!("Received new cmd: {}", new_cmd);
                } else {()};
                let new_cmd_valid = if recv_new_cmd { new_cmd_valid } else { state.cmd_valid };

                // Handle current read
                let (rdata, new_read_ptr) = if send_response {
                    let new_read_ptr = new_read_ptr + state.cmd.length as BufferLength;
                    let rdata = if (status == OutputStatus::ERROR) {
                        Output {
                            payload: OutputPayload {
                                length: DataLength:0,
                                data: Data:0,
                                last: false,
                            },
                            status: status
                        }
                    } else {
                        Output {
                            payload: OutputPayload {
                                length: state.cmd.length,
                                data: math::mask(math::logshiftr(state.buffer, state.read_ptr) as Data, state.cmd.length),
                                last: state.last && state.cmd.length as BufferLength == state.buffer_cnt,
                            },
                            status: OutputStatus::OK,
                        }
                    };

                    trace_fmt!("rdata: {:#x}", rdata);
                    trace_fmt!("new_read_ptr: {}", new_read_ptr);

                    (rdata, new_read_ptr)
                } else {
                    (Output { payload: zero!<OutputPayload>(), status: status }, new_read_ptr)
                };

                let tok = join(tok_input, tok_ctrl);
                send_if(tok, output, send_response, rdata);
                if (send_response) {
                    trace_fmt!("Sent out rdata: {:#x}", rdata);
                } else {()};

                let new_buffer_cnt = new_write_ptr - new_read_ptr;
                let new_last = new_last && new_buffer_cnt != BufferLength:0;

                let new_state = State {
                    buffer: new_buffer,
                    buffer_cnt: new_buffer_cnt,
                    read_ptr: new_read_ptr,
                    write_ptr: new_write_ptr,
                    last: new_last,
                    cmd: new_cmd,
                    cmd_valid: new_cmd_valid,
                    status: rdata.status
                };
                new_state
            },
            OutputStatus::ERROR =>
                State {status: status, ..state},
            _ => state
        };

        new_state
    }
}

const STORAGE_TEST_DATA_WIDTH = u32:64;
const STORAGE_TEST_LENGTH_WIDTH = length_width(STORAGE_TEST_DATA_WIDTH);
const STORAGE_TEST_DATA_WIDTH_X2 = STORAGE_TEST_DATA_WIDTH * u32:2;

#[test_proc]
proc ShiftBufferStorageTest {
    terminator: chan<bool> out;
    type Ctrl = ShiftBufferCtrl<STORAGE_TEST_LENGTH_WIDTH>;
    type Inter = ShiftBufferPacket<STORAGE_TEST_DATA_WIDTH_X2, STORAGE_TEST_LENGTH_WIDTH>;
    type Output = ShiftBufferOutput<STORAGE_TEST_DATA_WIDTH, STORAGE_TEST_LENGTH_WIDTH>;
    type OutputPayload = ShiftBufferPacket<STORAGE_TEST_DATA_WIDTH, STORAGE_TEST_LENGTH_WIDTH>;
    type OutputStatus = ShiftBufferStatus;

    type Length = uN[STORAGE_TEST_LENGTH_WIDTH];
    type Data = uN[STORAGE_TEST_DATA_WIDTH];
    type DataX2 = uN[STORAGE_TEST_DATA_WIDTH_X2];

    ctrl_s: chan<Ctrl> out;
    inter_s: chan<Inter> out;
    output_r: chan<Output> in;

    config(terminator: chan<bool> out) {
        let (ctrl_s, ctrl_r) = chan<Ctrl>("ctrl");
        let (inter_s, inter_r) = chan<Inter>("inter");
        let (output_s, output_r) = chan<Output>("output");

        spawn ShiftBufferStorage<STORAGE_TEST_DATA_WIDTH, STORAGE_TEST_LENGTH_WIDTH>(ctrl_r, inter_r, output_s);

        (terminator, ctrl_s, inter_s, output_r)
    }

    init {  }

    next(state: ()) {
        // Single input, single output packet 32bit buffering
        let tok = send(join(), inter_s, Inter { data: DataX2: 0xAABB_CCDD, length: Length: 32, last: false});

        // Multiple input packets, single output 32bit buffering
        let tok = send(tok, inter_s, Inter { data: DataX2: 0x3344_0000_0000, length: Length: 16, last: false});
        let tok = send(tok, inter_s, Inter { data: DataX2: 0x22_0000_0000_0000, length: Length: 8, last: false});
        let tok = send(tok, inter_s, Inter { data: DataX2: 0x1100_0000_0000_0000, length: Length: 8, last: false});

        // Small consecutive single input, single output 8bit buffering
        let tok = send(tok, inter_s, Inter { data: DataX2: 0x55, length: Length: 8, last: false});
        let tok = send(tok, inter_s, Inter { data: DataX2: 0x6600, length: Length: 8, last: false});

        // Multiple input packets, single output 64bit buffering
        let tok = send(tok, inter_s, Inter { data: DataX2: 0xDDEE_0000, length: Length: 16, last: false});
        let tok = send(tok, inter_s, Inter { data: DataX2: 0xBBCC_0000_0000, length: Length: 16, last: false});
        let tok = send(tok, inter_s, Inter { data: DataX2: 0x99AA_0000_0000_0000, length: Length: 16, last: false});
        let tok = send(tok, inter_s, Inter { data: DataX2: 0x7788, length: Length: 16, last: false});

        // Single input packet, single output 64bit buffering
        let tok = send(tok, inter_s, Inter { data: DataX2: 0x1122_3344_5566_7788_0000, length: Length: 64, last: false});

        // Single 64bit input packet, multiple output packets of different sizes
        let tok = send(tok, inter_s, Inter { data: DataX2: 0xEEFF_0011_CCDD_BBAA_0000, length: Length: 64, last: false});

        // Consecutive small packet last propagation
        // Account for leftover 0xEEFF from the previous packet
        let tok = send(tok, inter_s, Inter { data: DataX2: 0x1122_0000, length: Length: 16, last: true});
        // Should operate on flushed buffer
        let tok = send(tok, inter_s, Inter { data: DataX2: 0x3344_0000_0000, length: Length: 16, last: true});

        // Multiple input packets with last propagation at the last packet
        // Input packets additionally span across 2 shift buffer aligner shift domains
        let tok = send(tok, inter_s, Inter { data: DataX2: 0x7788_0000_0000_0000, length: Length: 16, last: false});
        let tok = send(tok, inter_s, Inter { data: DataX2: 0x5566, length: Length: 16, last: true});

        // Test flushing buffer before reading next input data packets
        let tok = send(tok, inter_s, Inter { data: DataX2: 0x3344_0000, length: Length: 16, last: false});
        let tok = send(tok, inter_s, Inter { data: DataX2: 0x1122_0000_0000, length: Length: 16, last: true});
        let tok = send(tok, inter_s, Inter { data: DataX2: 0x7788_0000_0000_0000, length: Length: 16, last: false});
        let tok = send(tok, inter_s, Inter { data: DataX2: 0x5566, length: Length: 16, last: false});

        // Single input, single output packet 32bit buffering
        let tok = send(tok, ctrl_s, Ctrl { length: Length:32});
        let (tok, data) = recv(tok, output_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0xAABB_CCDD, length: Length: 32, last: false}, status: OutputStatus::OK});

        // Multiple input packets, single output 32bit buffering
        let tok = send(tok, ctrl_s, Ctrl { length: Length:32});
        let (tok, data) = recv(tok, output_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x1122_3344, length: Length: 32, last: false}, status: OutputStatus::OK});

        // Small consecutive single input, single output 8bit buffering
        let tok = send(tok, ctrl_s, Ctrl { length: Length:8});
        let (tok, data) = recv(tok, output_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x55, length: Length: 8, last: false}, status: OutputStatus::OK});
        let tok = send(tok, ctrl_s, Ctrl { length: Length:8});
        let (tok, data) = recv(tok, output_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x66, length: Length: 8, last: false}, status: OutputStatus::OK});

        // Multiple input packets, single output 64bit buffering
        let tok = send(tok, ctrl_s, Ctrl { length: Length:64});
        let (tok, data) = recv(tok, output_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x7788_99AA_BBCC_DDEE, length: Length: 64, last: false}, status: OutputStatus::OK});

        // Single input packet, single output 64bit buffering
        let tok = send(tok, ctrl_s, Ctrl { length: Length:64});
        let (tok, data) = recv(tok, output_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x1122_3344_5566_7788, length: Length: 64, last: false}, status: OutputStatus::OK});

        // Single 64bit input packet, multiple output packets of different sizes
        let tok = send(tok, ctrl_s, Ctrl { length: Length:8});
        let (tok, data) = recv(tok, output_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0xAA, length: Length: 8, last: false}, status: OutputStatus::OK});
        let tok = send(tok, ctrl_s, Ctrl { length: Length:8});
        let (tok, data) = recv(tok, output_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0xBB, length: Length: 8, last: false}, status: OutputStatus::OK});
        let tok = send(tok, ctrl_s, Ctrl { length: Length:16});
        let (tok, data) = recv(tok, output_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0xCCDD, length: Length: 16, last: false}, status: OutputStatus::OK});
        let tok = send(tok, ctrl_s, Ctrl { length: Length:32});
        let (tok, data) = recv(tok, output_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0xEEFF_0011, length: Length: 32, last: false}, status: OutputStatus::OK});

        // Consecutive small packet last propagation
        let tok = send(tok, ctrl_s, Ctrl { length: Length:16});
        let (tok, data) = recv(tok, output_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x1122, length: Length: 16, last: true}, status: OutputStatus::OK});
        let tok = send(tok, ctrl_s, Ctrl { length: Length:16});
        let (tok, data) = recv(tok, output_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x3344, length: Length: 16, last: true}, status: OutputStatus::OK});

        // Multiple input packets with last propagation at the last packet
        let tok = send(tok, ctrl_s, Ctrl { length: Length:32});
        let (tok, data) = recv(tok, output_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x5566_7788, length: Length: 32, last: true}, status: OutputStatus::OK});

        // Test error handling when attempting to read more data than available in the buffer with last set
        // This triggers error that will cause the buffer to send out a single output packet with
        // the ERROR status. Resuming the operation requires resetting the proc.
        let tok = send(tok, ctrl_s, Ctrl { length: Length:64});
        let (tok, data) = recv(tok, output_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x0, length: Length: 0, last: false}, status: OutputStatus::ERROR});
        // This will spin on recv infinitely due to an error from the previous case
        //let tok = send(tok, ctrl_s, Ctrl { length: Length:32});
        //let (tok, data) = recv(tok, output_r);

        send(tok, terminator, true);
    }
}

proc ShiftBuffer<DATA_WIDTH: u32, LENGTH_WIDTH: u32> {
    type Input = ShiftBufferPacket;
    type Ctrl = ShiftBufferCtrl;
    type Inter = ShiftBufferPacket;
    type Output = ShiftBufferOutput;

    config(ctrl: chan<Ctrl<LENGTH_WIDTH>> in, input: chan<Input<DATA_WIDTH, LENGTH_WIDTH>> in,
           output: chan<Output<DATA_WIDTH, LENGTH_WIDTH>> out) {
        let (inter_out, inter_in) =
            chan<ShiftBufferPacket<{DATA_WIDTH * u32:2}, LENGTH_WIDTH>, u32:1>("inter");
        spawn ShiftBufferAligner<DATA_WIDTH, LENGTH_WIDTH>(input, inter_out);
        spawn ShiftBufferStorage<DATA_WIDTH, LENGTH_WIDTH>(ctrl, inter_in, output);
        ()
    }

    init {  }

    next(state: ()) { }
}

const TEST_DATA_WIDTH = u32:64;
const TEST_LENGTH_WIDTH = std::clog2(TEST_DATA_WIDTH) + u32:1;

#[test_proc]
proc ShiftBufferTest {
    type Input = ShiftBufferPacket;
    type Ctrl = ShiftBufferCtrl;
    type Output = ShiftBufferOutput;

    terminator: chan<bool> out;
    input_s: chan<Input<TEST_DATA_WIDTH, TEST_LENGTH_WIDTH>> out;
    ctrl_s: chan<Ctrl<TEST_LENGTH_WIDTH>> out;
    data_r: chan<Output<TEST_DATA_WIDTH, TEST_LENGTH_WIDTH>> in;

    config(terminator: chan<bool> out) {
        let (input_s, input_r) = chan<Input<TEST_DATA_WIDTH, TEST_LENGTH_WIDTH>, u32:1>("input");
        let (ctrl_s, ctrl_r) = chan<Ctrl<TEST_LENGTH_WIDTH>, u32:1>("ctrl");
        let (data_s, data_r) = chan<Output<TEST_DATA_WIDTH, TEST_LENGTH_WIDTH>, u32:1>("data");

        spawn ShiftBuffer<TEST_DATA_WIDTH, TEST_LENGTH_WIDTH>(ctrl_r, input_r, data_s);

        (terminator, input_s, ctrl_s, data_r)
    }

    init {  }

    next(state: ()) {
        type Data = bits[TEST_DATA_WIDTH];
        type Length = bits[TEST_LENGTH_WIDTH];
        type Input = ShiftBufferPacket;
        type Output = ShiftBufferOutput;
        type OutputPayload = ShiftBufferPacket;
        type OutputStatus = ShiftBufferStatus;
        type Ctrl = ShiftBufferCtrl;

        let tok = send(join(), input_s, Input { data: Data:0xDD_44, length: Length:16, last: false });
        let tok = send(tok, input_s, Input { data: Data:0xAA_11_BB_22_CC_33, length: Length:48, last: false });
        let tok = send(tok, input_s, Input { data: Data:0xEE_55_FF_66_00_77_11_88, length: Length:64, last: false });

        // Single input, single output packet 32bit buffering
        let tok = send(join(), input_s, Input { data: Data: 0xAABB_CCDD, length: Length: 32, last: false});

        // Multiple input packets, single output 32bit buffering
        let tok = send(tok, input_s, Input { data: Data: 0x3344, length: Length: 16, last: false});
        let tok = send(tok, input_s, Input { data: Data: 0x22, length: Length: 8, last: false});
        let tok = send(tok, input_s, Input { data: Data: 0x11, length: Length: 8, last: false});

        // Small consecutive single input, single output 8bit buffering
        let tok = send(tok, input_s, Input { data: Data: 0x55, length: Length: 8, last: false});
        let tok = send(tok, input_s, Input { data: Data: 0x66, length: Length: 8, last: false});

        // Multiple input packets, single output 64bit buffering
        let tok = send(tok, input_s, Input { data: Data: 0xDDEE, length: Length: 16, last: false});
        let tok = send(tok, input_s, Input { data: Data: 0xBBCC, length: Length: 16, last: false});
        let tok = send(tok, input_s, Input { data: Data: 0x99AA, length: Length: 16, last: false});
        let tok = send(tok, input_s, Input { data: Data: 0x7788, length: Length: 16, last: false});

        // Single input packet, single output 64bit buffering
        let tok = send(tok, input_s, Input { data: Data: 0x1122_3344_5566_7788, length: Length: 64, last: false});

        // Single 64bit input packet, multiple output packets of different sizes
        let tok = send(tok, input_s, Input { data: Data: 0xEEFF_0011_CCDD_BBAA, length: Length: 64, last: false});

        // Consecutive small packet last propagation
        // Account for leftover 0xEEFF from the previous packet
        let tok = send(tok, input_s, Input { data: Data: 0x1122, length: Length: 16, last: true});
        // Should operate on flushed buffer
        let tok = send(tok, input_s, Input { data: Data: 0x3344, length: Length: 16, last: true});

        // Multiple input packets with last propagation at the last packet
        // Input packets additionally span across 2 shift buffer aligner shift domains
        let tok = send(tok, input_s, Input { data: Data: 0x7788, length: Length: 16, last: false});
        let tok = send(tok, input_s, Input { data: Data: 0x5566, length: Length: 16, last: true});

        // Test flushing buffer before reading next input data packets
        let tok = send(tok, input_s, Input { data: Data: 0x3344, length: Length: 16, last: false});
        let tok = send(tok, input_s, Input { data: Data: 0x1122, length: Length: 16, last: true});
        let tok = send(tok, input_s, Input { data: Data: 0x7788, length: Length: 16, last: false});
        let tok = send(tok, input_s, Input { data: Data: 0x5566, length: Length: 16, last: false});

        let tok = send(tok, ctrl_s, Ctrl { length: Length:8 });
        let (tok, output) = recv(tok, data_r);
        assert_eq(output, Output { payload: OutputPayload { data: Data:0x44, length: Length:8, last: false }, status: OutputStatus::OK});

        let tok = send(tok, ctrl_s, Ctrl { length: Length:4 });
        let (tok, output) = recv(tok, data_r);
        assert_eq(output, Output { payload: OutputPayload { data: Data:0xD, length: Length:4, last: false }, status: OutputStatus::OK});
        let tok = send(tok, ctrl_s, Ctrl { length: Length:4 });
        let (tok, output) = recv(tok, data_r);
        assert_eq(output, Output { payload: OutputPayload { data: Data:0xD, length: Length:4, last: false }, status: OutputStatus::OK});

        let tok = send(tok, ctrl_s, Ctrl { length: Length:48 });
        let (tok, output) = recv(tok, data_r);
        assert_eq(output, Output { payload: OutputPayload { data: Data:0xAA_11_BB_22_CC_33, length: Length:48, last: false }, status: OutputStatus::OK});

        let tok = send(tok, ctrl_s, Ctrl { length: Length:64 });
        let (tok, output) = recv(tok, data_r);
        assert_eq(output, Output { payload: OutputPayload { data: Data:0xEE_55_FF_66_00_77_11_88, length: Length:64, last: false }, status: OutputStatus::OK});

        // Single input, single output packet 32bit buffering
        let tok = send(tok, ctrl_s, Ctrl { length: Length:32});
        let (tok, data) = recv(tok, data_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0xAABB_CCDD, length: Length: 32, last: false}, status: OutputStatus::OK});

        // Multiple input packets, single output 32bit buffering
        let tok = send(tok, ctrl_s, Ctrl { length: Length:32});
        let (tok, data) = recv(tok, data_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x1122_3344, length: Length: 32, last: false}, status: OutputStatus::OK});

        // Small consecutive single input, single output 8bit buffering
        let tok = send(tok, ctrl_s, Ctrl { length: Length:8});
        let (tok, data) = recv(tok, data_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x55, length: Length: 8, last: false}, status: OutputStatus::OK});
        let tok = send(tok, ctrl_s, Ctrl { length: Length:8});
        let (tok, data) = recv(tok, data_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x66, length: Length: 8, last: false}, status: OutputStatus::OK});

        // Multiple input packets, single output 64bit buffering
        let tok = send(tok, ctrl_s, Ctrl { length: Length:64});
        let (tok, data) = recv(tok, data_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x7788_99AA_BBCC_DDEE, length: Length: 64, last: false}, status: OutputStatus::OK});

        // Single input packet, single output 64bit buffering
        let tok = send(tok, ctrl_s, Ctrl { length: Length:64});
        let (tok, data) = recv(tok, data_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x1122_3344_5566_7788, length: Length: 64, last: false}, status: OutputStatus::OK});

        // Single 64bit input packet, multiple output packets of different sizes
        let tok = send(tok, ctrl_s, Ctrl { length: Length:8});
        let (tok, data) = recv(tok, data_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0xAA, length: Length: 8, last: false}, status: OutputStatus::OK});
        let tok = send(tok, ctrl_s, Ctrl { length: Length:8});
        let (tok, data) = recv(tok, data_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0xBB, length: Length: 8, last: false}, status: OutputStatus::OK});
        let tok = send(tok, ctrl_s, Ctrl { length: Length:16});
        let (tok, data) = recv(tok, data_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0xCCDD, length: Length: 16, last: false}, status: OutputStatus::OK});
        let tok = send(tok, ctrl_s, Ctrl { length: Length:32});
        let (tok, data) = recv(tok, data_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0xEEFF_0011, length: Length: 32, last: false}, status: OutputStatus::OK});

        // Consecutive small packet last propagation
        let tok = send(tok, ctrl_s, Ctrl { length: Length:16});
        let (tok, data) = recv(tok, data_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x1122, length: Length: 16, last: true}, status: OutputStatus::OK});
        let tok = send(tok, ctrl_s, Ctrl { length: Length:16});
        let (tok, data) = recv(tok, data_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x3344, length: Length: 16, last: true}, status: OutputStatus::OK});

        // Multiple input packets with last propagation at the last packet
        let tok = send(tok, ctrl_s, Ctrl { length: Length:32});
        let (tok, data) = recv(tok, data_r);
        assert_eq(data, Output { payload: OutputPayload { data: Data: 0x5566_7788, length: Length: 32, last: true}, status: OutputStatus::OK});

        send(tok, terminator, true);
    }
}
