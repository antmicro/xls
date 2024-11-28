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

enum RefillerFsm: u2 {
    IDLE = 0,
    REFILLING = 1,
    FLUSHING = 2,
}

enum RefillError: u1 {
    AXI_ERROR = 0,
}

struct RefillerState<ADDR_W: u32, LENGTH_W: u32, BUFFER_W_CLOG2: u32> {
    curr_addr: uN[ADDR_W],                       // next memory address to request data from
    fsm: RefillerFsm,                            // FSM state
    buffer_occupancy: uN[BUFFER_W_CLOG2],        // amount of bits that are currently in the ShiftBuffer +
                                                 // amount of bits that will enter ShiftBuffer once all
                                                 // pending memory requests are served
    axi_error: bool,                             // whether or not at least one memory read resulted in AXI error
    bits_to_axi_error: uN[BUFFER_W_CLOG2],       // amount of bits that we need to consume from the
                                                 // ShiftBuffer to trigger the AXI error
    bits_to_flush: uN[BUFFER_W_CLOG2],           // amount of bits left to flush during flushing state
}


pub proc RefillingShiftBufferInternal<
    DATA_W: u32, ADDR_W: u32,
    LENGTH_W: u32 = {shift_buffer::length_width(DATA_W)}, 
    DATA_W_DIV8: u32 = {DATA_W / u32:8},
    BUFFER_W: u32 = {DATA_W * u32:2},             // TODO: fix implementation detail of ShiftBuffer leaking here
    BUFFER_W_CLOG2: u32 = {std::clog2(BUFFER_W) + u32:1},
>{
    type MemReaderReq = mem_reader::MemReaderReq<ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<DATA_W, ADDR_W>;
    type MemReaderStatus = mem_reader::MemReaderStatus;
    type StartReq = RefillStart<ADDR_W>;
    type SBPacket = shift_buffer::ShiftBufferPacket<DATA_W, LENGTH_W>;
    type SBOutput = shift_buffer::ShiftBufferOutput<DATA_W, LENGTH_W>;
    type SBCtrl = shift_buffer::ShiftBufferCtrl<LENGTH_W>;
    type State = RefillerState<ADDR_W, LENGTH_W, BUFFER_W_CLOG2>;
    type Fsm = RefillerFsm;
    type BufferSize = uN[BUFFER_W_CLOG2];

    reader_req_s: chan<MemReaderReq> out;
    reader_resp_r: chan<MemReaderResp> in;
    start_req_r: chan<RefillStart> in;
    stop_flush_req_r: chan<()> in;
    error_s: chan<RefillError> out;
    buffer_data_in_s: chan<SBPacket> out;
    buffer_data_out_s: chan<SBOutput> out;
    buffer_ctrl_r: chan<SBCtrl> in;
    snoop_data_out_r: chan<SBOutput> in; 
    snoop_ctrl_s: chan<SBCtrl> out;

    config(
        reader_req_s: chan<MemReaderReq> out,
        reader_resp_r: chan<MemReaderResp> in,
        start_req_r: chan<RefillStart> in,
        stop_flush_req_r: chan<()> in,
        error_s: chan<RefillError> out,
        buffer_ctrl_r: chan<SBCtrl> in,
        buffer_data_out_s: chan<SBOutput> out,
        snoop_ctrl_s: chan<SBCtrl> out,
        buffer_data_in_s: chan<SBPacket> out,
        snoop_data_out_r: chan<SBOutput> in,
    ) {
        (reader_req_s, reader_resp_r, start_req_r, stop_flush_req_r, error_s,
        buffer_data_in_s, buffer_data_out_s, buffer_ctrl_r, snoop_data_out_r, snoop_ctrl_s)
    }

    init {
        zero!<State>()
    }

    next(state: State) {
        let tok = join();

        trace_fmt!("current state: {:#x}", state);

        // public interface - receive start/stop&flush requests
        let (_, start_req, start_valid) = recv_if_non_blocking(tok, start_req_r, state.fsm == Fsm::IDLE, zero!<StartReq>());
        let (_, (), stop_flush_valid) = recv_if_non_blocking(tok, stop_flush_req_r, state.fsm == Fsm::REFILLING, ());

        // flush logic
        let flushing_end = state.buffer_occupancy == BufferSize:0;
        let flushing = state.fsm == Fsm::FLUSHING;
        // flush at most DATA_W bits in a given next() evaluation
        let flush_amount_bits = std::umin(DATA_W as BufferSize, state.bits_to_flush);

        // snooping logic for the ShiftBuffer control channel
        // recv and immediately send out control packets heading for ShiftBuffer,
        // unless we're flushing or its not possible to serve such request anyway
        // as the buffer doesn't have enough data to serve to previous request.
        // This is to prevent unbounded amount of control packets from accumulating
        // on buffer_ctrl_r and thus potentially breaking flushing mechanism as it
        // relies on being able to 
        let (_, snoop_ctrl, snoop_ctrl_valid) = recv_if_non_blocking(tok, buffer_ctrl_r, !flushing, zero!<SBCtrl>());
        // If we're flushing send our packets for taking out data from the shiftbuffer
        // (that will then be discarded)
        let ctrl_packet = if (flushing) {
            SBCtrl {length: flush_amount_bits as uN[LENGTH_W]}
        } else if (snoop_ctrl_valid) {
            snoop_ctrl
        } else {
            zero!<SBCtrl>()
        };
        let do_send_ctrl = (flushing && flush_amount_bits > BufferSize:0) || snoop_ctrl_valid;
        send_if(tok, snoop_ctrl_s, do_send_ctrl, ctrl_packet);
        if do_send_ctrl {
            trace_fmt!("Sent snooped/injected control packet: {:#x}", ctrl_packet);
        } else {};

        // snooping logic for keeping track how many bits in ShiftBuffer are occupied
        // recv and immediately send the data heading for the ShiftBuffer output,
        // unless we're flushing - in that case discard the data
        let (_, snoop_data, snoop_data_valid) = recv_non_blocking(tok, snoop_data_out_r, zero!<SBOutput>());
        let forward_snooped_data = snoop_data_valid && !flushing;
        send_if(tok, buffer_data_out_s, forward_snooped_data, snoop_data);
        if forward_snooped_data {
            trace_fmt!("Forwarded snooped data output packet: {:#x}", snoop_data);
        } else {};

        // refilling logic
        const REFILL_SIZE = DATA_W_DIV8 as uN[ADDR_W];
        // we eagerly request data based on the *future* capacity of the buffer,
        // this might stall us (and in turn MemReader and potentially the whole bus)
        // if the proc sending control requests isn't receiving the data on
        // the output channel fast enough, but this is true of any proc that
        // uses MemReader but we don't consider this an issue
        let buf_has_enough_space = state.buffer_occupancy <= DATA_W as BufferSize;    // TODO: fix implementation detail of ShiftBuffer leaking here
        let do_refill_cycle = state.fsm == Fsm::REFILLING && buf_has_enough_space;
        // send request to memory for more data under the assumption
        // that there's enough space in the ShiftBuffer to fit it
        send_if(tok, reader_req_s, do_refill_cycle, MemReaderReq {
        addr: state.curr_addr,
            length: REFILL_SIZE,
        });
        // receive data from memory
        let (_, reader_resp, reader_resp_valid) = recv_non_blocking(tok, reader_resp_r, zero!<MemReaderResp>());
        if reader_resp_valid {
            trace_fmt!("Received data from memory: {:#x}", reader_resp);
        } else {};
        // always send some data regardless of the reader_resp.status to allow for all requests
        // to complete since there must be no requests pending during flushing
        // which needs to happen after an error
        let do_buffer_refill = reader_resp_valid;
        let reader_resp_len_bits = DATA_W as uN[LENGTH_W];
        let data_packet = SBPacket {
            data: reader_resp.data,
            length: reader_resp_len_bits,
            last: false
        };
        // this send will always succeed since part of the condition `do_buffer_refill` is `buf_has_enough_space`
        send_if(tok, buffer_data_in_s, do_buffer_refill, data_packet);
        if (do_buffer_refill) {
            trace_fmt!("Sent data to the shiftbuffer: {:#x}", data_packet);
        } else {};

        // length of additional data that will be inserted into the ShiftBuffer *in the future*
        // once all pending memory requests are served
        let future_input_bits = if (do_refill_cycle) {
            DATA_W as uN[LENGTH_W]
        } else {
            uN[LENGTH_W]:0
        };
        // length of data that was snooped on the ShiftBuffer output
        // note: default value of snoop_ctrl.length from its recv_if_non_blocking is 0
        let output_bits = snoop_data.payload.length;
        // calculate the difference in the amount of bits inserted/taken out
        // this will never underflow as it's always true that output_bits <= state.buffer_occupancy
        // (because output_bits is based on the number of outgoing bits from the buffer which cannot be
        // larger than its current occupancy) 
        let next_buffer_occupancy = state.buffer_occupancy + (future_input_bits as BufferSize) - (output_bits as BufferSize); 

        let next_bits_to_flush = if (flushing) {
            state.bits_to_flush - flush_amount_bits
        } else {
            next_buffer_occupancy
        };

        // error handling
        let axi_resp_error = reader_resp_valid && reader_resp.status == MemReaderStatus::ERROR;
        let next_bits_to_axi_error = if (axi_resp_error) {
            state.bits_to_axi_error - snoop_ctrl.length as BufferSize
        } else {
            next_buffer_occupancy - DATA_W as BufferSize
        };
        // we will consume at least one bit from the data that returned AXI error
        let reads_error_bits = snoop_ctrl_valid && state.bits_to_axi_error < snoop_ctrl.length as BufferSize;
        let do_send_error = state.axi_error && reads_error_bits;
        send_if(tok, error_s, do_send_error, RefillError::AXI_ERROR);

        let next_axi_error = (state.axi_error || axi_resp_error) && state.fsm == Fsm::REFILLING;

        // equivalent to the following implication: state.fsm == Fsm::IDLE => next_buffer_occupancy == 0
        assert!(!(state.fsm == Fsm::IDLE) || state.buffer_occupancy == BufferSize:0, "buffer_occupancy was not 0 in IDLE state");        

        // FSM
        let next_state = match (state.fsm) {
            Fsm::IDLE => {
                if (start_valid) {
                    State {
                        fsm: Fsm::REFILLING,
                        curr_addr: start_req.start_addr,
                        ..state
                    }
                } else {
                    state
                }
            },
            Fsm::REFILLING => {
                // stop and AXI error might happen on the same cycle,
                // in that case stop&flush takes precedence over error
                if (stop_flush_valid) {
                    State {
                        fsm: Fsm::FLUSHING,
                        ..state
                    }
                } else if (do_send_error) {
                    State {
                        fsm: Fsm::IDLE,
                        ..state
                    }
                } else if (do_refill_cycle) {
                    State {
                        curr_addr: state.curr_addr + REFILL_SIZE,
                        ..state
                    }
                } else {
                    state
                }
            },
            Fsm::FLUSHING => {
                if (flushing_end) {
                    State {
                        fsm: Fsm::IDLE,
                        axi_error: false,
                        ..state
                    }
                } else {
                    state
                }
            },
            _ => fail!("refilling_shift_buffer_fsm_unreachable", zero!<State>())
        };

        // combine next FSM state with buffer occupancy data
        State {
            buffer_occupancy: next_buffer_occupancy,
            bits_to_axi_error: next_bits_to_axi_error,
            bits_to_flush: next_bits_to_flush,
            axi_error: next_axi_error,
            ..next_state
        }
    }
}

pub proc RefillingShiftBuffer<
    DATA_W: u32,
    ADDR_W: u32,
    LENGTH_W: u32 = {shift_buffer::length_width(DATA_W)},
> {
    type MemReaderReq = mem_reader::MemReaderReq<ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<DATA_W, ADDR_W>;
    type StartReq = RefillStart<ADDR_W>;
    type SBPacket = shift_buffer::ShiftBufferPacket<DATA_W, LENGTH_W>;
    type SBOutput = shift_buffer::ShiftBufferOutput<DATA_W, LENGTH_W>;
    type SBCtrl = shift_buffer::ShiftBufferCtrl<LENGTH_W>;

    config(
        reader_req_s: chan<MemReaderReq> out,
        reader_resp_r: chan<MemReaderResp> in,
        start_req_r: chan<StartReq> in,
        stop_flush_req_r: chan<()> in,
        error_s: chan<RefillError> out,
        buffer_ctrl_r: chan<SBCtrl> in,
        buffer_data_out_s: chan<SBOutput> out,
    ) {
        let (buffer_data_in_s, buffer_data_in_r) = chan<SBPacket>("buffer_data_in");
        let (snoop_data_out_s, snoop_data_out_r) = chan<SBOutput>("snoop_data_out_s");
        let (snoop_ctrl_s, snoop_ctrl_r) = chan<SBCtrl>("snoop_ctrl");

        spawn shift_buffer::ShiftBuffer<DATA_W, LENGTH_W>(
            snoop_ctrl_r, buffer_data_in_r, snoop_data_out_s
        );
        spawn RefillingShiftBufferInternal<DATA_W, ADDR_W>(
            reader_req_s,
            reader_resp_r,
            start_req_r,
            stop_flush_req_r,
            error_s,
            buffer_ctrl_r,
            buffer_data_out_s,
            snoop_ctrl_s,
            buffer_data_in_s,
            snoop_data_out_r,
        );
    }

    init {}

    next(_: ()) {}
}


const TEST_DATA_W = u32:64;
const TEST_ADDR_W = u32:32;
const TEST_LENGTH_W = shift_buffer::length_width(TEST_DATA_W);
const TEST_DATA_W_DIV8 = TEST_DATA_W / u32:8;
const TEST_BUFFER_W = TEST_DATA_W * u32:2;             // TODO: fix implementation detail of ShiftBuffer leaking here
const TEST_BUFFER_W_CLOG2 = std::clog2(TEST_BUFFER_W);

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
    type State = RefillerState<TEST_ADDR_W, TEST_BUFFER_W_CLOG2>;

    terminator: chan<bool> out;
    reader_req_r: chan<MemReaderReq> in;
    reader_resp_s: chan<MemReaderResp> out;
    start_req_s: chan<StartReq> out;
    stop_flush_req_s: chan<()> out;
    error_r: chan<RefillError> in;
    buffer_ctrl_s: chan<SBCtrl> out;
    buffer_data_out_r: chan<SBOutput> in;
    
    config(terminator: chan<bool> out) {
        let (reader_req_s, reader_req_r) = chan<MemReaderReq>("reader_req");
        let (reader_resp_s, reader_resp_r) = chan<MemReaderResp>("reader_resp");
        let (start_req_s, start_req_r) = chan<StartReq>("start_req");
        let (stop_flush_req_s, stop_flush_req_r) = chan<()>("stop_flush_req");
        let (error_s, error_r) = chan<RefillError>("error");
        let (buffer_ctrl_s, buffer_ctrl_r) = chan<SBCtrl>("buffer_ctrl");
        let (buffer_data_out_s, buffer_data_out_r) = chan<SBOutput>("buffer_data_out");

        spawn RefillingShiftBuffer<TEST_DATA_W, TEST_ADDR_W>(
            reader_req_s, reader_resp_r, start_req_r, stop_flush_req_r,
            error_s, buffer_ctrl_r, buffer_data_out_s,
        );

        (
            terminator, reader_req_r, reader_resp_s, start_req_s,
            stop_flush_req_s, error_r, buffer_ctrl_s, buffer_data_out_r
        )
    }

    init { }

    next(state: ()) {
        let tok = join();

        const REFILL_SIZE = TEST_DATA_W_DIV8 as uN[TEST_ADDR_W];
        let tok = send(tok, start_req_s, StartReq { start_addr: uN[TEST_ADDR_W]:0xDEAD_0008 });
        
        // proc should ask for data 2 times (2/3 of the size of the internal ShiftBuffer)
        let (tok, req) = recv(tok, reader_req_r);
        assert_eq(req, MemReaderReq {
            addr: uN[TEST_ADDR_W]:0xDEAD_0008,
            length: REFILL_SIZE,
        });
        let tok = send(tok, reader_resp_s, MemReaderResp {
            status: MemReaderStatus::OKAY,
            data: uN[TEST_DATA_W]:0x01234567_89ABCDEF,
            length: REFILL_SIZE,
            last: false,
        });
        let (tok, req) = recv(tok, reader_req_r);
        assert_eq(req, MemReaderReq {
            addr: uN[TEST_ADDR_W]:0xDEAD_0010,
            length: REFILL_SIZE,
        });
        let tok = send(tok, reader_resp_s, MemReaderResp {
            status: MemReaderStatus::OKAY,
            data: uN[TEST_DATA_W]:0xFEDCBA98_76543210,
            length: REFILL_SIZE,
            last: false,
        });

        // read single byte
        let tok = send(tok, buffer_ctrl_s, SBCtrl {
            length: uN[TEST_LENGTH_W]:8
        });
        let (tok, resp) = recv(tok, buffer_data_out_r);
        assert_eq(resp, SBOutput {
            status: SBStatus::OK,
            payload: SBPacket {
                data: uN[TEST_DATA_W]:0xEF,
                length: uN[TEST_LENGTH_W]:8,
                last: false,
            }
        });

        // proc shouldn't be asking for any more data at this point
        let tok = for (_, tok): (u32, token) in u32:1..u32:100 {
            let (tok, _, data_valid) = recv_non_blocking(tok, reader_req_r, zero!<MemReaderReq>());
            assert_eq(data_valid, false);
            tok
        }(tok);

        // read enough data from the buffer to trigger a refill
        let tok = send(tok, buffer_ctrl_s, SBCtrl {
            length: uN[TEST_LENGTH_W]:56
        });
        let (tok, resp) = recv(tok, buffer_data_out_r);
        assert_eq(resp, SBOutput {
            status: SBStatus::OK,
            payload: SBPacket {
                data: uN[TEST_DATA_W]:0x01234567_89ABCD,
                length: uN[TEST_LENGTH_W]:56,
                last: false,
            }
        });
        let (tok, req) = recv(tok, reader_req_r);
        assert_eq(req, MemReaderReq {
            addr: uN[TEST_ADDR_W]:0xDEAD_0018,
            length: REFILL_SIZE,
        });
        // don't respond to the request yet

        // we have 64 bits in the buffer at this point - almost empty it manually
        let tok = send(tok, buffer_ctrl_s, SBCtrl {
            length: uN[TEST_LENGTH_W]:60
        });
        let (tok, resp) = recv(tok, buffer_data_out_r);
        assert_eq(resp, SBOutput {
            status: SBStatus::OK,
            payload: SBPacket {
                data: uN[TEST_DATA_W]:0xEDCBA98_76543210,
                length: uN[TEST_LENGTH_W]:60,
                last: false,
            }
        });

        // ask for more data from the buffer (but not enough data is available)
        let tok = send(tok, buffer_ctrl_s, SBCtrl {
            length: uN[TEST_LENGTH_W]:12
        });
        // make sure that reading from output is stuck
        let tok = for (_, tok): (u32, token) in u32:1..u32:100 {
            let (tok, _, data_valid) = recv_non_blocking(tok, buffer_data_out_r, zero!<SBOutput>());
            assert_eq(data_valid, false);
            tok
        }(tok);

        // serve earlier memory request
        let tok = send(tok, reader_resp_s, MemReaderResp {
            status: MemReaderStatus::OKAY,
            data: uN[TEST_DATA_W]:0x02481357_8ACE9BD0,
            length: REFILL_SIZE,
            last: false,
        });
        // should be able to receive from the buffer now
        let (tok, resp) = recv(tok, buffer_data_out_r);
        assert_eq(resp, SBOutput {
            status: SBStatus::OK,
            payload: SBPacket {
                data: uN[TEST_DATA_W]:0xD0F,
                length: uN[TEST_LENGTH_W]:12,
                last: false,
            }
        });

        // buffer now contains 56 bits - proc should have sent 1 more
        // memory requests by this point - serve it
        let (tok, req) = recv(tok, reader_req_r);
        assert_eq(req, MemReaderReq {
            addr: uN[TEST_ADDR_W]:0xDEAD_0020,
            length: REFILL_SIZE,
        });
        let tok = send(tok, reader_resp_s, MemReaderResp {
            status: MemReaderStatus::OKAY,
            data: uN[TEST_DATA_W]:0x86868686_42424242,
            length: REFILL_SIZE,
            last: false,
        });

        // make sure proc is not requesting more data that we can insert into the buffer
        let tok = for (_, tok): (u32, token) in u32:1..u32:100 {
            let (tok, _, req_valid) = recv_non_blocking(tok, reader_req_r, zero!<MemReaderReq>());
            assert_eq(req_valid, false);
            tok
        }(tok);

        // try flushing
        let tok = send(tok, stop_flush_req_s, ());

        // start from a new address and refill buffer with more data
        let tok = send(tok, start_req_s, StartReq { start_addr: u32: 0x1000_11F0 });
        let (tok, req) = recv(tok, reader_req_r);
        assert_eq(req, MemReaderReq {
            addr: uN[TEST_ADDR_W]:0x1000_11F0,
            length: REFILL_SIZE,
        });
        let tok = send(tok, reader_resp_s, MemReaderResp {
            status: MemReaderStatus::OKAY,
            data: uN[TEST_DATA_W]:0xFEFDFCFB_FAF9F8F7,
            length: REFILL_SIZE,
            last: false,
        });

        // old request for 4 bits was flushed as well so we need to issue a new one
        let tok = send(tok, buffer_ctrl_s, SBCtrl {
            length: uN[TEST_LENGTH_W]:4
        });
        // we should be able to receive data from the buffer at this point
        let (tok, resp) = recv(tok, buffer_data_out_r);
        assert_eq(resp, SBOutput {
            status: SBStatus::OK,
            payload: SBPacket {
                data: uN[TEST_DATA_W]:0x7,
                length: uN[TEST_LENGTH_W]:4,
                last: false,
            }
        });
    
        // refill with even more data
        let (tok, req) = recv(tok, reader_req_r);
        assert_eq(req, MemReaderReq {
            addr: uN[TEST_ADDR_W]:0x1000_11F8,
            length: REFILL_SIZE,
        });
        let tok = send(tok, reader_resp_s, MemReaderResp {
            status: MemReaderStatus::OKAY,
            data: uN[TEST_DATA_W]:0xABBA_BAAB_AABB_BBAA,
            length: REFILL_SIZE,
            last: false,
        });

        let tok = send(tok, buffer_ctrl_s, SBCtrl {
            length: uN[TEST_LENGTH_W]:64
        });
        let tok = send(tok, buffer_ctrl_s, SBCtrl {
            length: uN[TEST_LENGTH_W]:60
        });

        // receive all of the new data and verify that it's new data
        let (tok, resp) = recv(tok, buffer_data_out_r);
        assert_eq(resp, SBOutput {
            status: SBStatus::OK,
            payload: SBPacket {
                data: uN[TEST_DATA_W]:0xAFEFDFCF_BFAF9F8F,
                length: uN[TEST_LENGTH_W]:64,
                last: false,
            }
        });
        let (tok, resp) = recv(tok, buffer_data_out_r);
        assert_eq(resp, SBOutput {
            status: SBStatus::OK,
            payload: SBPacket {
                data: uN[TEST_DATA_W]:0xABBA_BAAB_AABB_BBA,
                length: uN[TEST_LENGTH_W]:60,
                last: false,
            }
        });

        send(tok, terminator, true);
    }
}

proc RefillingShiftBufferInternalInst {
    type MemReaderReq = mem_reader::MemReaderReq<TEST_ADDR_W>;
    type MemReaderResp = mem_reader::MemReaderResp<TEST_DATA_W, TEST_ADDR_W>;
    type MemReaderStatus = mem_reader::MemReaderStatus;
    type StartReq = RefillStart<TEST_ADDR_W>;
    type SBPacket = shift_buffer::ShiftBufferPacket<TEST_DATA_W, TEST_LENGTH_W>;
    type SBOutput = shift_buffer::ShiftBufferOutput<TEST_DATA_W, TEST_LENGTH_W>;
    type SBCtrl = shift_buffer::ShiftBufferCtrl<TEST_LENGTH_W>;
    type SBStatus = shift_buffer::ShiftBufferStatus;
    type State = RefillerState<TEST_ADDR_W, TEST_LENGTH_W, TEST_BUFFER_W_CLOG2>;

    reader_req_s: chan<MemReaderReq> out;
    reader_resp_r: chan<MemReaderResp> in;
    start_req_r: chan<StartReq> in;
    stop_flush_req_r: chan<()> in;
    error_s: chan<RefillError> out;
    buffer_ctrl_r: chan<SBCtrl> in;
    buffer_data_out_s: chan<SBOutput> out;
    snoop_ctrl_s: chan<SBCtrl> out;
    buffer_data_in_s: chan<SBPacket> out;
    snoop_data_out_r: chan<SBOutput> in;
    
    config(
        reader_req_s: chan<MemReaderReq> out,
        reader_resp_r: chan<MemReaderResp> in,
        start_req_r: chan<StartReq> in,
        stop_flush_req_r: chan<()> in,
        error_s: chan<RefillError> out,
        buffer_ctrl_r: chan<SBCtrl> in,
        buffer_data_out_s: chan<SBOutput> out,
        snoop_ctrl_s: chan<SBCtrl> out,
        buffer_data_in_s: chan<SBPacket> out,
        snoop_data_out_r: chan<SBOutput> in,
    ) {
        spawn RefillingShiftBufferInternal<TEST_DATA_W, TEST_ADDR_W>(
            reader_req_s, reader_resp_r, start_req_r, stop_flush_req_r,
            error_s, buffer_ctrl_r, buffer_data_out_s, snoop_ctrl_s,
            buffer_data_in_s, snoop_data_out_r,
        );

        (
            reader_req_s, reader_resp_r, start_req_r, stop_flush_req_r,
            error_s, buffer_ctrl_r, buffer_data_out_s, snoop_ctrl_s,
            buffer_data_in_s, snoop_data_out_r
        )
    }

    init { }

    next(state: ()) { }
}
