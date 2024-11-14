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
import xls.modules.shift_buffer.shift_buffer;
import xls.modules.zstd.memory.mem_reader;


pub struct RefillStart<ADDR_W: u32> {
    start_addr: uN[ADDR_W]
}

enum RefillerStatus: u1 {
    STOPPED = 0,
    REFILLING = 1,
}

enum RefillError: u1 {
    AXI_ERROR = 0,
}

struct RefillerState<ADDR_W: u32> {
    curr_addr: uN[ADDR_W],
    status: RefillerStatus,
}


pub proc RefillingShiftBuffer<
    DATA_W: u32, ADDR_W: u32,
    LENGTH_W: u32 = {shift_buffer::length_width(DATA_W)},
    DATA_W_DIV8: u32 = {DATA_W / u32:8},
>{
    type MemReaderReq = mem_reader::MemReaderReq<ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<DATA_W, ADDR_W>;
    type MemReaderStatus = mem_reader::MemReaderStatus;
    type StartReq = RefillStart<ADDR_W>;
    type SBPacket = shift_buffer::ShiftBufferPacket<DATA_W, LENGTH_W>;
    type SBOutput = shift_buffer::ShiftBufferOutput<DATA_W, LENGTH_W>;
    type SBCtrl = shift_buffer::ShiftBufferCtrl<LENGTH_W>;
    type State = RefillerState<ADDR_W>;

    reader_req_s: chan<MemReaderReq> out;
    reader_resp_r: chan<MemReaderResp> in;
    start_req_r: chan<RefillStart> in;
    stop_req_r: chan<()> in;
    error_s: chan<RefillError> out;
    buffer_data_in_s: chan<SBPacket> out;

    config(
        reader_req_s: chan<MemReaderReq> out,
        reader_resp_r: chan<MemReaderResp> in,
        start_req_r: chan<RefillStart> in,
        stop_req_r: chan<()> in,
        error_s: chan<RefillError> out,
        buffer_ctrl_r: chan<SBCtrl> in,
        buffer_data_out_s: chan<SBOutput> out,
    ) {
        let (buffer_data_in_s, buffer_data_in_r) = chan<SBPacket, u32:1>("buffer_data_in");

        spawn shift_buffer::ShiftBuffer<DATA_W, LENGTH_W>(
            buffer_ctrl_r, buffer_data_in_r, buffer_data_out_s
        );

        (reader_req_s, reader_resp_r, start_req_r, stop_req_r, error_s, buffer_data_in_s)
    }

    init {
        zero!<State>()
    }

    next(state: State) {
        const REFILL_SIZE = (DATA_W_DIV8 * u32:2) as uN[ADDR_W];
        
        let tok = join();
        let (tok_start, start_req, start_req_valid) = recv_non_blocking(tok, start_req_r, zero!<RefillStart>());
        
        let next_curr_addr = if (start_req_valid) {
            start_req.start_addr
        } else {
            state.curr_addr + DATA_W_DIV8 as uN[ADDR_W]
        };

        let (tok_stop, (), stop_req_valid) = recv_non_blocking(tok, stop_req_r, ());
        let next_state = if (stop_req_valid) {
            RefillerStatus::STOPPED
        } else {
            state.status
        };

        let next_state = match (start_req_valid, stop_req_valid, state.status) {
            // start takes precedence over stop
            (true, _, _) => State {
                curr_addr: start_req.start_addr,
                status: RefillerStatus::REFILLING
            },
            (false, true, _) => State {
                status: RefillerStatus::STOPPED,
                ..state
            },
            (false, false, RefillerStatus::REFILLING) => State {
                curr_addr: state.curr_addr + REFILL_SIZE,
                ..state
            },
            _ => state
        };

        let do_refill_cycle = state.status == RefillerStatus::REFILLING;
        let req_tok = send_if(tok, reader_req_s, do_refill_cycle, MemReaderReq {
            addr: state.curr_addr,
            length: REFILL_SIZE,
        });
        let (resp_tok, reader_resp) = recv_if(req_tok, reader_resp_r, do_refill_cycle, zero!<MemReaderResp>());
        
        let do_buffer_refill = do_refill_cycle && reader_resp.status == MemReaderStatus::OKAY;
        let do_error_resp = do_refill_cycle && reader_resp.status == MemReaderStatus::ERROR;

        send_if(resp_tok, buffer_data_in_s, do_refill_cycle, SBPacket {
            data: reader_resp.data,
            length: reader_resp.length as uN[LENGTH_W],
            last: false // tells shift buffer to also receive new data on next iteration
        });

        send_if(resp_tok, error_s, do_error_resp, RefillError::AXI_ERROR);

        if (do_error_resp) {
            State {
                status: RefillerStatus::STOPPED,
                ..next_state
            }
        } else {
            next_state
        }
    }
}

const TEST_DATA_W = u32:64;
const TEST_ADDR_W = u32:32;
const TEST_LENGTH_W = shift_buffer::length_width(TEST_DATA_W);
const TEST_DATA_W_DIV8 = TEST_DATA_W / u32:8;

#[test_proc]
proc RefillingShiftBufferTest {
    type MemReaderReq = mem_reader::MemReaderReq<TEST_ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<TEST_DATA_W, TEST_ADDR_W>;
    type MemReaderStatus = mem_reader::MemReaderStatus;
    type StartReq = RefillStart<TEST_ADDR_W>;
    type SBPacket = shift_buffer::ShiftBufferPacket<TEST_DATA_W, TEST_LENGTH_W>;
    type SBOutput = shift_buffer::ShiftBufferOutput<TEST_DATA_W, TEST_LENGTH_W>;
    type SBCtrl = shift_buffer::ShiftBufferCtrl<TEST_LENGTH_W>;
    type SBStatus = shift_buffer::ShiftBufferStatus;
    type State = RefillerState<TEST_ADDR_W>;

    terminator: chan<bool> out;
    reader_req_r: chan<MemReaderReq> in;
    reader_resp_s: chan<MemReaderResp> out;
    start_req_s: chan<StartReq> out;
    stop_req_s: chan<()> out;
    error_r: chan<RefillError> in;
    buffer_ctrl_s: chan<SBCtrl> out;
    buffer_data_out_r: chan<SBOutput> in;
    
    config(terminator: chan<bool> out) {
        let (reader_req_s, reader_req_r) = chan<MemReaderReq>("reader_req");
        let (reader_resp_s, reader_resp_r) = chan<MemReaderResp>("reader_resp");
        let (start_req_s, start_req_r) = chan<StartReq>("start_req");
        let (stop_req_s, stop_req_r) = chan<()>("stop_req");
        let (error_s, error_r) = chan<RefillError>("error");
        let (buffer_ctrl_s, buffer_ctrl_r) = chan<SBCtrl>("buffer_ctrl");
        let (buffer_data_out_s, buffer_data_out_r) = chan<SBOutput>("buffer_data_out");

        spawn RefillingShiftBuffer<TEST_DATA_W, TEST_ADDR_W>(
            reader_req_s, reader_resp_r, start_req_r, stop_req_r,
            error_s, buffer_ctrl_r, buffer_data_out_s,
        );

        (
            terminator, reader_req_r, reader_resp_s, start_req_s,
            stop_req_s, error_r, buffer_ctrl_s, buffer_data_out_r
        )
    }

    init { }

    next(state: ()) {
        let tok = join();

        const REFILL_SIZE = (TEST_DATA_W_DIV8 * u32:2) as uN[TEST_ADDR_W];
        let tok = send(tok, start_req_s, StartReq { start_addr: uN[TEST_ADDR_W]:0xDEAD_0008 });
        let (tok, req) = recv(tok, reader_req_r);
        assert_eq(req, MemReaderReq {
            addr: uN[TEST_ADDR_W]:0xDEAD_0008,
            length: REFILL_SIZE,
        });
        let tok = send(tok, reader_resp_s, MemReaderResp {
            status: MemReaderStatus::OKAY,
            data: uN[TEST_DATA_W]:0x01234567_89ABCDEF,
            length: TEST_DATA_W,
            last: false,
        });
        let tok = send(tok, reader_resp_s, MemReaderResp {
            status: MemReaderStatus::OKAY,
            data: uN[TEST_DATA_W]:0xFEBCBA_76543210,
            length: TEST_DATA_W,
            last: false,
        });

        let tok = send(tok, buffer_ctrl_s, SBCtrl {
            length: uN[TEST_LENGTH_W]:0x8
        });
        let (tok, resp) = recv(tok, buffer_data_out_r);
        assert_eq(resp, SBOutput {
            status: SBStatus::OK,
            payload: SBPacket {
                data: uN[TEST_DATA_W]:0xEF,
                length: uN[TEST_LENGTH_W]:0x8,
                last: false,
            }
        });

        send(tok, terminator, true);
    }
}

proc RefillingShiftBufferInst {
    type MemReaderReq = mem_reader::MemReaderReq<TEST_ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<TEST_DATA_W, TEST_ADDR_W>;
    type MemReaderStatus = mem_reader::MemReaderStatus;
    type StartReq = RefillStart<TEST_ADDR_W>;
    type SBPacket = shift_buffer::ShiftBufferPacket<TEST_DATA_W, TEST_LENGTH_W>;
    type SBOutput = shift_buffer::ShiftBufferOutput<TEST_DATA_W, TEST_LENGTH_W>;
    type SBCtrl = shift_buffer::ShiftBufferCtrl<TEST_LENGTH_W>;
    type SBStatus = shift_buffer::ShiftBufferStatus;
    type State = RefillerState<TEST_ADDR_W>;

    reader_req_s: chan<MemReaderReq> out;
    reader_resp_r: chan<MemReaderResp> in;
    start_req_r: chan<StartReq> in;
    stop_req_r: chan<()> in;
    error_s: chan<RefillError> out;
    buffer_ctrl_r: chan<SBCtrl> in;
    buffer_data_out_s: chan<SBOutput> out;
    
    config(
        reader_req_s: chan<MemReaderReq> out,
        reader_resp_r: chan<MemReaderResp> in,
        start_req_r: chan<StartReq> in,
        stop_req_r: chan<()> in,
        error_s: chan<RefillError> out,
        buffer_ctrl_r: chan<SBCtrl> in,
        buffer_data_out_s: chan<SBOutput> out,
    ) {
        spawn RefillingShiftBuffer<TEST_DATA_W, TEST_ADDR_W>(
            reader_req_s, reader_resp_r, start_req_r, stop_req_r,
            error_s, buffer_ctrl_r, buffer_data_out_s,
        );

        (
            reader_req_s, reader_resp_r, start_req_r, stop_req_r,
            error_s, buffer_ctrl_r, buffer_data_out_s,
        )
    }

    init { }

    next(state: ()) { }
}