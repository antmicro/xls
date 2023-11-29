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

// Generic Physical Function
//
// This implementation is used to test the DMA
// Input and output is AXI Stream
//
// Performed algorithm is meant to be simple, e.g.:
// output data = input data + 1

import xls.modules.axi4.dma.axi_st

pub fn pf<N: u32>(d: uN[N]) -> uN[N] { d + uN[N]:1 }

#[test]
fn test_pf() {
    assert_eq(pf(u32:0), u32:1);
    assert_eq(pf(u32:1), u32:2);
    assert_eq(pf(u32:100), u32:101);
}

type AXI_ST = axi_st::AXI_ST;

proc gpf<DATA_W: u32, DATA_W_DIV8: u32, ID_W: u32, DEST_W: u32> {
    ch_i: chan<AXI_ST<DATA_W, DATA_W_DIV8, ID_W, DEST_W>> in;
    ch_o: chan<AXI_ST<DATA_W, DATA_W_DIV8, ID_W, DEST_W>> out;

    config(ch_i: chan<AXI_ST<DATA_W, DATA_W_DIV8, ID_W, DEST_W>> in, ch_o
    :
    chan<AXI_ST<DATA_W, DATA_W_DIV8, ID_W, DEST_W>> out) {
        (ch_i, ch_o)
    }

    init { () }

    next(tok: token, state: ()) {
        // Receive
        trace_fmt!("GPF: pre recv");
        let (tok, read_data) = recv(tok, ch_i);
        trace_fmt!("GPF: post recv");
        // Process physical function
        let data = pf(read_data.tdata);

        // Send
        let axi_packet = AXI_ST<DATA_W, DATA_W_DIV8, ID_W, DEST_W> {
            tdata: data,
            tstr: uN[DATA_W_DIV8]:0,
            tkeep: uN[DATA_W_DIV8]:0,
            tlast: u1:1,
            tid: uN[ID_W]:0,
            tdest: uN[DEST_W]:0
        };
        let tok = send(tok, ch_o, axi_packet);
        trace_fmt!("GPF: sent packet to 2nd fifo");
    }
}

const TEST_0_DATA_W = u32:8;
const TEST_0_DATA_W_DIV8 = u32:1;
const TEST_0_ID_W = u32:1;
const TEST_0_DEST_W = u32:1;

#[test_proc]
proc test_gpf {
    ch_i: chan<AXI_ST<TEST_0_DATA_W, TEST_0_DATA_W_DIV8, TEST_0_ID_W, TEST_0_DEST_W>> out;
    ch_o: chan<AXI_ST<TEST_0_DATA_W, TEST_0_DATA_W_DIV8, TEST_0_ID_W, TEST_0_DEST_W>> in;
    terminator: chan<bool> out;

    config(terminator: chan<bool> out) {
        let (ch_i_s, ch_i_r) =
            chan<AXI_ST<TEST_0_DATA_W, TEST_0_DATA_W_DIV8, TEST_0_ID_W, TEST_0_DEST_W>>;
        let (ch_o_s, ch_o_r) =
            chan<AXI_ST<TEST_0_DATA_W, TEST_0_DATA_W_DIV8, TEST_0_ID_W, TEST_0_DEST_W>>;
        spawn gpf<TEST_0_DATA_W, TEST_0_DATA_W_DIV8, TEST_0_ID_W, TEST_0_DEST_W>(ch_i_r, ch_o_s);
        (ch_i_s, ch_o_r, terminator)
    }

    init { () }

    next(tok: token, state: ()) {
        // Send data
        let data = uN[TEST_0_DATA_W]:15;
        let axi_packet = AXI_ST<TEST_0_DATA_W, TEST_0_DATA_W_DIV8, TEST_0_ID_W, TEST_0_DEST_W> {
            tdata: data,
            tstr: uN[TEST_0_DATA_W_DIV8]:0,
            tkeep: uN[TEST_0_DATA_W_DIV8]:0,
            tlast: u1:1,
            tid: uN[TEST_0_ID_W]:0,
            tdest: uN[TEST_0_DEST_W]:0
        };
        let tok = send(tok, ch_i, axi_packet);

        // Receive
        let (tok, axi_packet_r) = recv(tok, ch_o);
        let r_data = axi_packet_r.tdata;

        // Test
        trace_fmt!("Data W: {}, Data R: {}", data, r_data);
        assert_eq(data + uN[TEST_0_DATA_W]:1, r_data);
        let tok = send(tok, terminator, true);
    }
}
