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

// This file contains utilities related to ZSTD Block Header parsing.
// More information about the ZSTD Block Header can be found in:
// https://datatracker.ietf.org/doc/html/rfc8878#section-3.1.1.2


import std;
import xls.examples.ram;

struct RamMuxState { active_channel: u1, pending_requests: u32 }

pub proc RamMux<ADDR_WIDTH: u32, DATA_WIDTH: u32, NUM_PARTITIONS: u32, FIRST_CHANNEL: u1 = {u1:0}> {
    type ReadReq = ram::ReadReq<ADDR_WIDTH, NUM_PARTITIONS>;
    type ReadResp = ram::ReadResp<DATA_WIDTH>;
    type WriteReq = ram::WriteReq<ADDR_WIDTH, DATA_WIDTH, NUM_PARTITIONS>;
    type WriteResp = ram::WriteResp;
    active_channel_r: chan<u1> in;
    rd_req0_r: chan<ReadReq> in;
    rd_resp0_s: chan<ReadResp> out;
    wr_req0_r: chan<WriteReq> in;
    wr_resp0_s: chan<WriteResp> out;
    rd_req1_r: chan<ReadReq> in;
    rd_resp1_s: chan<ReadResp> out;
    wr_req1_r: chan<WriteReq> in;
    wr_resp1_s: chan<WriteResp> out;
    rd_req_s: chan<ReadReq> out;
    rd_resp_r: chan<ReadResp> in;
    wr_req_s: chan<WriteReq> out;
    wr_resp_r: chan<WriteResp> in;

    config(active_channel_r: chan<u1> in, rd_req0_r: chan<ReadReq> in,
           rd_resp0_s: chan<ReadResp> out, wr_req0_r: chan<WriteReq> in,
           wr_resp0_s: chan<WriteResp> out, rd_req1_r: chan<ReadReq> in,
           rd_resp1_s: chan<ReadResp> out, wr_req1_r: chan<WriteReq> in,
           wr_resp1_s: chan<WriteResp> out, rd_req_s: chan<ReadReq> out,
           rd_resp_r: chan<ReadResp> in, wr_req_s: chan<WriteReq> out, wr_resp_r: chan<WriteResp> in) {
        (
            active_channel_r, rd_req0_r, rd_resp0_s, wr_req0_r, wr_resp0_s, rd_req1_r, rd_resp1_s,
            wr_req1_r, wr_resp1_s, rd_req_s, rd_resp_r, wr_req_s, wr_resp_r,
        )
    }

    init { RamMuxState { active_channel: FIRST_CHANNEL, ..zero!<RamMuxState>() } }

    next(state: RamMuxState) {
        let tok = join();

        let active_channel = state.active_channel;
        let pending_requests = state.pending_requests;

        // Receive any requests from the selected channel.
        let (tok_rd_req, rd_req, rd_req_valid) = if active_channel == u1:0 {
            recv_non_blocking(tok, rd_req0_r, zero!<ReadReq>())
        } else {
            recv_non_blocking(tok, rd_req1_r, zero!<ReadReq>())
        };
        let (tok_wr_req, wr_req, wr_req_valid) = if active_channel == u1:0 {
            recv_non_blocking(tok, wr_req0_r, zero!<WriteReq>())
        } else {
            recv_non_blocking(tok, wr_req1_r, zero!<WriteReq>())
        };

        // Record the incoming requests as pending.
        let pending_requests = pending_requests + (rd_req_valid as u32) + (wr_req_valid as u32);

        // Receive any responses from the RAM.
        let (tok_rd_resp, rd_resp, rd_resp_valid) =
            recv_non_blocking(join(), rd_resp_r, zero!<ReadResp>());
        let (tok_wr_resp, wr_resp, wr_resp_valid) =
            recv_non_blocking(join(), wr_resp_r, zero!<WriteResp>());

        let all_receives = join(tok_rd_req, tok_wr_req, tok_rd_resp, tok_wr_resp);

        // Send any requests to the RAM.
        let sent_rd_req = send_if(all_receives, rd_req_s, rd_req_valid, rd_req);
        let sent_wr_req = send_if(all_receives, wr_req_s, wr_req_valid, wr_req);

        if active_channel == u1:0 {
            // send responses to channel 0
            send_if(all_receives, rd_resp0_s, rd_resp_valid, rd_resp);
            send_if(all_receives, wr_resp0_s, wr_resp_valid, wr_resp);
        } else {
            // send responses to channel 1
            send_if(all_receives, rd_resp1_s, rd_resp_valid, rd_resp);
            send_if(all_receives, wr_resp1_s, wr_resp_valid, wr_resp);
        };
        let pending_requests = pending_requests - (rd_resp_valid as u32) - (wr_resp_valid as u32);

        // If there are no outstanding requests, accept any incoming request to switch channels.
        let (_, active_channel, _) = recv_if_non_blocking(
            all_receives, active_channel_r, pending_requests == u32:0, state.active_channel);

        RamMuxState { active_channel, pending_requests }
    }
}

const MUX_TEST_SIZE = u32:32;
const MUX_TEST_DATA_WIDTH = u32:8;
const MUX_TEST_ADDR_WIDTH = std::clog2(MUX_TEST_SIZE);
const MUX_TEST_WORD_PARTITION_SIZE = u32:1;
const MUX_TEST_NUM_PARTITIONS = ram::num_partitions(
    MUX_TEST_WORD_PARTITION_SIZE, MUX_TEST_DATA_WIDTH);

type MuxTestAddr = uN[MUX_TEST_ADDR_WIDTH];
type MuxTestData = uN[MUX_TEST_DATA_WIDTH];

fn MuxTestWriteWordReq
    (addr: MuxTestAddr, data: MuxTestData)
    -> ram::WriteReq<MUX_TEST_ADDR_WIDTH, MUX_TEST_DATA_WIDTH, MUX_TEST_NUM_PARTITIONS> {
    ram::WriteWordReq<MUX_TEST_NUM_PARTITIONS>(addr, data)
}

fn MuxTestReadWordReq
    (addr: MuxTestAddr) -> ram::ReadReq<MUX_TEST_ADDR_WIDTH, MUX_TEST_NUM_PARTITIONS> {
    ram::ReadWordReq<MUX_TEST_NUM_PARTITIONS>(addr)
}

#[test_proc]
proc RamMuxTest {
    terminator: chan<bool> out;
    active_channel_s: chan<u1> out;
    type ReadReq = ram::ReadReq<MUX_TEST_ADDR_WIDTH, MUX_TEST_NUM_PARTITIONS>;
    type ReadResp = ram::ReadResp<MUX_TEST_DATA_WIDTH>;
    type WriteReq = ram::WriteReq<MUX_TEST_ADDR_WIDTH, MUX_TEST_DATA_WIDTH, MUX_TEST_NUM_PARTITIONS>;
    type WriteResp = ram::WriteResp;
    rd_req0_s: chan<ReadReq> out;
    rd_resp0_r: chan<ReadResp> in;
    wr_req0_s: chan<WriteReq> out;
    wr_resp0_r: chan<WriteResp> in;
    rd_req1_s: chan<ReadReq> out;
    rd_resp1_r: chan<ReadResp> in;
    wr_req1_s: chan<WriteReq> out;
    wr_resp1_r: chan<WriteResp> in;

    config(terminator: chan<bool> out) {
        let (active_channel_s, active_channel_r) = chan<u1>("active_channel");

        let (rd_req0_s, rd_req0_r) = chan<ReadReq>("rd_req0");
        let (rd_resp0_s, rd_resp0_r) = chan<ReadResp>("rd_resp0");
        let (wr_req0_s, wr_req0_r) = chan<WriteReq>("wr_req0");
        let (wr_resp0_s, wr_resp0_r) = chan<WriteResp>("wr_resp0");

        let (rd_req1_s, rd_req1_r) = chan<ReadReq>("rd_req1");
        let (rd_resp1_s, rd_resp1_r) = chan<ReadResp>("rd_resp1");
        let (wr_req1_s, wr_req1_r) = chan<WriteReq>("rd_req1");
        let (wr_resp1_s, wr_resp1_r) = chan<WriteResp>("wr_resp1");

        let (rd_req_s, rd_req_r) = chan<ReadReq>("rd_req");
        let (rd_resp_s, rd_resp_r) = chan<ReadResp>("rd_resp");
        let (wr_req_s, wr_req_r) = chan<WriteReq>("wr_req");
        let (wr_resp_s, wr_resp_r) = chan<WriteResp>("wr_resp");

        spawn RamMux<MUX_TEST_ADDR_WIDTH, MUX_TEST_DATA_WIDTH, MUX_TEST_NUM_PARTITIONS>(
            active_channel_r, rd_req0_r, rd_resp0_s, wr_req0_r, wr_resp0_s, rd_req1_r, rd_resp1_s,
            wr_req1_r, wr_resp1_s, rd_req_s, rd_resp_r, wr_req_s, wr_resp_r);

        spawn ram::RamModel<MUX_TEST_DATA_WIDTH, MUX_TEST_SIZE, MUX_TEST_WORD_PARTITION_SIZE>(
            rd_req_r, rd_resp_s, wr_req_r, wr_resp_s);
        (
            terminator, active_channel_s, rd_req0_s, rd_resp0_r, wr_req0_s, wr_resp0_r, rd_req1_s,
            rd_resp1_r, wr_req1_s, wr_resp1_r,
        )
    }

    init {  }

    next(state: ()) {
        let tok = join();
        let req = MuxTestWriteWordReq(MuxTestAddr:0, MuxTestData:0xAB);
        let tok = send(tok, wr_req0_s, req);
        let (tok, _) = recv(tok, wr_resp0_r);
        let tok = send(tok, rd_req0_s, MuxTestReadWordReq(req.addr));
        let (tok, resp) = recv(tok, rd_resp0_r);
        assert_eq(resp.data, req.data);

        let req = MuxTestWriteWordReq(MuxTestAddr:1, MuxTestData:0xCD);
        let tok = send(tok, wr_req1_s, req);
        let tok = send(tok, active_channel_s, u1:1);
        let (tok, _) = recv(tok, wr_resp1_r);
        let tok = send(tok, rd_req1_s, MuxTestReadWordReq(req.addr));
        let (tok, resp) = recv(tok, rd_resp1_r);
        assert_eq(resp.data, req.data);

        let tok = send(tok, terminator, true);
    }
}
