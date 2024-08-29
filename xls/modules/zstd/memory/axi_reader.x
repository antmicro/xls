// Copyright 2023-2024 The XLS Authors
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

import xls.modules.zstd.memory.axi;
import xls.modules.zstd.memory.axi_st;

enum AxiReaderFsm: u2 {
    IDLE = 0,
    REQ = 1,
    RESP = 2
}

pub struct TransferReq<ADDR_W: u32> {
    addr: uN[ADDR_W],
    len: uN[ADDR_W]
}

pub fn div_ceil_pow2<N: u32>(x: uN[N], y: uN[N]) -> uN[N] {
    assert!(y != uN[N]:0, "division_by_zero");
    let rest = std::mod_pow2(x, y) != uN[N]:0;
    let div = std::div_pow2(x, y);
    div + rest as uN[N]
}

#[test]
fn test_div_ceil_pow2() {
    assert_eq(div_ceil_pow2(u32:8, u32:1), u32:8);
    assert_eq(div_ceil_pow2(u32:8, u32:2), u32:4);
    assert_eq(div_ceil_pow2(u32:8, u32:3), u32:2);
    assert_eq(div_ceil_pow2(u32:8, u32:4), u32:2);
    assert_eq(div_ceil_pow2(u32:8, u32:5), u32:1);
    assert_eq(div_ceil_pow2(u32:8, u32:6), u32:1);
    assert_eq(div_ceil_pow2(u32:8, u32:7), u32:1);
    assert_eq(div_ceil_pow2(u32:8, u32:8), u32:1);
}

fn axsize<DATA_W_DIV8: u32>() -> axi::AxiAxSize {
    match (DATA_W_DIV8) {
        u32:1  => axi::AxiAxSize::MAX_1B_TRANSFER,
        u32:2  => axi::AxiAxSize::MAX_2B_TRANSFER,
        u32:4  => axi::AxiAxSize::MAX_4B_TRANSFER,
        u32:8  => axi::AxiAxSize::MAX_8B_TRANSFER,
        u32:16 => axi::AxiAxSize::MAX_16B_TRANSFER,
        u32:32 => axi::AxiAxSize::MAX_32B_TRANSFER,
        u32:64 => axi::AxiAxSize::MAX_64B_TRANSFER,
        _      => axi::AxiAxSize::MAX_128B_TRANSFER,
    }
}

fn is_valid_axi_width(x: u32) -> bool {
    match (x) {
        u32:8    => true,
        u32:16   => true,
        u32:32   => true,
        u32:64   => true,
        u32:128  => true,
        u32:512  => true,
        u32:1024 => true,
        _        => false,
    }
}

fn is_valid_axi_size(x: u32) -> bool {
    match (x) {
        u32:1  => true,
        u32:2  => true,
        u32:4  => true,
        u32:8  => true,
        u32:16 => true,
        u32:32 => true,
        u32:64 => true,
        _      => false,
    }
}

fn is_valid_axi_addr(x: u32) -> bool {
    x >= u32:1 && x <= u32:64
}

fn align<ALIGN: u32, N:u32, LOG_ALIGN:u32 = {std::clog2(ALIGN)}>(x: uN[N]) -> uN[N] {
    x & !(all_ones!<uN[LOG_ALIGN]>() as uN[N])
}

#[test]
fn test_align() {
    assert_eq(align<u32:1>(u32:0x1000), u32:0x1000);
    assert_eq(align<u32:1>(u32:0x1001), u32:0x1001);

    assert_eq(align<u32:2>(u32:0x1000), u32:0x1000);
    assert_eq(align<u32:2>(u32:0x1001), u32:0x1000);
    assert_eq(align<u32:2>(u32:0x1002), u32:0x1002);

    assert_eq(align<u32:4>(u32:0x1000), u32:0x1000);
    assert_eq(align<u32:4>(u32:0x1001), u32:0x1000);
    assert_eq(align<u32:4>(u32:0x1002), u32:0x1000);
    assert_eq(align<u32:4>(u32:0x1003), u32:0x1000);
    assert_eq(align<u32:4>(u32:0x1004), u32:0x1004);

    assert_eq(align<u32:8>(u32:0x1000), u32:0x1000);
    assert_eq(align<u32:8>(u32:0x1001), u32:0x1000);
    assert_eq(align<u32:8>(u32:0x1002), u32:0x1000);
    assert_eq(align<u32:8>(u32:0x1003), u32:0x1000);
    assert_eq(align<u32:8>(u32:0x1004), u32:0x1000);
    assert_eq(align<u32:8>(u32:0x1005), u32:0x1000);
    assert_eq(align<u32:8>(u32:0x1006), u32:0x1000);
    assert_eq(align<u32:8>(u32:0x1007), u32:0x1000);
    assert_eq(align<u32:8>(u32:0x1008), u32:0x1008);
}

fn offset<ALIGN: u32, N:u32, LOG_ALIGN:u32 = {std::clog2(ALIGN)}>(x: uN[N]) -> uN[LOG_ALIGN] {
    type Offset = uN[LOG_ALIGN];
    checked_cast<Offset>(x & (all_ones!<uN[LOG_ALIGN]>() as uN[N]))
}

#[test]
fn test_offset() {
    const OFFSET_W = std::clog2(u32:1);
    type Offset = uN[OFFSET_W];

    assert_eq(offset<u32:1>(u32:0x1000), Offset:0x0);
    assert_eq(offset<u32:1>(u32:0x1001), Offset:0x0);

    const OFFSET_W = std::clog2(u32:2);
    type Offset = uN[OFFSET_W];

    assert_eq(offset<u32:2>(u32:0x1000), Offset:0x0);
    assert_eq(offset<u32:2>(u32:0x1001), Offset:0x1);
    assert_eq(offset<u32:2>(u32:0x1002), Offset:0x0);

    const OFFSET_W = std::clog2(u32:4);
    type Offset = uN[OFFSET_W];

    assert_eq(offset<u32:4>(u32:0x1000), Offset:0x0);
    assert_eq(offset<u32:4>(u32:0x1001), Offset:0x1);
    assert_eq(offset<u32:4>(u32:0x1002), Offset:0x2);
    assert_eq(offset<u32:4>(u32:0x1003), Offset:0x3);
    assert_eq(offset<u32:4>(u32:0x1004), Offset:0x0);

    const OFFSET_W = std::clog2(u32:8);
    type Offset = uN[OFFSET_W];

    assert_eq(offset<u32:8>(u32:0x1000), Offset:0x0);
    assert_eq(offset<u32:8>(u32:0x1001), Offset:0x1);
    assert_eq(offset<u32:8>(u32:0x1002), Offset:0x2);
    assert_eq(offset<u32:8>(u32:0x1003), Offset:0x3);
    assert_eq(offset<u32:8>(u32:0x1004), Offset:0x4);
    assert_eq(offset<u32:8>(u32:0x1005), Offset:0x5);
    assert_eq(offset<u32:8>(u32:0x1006), Offset:0x6);
    assert_eq(offset<u32:8>(u32:0x1007), Offset:0x7);
    assert_eq(offset<u32:8>(u32:0x1008), Offset:0x0);
}

fn get_lanes<
    DATA_W_DIV8: u32,
    ADDR_W: u32,
    LANE_W: u32 = {std::clog2(DATA_W_DIV8)}
>(addr: uN[ADDR_W], len: uN[ADDR_W]) -> (uN[LANE_W], uN[LANE_W]) {
    type Lane = uN[LANE_W];

    let low_lane = checked_cast<Lane>(offset<DATA_W_DIV8>(addr));
    let len_mod = checked_cast<Lane>(std::mod_pow2(len, DATA_W_DIV8 as uN[ADDR_W]));
    const MAX_LANE = std::unsigned_max_value<LANE_W>();

    let high_lane = low_lane + len_mod + MAX_LANE;
    (low_lane, high_lane)
}

#[test]
fn test_get_lanes() {
    const DATA_W_DIV8 = u32:32 / u32:8;
    const ADDR_W = u32:16;
    const LANE_W = std::clog2(DATA_W_DIV8);

    type Addr = uN[ADDR_W];
    type Length = uN[ADDR_W];
    type Lane = uN[LANE_W];

    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0x0, Length:0x1), (Lane:0, Lane:0));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0x0, Length:0x2), (Lane:0, Lane:1));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0x0, Length:0x3), (Lane:0, Lane:2));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0x0, Length:0x4), (Lane:0, Lane:3));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0x0, Length:0x5), (Lane:0, Lane:0));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0x0, Length:0x6), (Lane:0, Lane:1));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0x0, Length:0x7), (Lane:0, Lane:2));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0x0, Length:0x8), (Lane:0, Lane:3));

    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0x1, Length:0x1), (Lane:1, Lane:1));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0x1, Length:0x2), (Lane:1, Lane:2));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0x1, Length:0x3), (Lane:1, Lane:3));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0x1, Length:0x4), (Lane:1, Lane:0));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0x1, Length:0x5), (Lane:1, Lane:1));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0x1, Length:0x6), (Lane:1, Lane:2));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0x1, Length:0x7), (Lane:1, Lane:3));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0x1, Length:0x8), (Lane:1, Lane:0));

    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0xFFE, Length:0x1), (Lane:2, Lane:2));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0xFFE, Length:0x2), (Lane:2, Lane:3));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0xFFE, Length:0x3), (Lane:2, Lane:0));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0xFFE, Length:0x4), (Lane:2, Lane:1));

    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0xFFE, Length:0xFFE), (Lane:2, Lane:3));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0xFFE, Length:0xFFF), (Lane:2, Lane:0));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0xFFE, Length:0x1000), (Lane:2, Lane:1));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0xFFE, Length:0x1001), (Lane:2, Lane:2));
    assert_eq(get_lanes<DATA_W_DIV8>(Addr:0xFFE, Length:0x1002), (Lane:2, Lane:3));
}

fn lane_mask<
    DATA_W_DIV8: u32,
    LANE_W: u32 = {std::clog2(DATA_W_DIV8)},
    ITER_W: u32 = {std::clog2(DATA_W_DIV8) + u32:1}
>(low_lane: uN[LANE_W], high_lane: uN[LANE_W]) -> uN[DATA_W_DIV8] {

    type Iter = uN[ITER_W];
    const ITER_MAX = Iter:1 << LANE_W;

    type Mask = uN[DATA_W_DIV8];

    let low_mask = for (i, mask) in Iter:0..ITER_MAX {
        if i >= low_lane as Iter {
            mask | Mask:0x1 << i
        } else { mask }
    }(uN[DATA_W_DIV8]:0);

    let high_mask = for (i, mask) in Iter:0..ITER_MAX {
        if i <= high_lane as Iter {
            mask | Mask:0x1 << i
        } else { mask }
    }(uN[DATA_W_DIV8]:0);

    low_mask & high_mask
}

#[test]
fn test_lane_mask() {
    const DATA_W_DIV8 = u32:32/u32:8;
    const LANE_W = std::clog2(DATA_W_DIV8);

    type Mask = uN[DATA_W_DIV8];
    type Lane = uN[LANE_W];

    assert_eq(lane_mask<DATA_W_DIV8>(Lane:0, Lane:0), Mask:0b0001);
    assert_eq(lane_mask<DATA_W_DIV8>(Lane:0, Lane:1), Mask:0b0011);
    assert_eq(lane_mask<DATA_W_DIV8>(Lane:0, Lane:2), Mask:0b0111);
    assert_eq(lane_mask<DATA_W_DIV8>(Lane:0, Lane:3), Mask:0b1111);

    assert_eq(lane_mask<DATA_W_DIV8>(Lane:1, Lane:0), Mask:0b0000);
    assert_eq(lane_mask<DATA_W_DIV8>(Lane:1, Lane:1), Mask:0b0010);
    assert_eq(lane_mask<DATA_W_DIV8>(Lane:1, Lane:2), Mask:0b0110);
    assert_eq(lane_mask<DATA_W_DIV8>(Lane:1, Lane:3), Mask:0b1110);

    assert_eq(lane_mask<DATA_W_DIV8>(Lane:2, Lane:0), Mask:0b0000);
    assert_eq(lane_mask<DATA_W_DIV8>(Lane:2, Lane:1), Mask:0b0000);
    assert_eq(lane_mask<DATA_W_DIV8>(Lane:2, Lane:2), Mask:0b0100);
    assert_eq(lane_mask<DATA_W_DIV8>(Lane:2, Lane:3), Mask:0b1100);

    assert_eq(lane_mask<DATA_W_DIV8>(Lane:3, Lane:0), Mask:0b0000);
    assert_eq(lane_mask<DATA_W_DIV8>(Lane:3, Lane:1), Mask:0b0000);
    assert_eq(lane_mask<DATA_W_DIV8>(Lane:3, Lane:2), Mask:0b0000);
    assert_eq(lane_mask<DATA_W_DIV8>(Lane:3, Lane:3), Mask:0b1000);
}

fn bytes_to_4k_boundary<ADDR_W: u32>(addr: uN[ADDR_W]) -> uN[ADDR_W] {
    const AXI_4K_BOUNDARY = uN[ADDR_W]:0x1000;
    const AXI_4K_BOUNDARY_MASK = uN[ADDR_W]:0x1000 -  uN[ADDR_W]:1;
    AXI_4K_BOUNDARY - std::mod_pow2(addr, AXI_4K_BOUNDARY)
}

struct AxiReaderState<
    ADDR_W: u32,
    DATA_W_DIV8: u32,
    LANE_W: u32,
> {
    fsm: AxiReaderFsm,

    tran_addr: uN[ADDR_W],
    tran_len: uN[ADDR_W],

    req_tran: u8,
    req_low_lane: uN[LANE_W],
    req_high_lane: uN[LANE_W],
}

proc AxiReader<
    ADDR_W: u32, DATA_W: u32, DEST_W: u32, ID_W: u32,
    DEBUG:bool = {true},
    DATA_W_DIV8:u32 = {DATA_W / u32:8},
    LANE_W: u32 = {std::clog2(DATA_W_DIV8)},
    LANE_DATA_W_DIV8_PLUS_ONE: u32 = {std::clog2(DATA_W_DIV8) + u32:1},
    TRAN_W: u32 = {std::clog2((u32:1 << ADDR_W) / DATA_W_DIV8)},
> {
    type Req = TransferReq<ADDR_W>;
    type AxiAr = axi::AxiAr<ADDR_W, ID_W>;
    type AxiR = axi::AxiR<DATA_W, ID_W>;
    type AxiStream = axi_st::AxiStream<DATA_W, DEST_W, ID_W, DATA_W_DIV8>;
    type Fsm = AxiReaderFsm;
    type State = AxiReaderState<ADDR_W, DATA_W_DIV8, LANE_W>;

    type Data = uN[DATA_W];
    type Length = uN[ADDR_W];
    type Addr = uN[ADDR_W];
    type Lane = uN[LANE_W];

    const_assert!(is_valid_axi_width(DATA_W));
    const_assert!(is_valid_axi_addr(ADDR_W));

    req_r: chan<Req> in;
    axi_ar_s: chan<AxiAr> out;
    axi_r_r: chan<AxiR> in;
    axi_st_s: chan<AxiStream> out;

    config(
        req_r: chan<Req> in,
        axi_ar_s: chan<AxiAr> out,
        axi_r_r: chan<AxiR> in,
        axi_st_s: chan<AxiStream> out
    ) {
        (req_r, axi_ar_s, axi_r_r, axi_st_s)
    }

    init { zero!<State>() }

    next(state: State) {
        let tok0 = join();

        const BYTES_IN_TRANSFER = DATA_W_DIV8 as Addr;
        const MAX_AXI_BURST_BYTES = Addr:256 * BYTES_IN_TRANSFER;

        // IDLE logic

        let do_recv_req = (state.fsm == Fsm::IDLE);
        let (tok1_0, req) = recv_if(tok0, req_r, do_recv_req, zero!<Req>());

        // REQ logic

        let aligned_addr = align<DATA_W_DIV8>(state.tran_addr);
        let aligned_offset = offset<DATA_W_DIV8>(state.tran_addr);

        let bytes_to_4k = bytes_to_4k_boundary(state.tran_addr);
        let tran_len = std::umin(state.tran_len, std::umin(bytes_to_4k, MAX_AXI_BURST_BYTES));
        let (req_low_lane, req_high_lane) = get_lanes<DATA_W_DIV8>(state.tran_addr, tran_len);

        let adjusted_tran_len = aligned_offset as Addr + tran_len;
        let rest = std::mod_pow2(adjusted_tran_len, BYTES_IN_TRANSFER) != Length:0;
        let ar_len = if rest {
            std::div_pow2(adjusted_tran_len, BYTES_IN_TRANSFER) as u8
        } else {
            (std::div_pow2(adjusted_tran_len, BYTES_IN_TRANSFER) - Length:1) as u8
        };

        let next_tran_addr = state.tran_addr + tran_len;
        let next_tran_len = state.tran_len - tran_len;

        let axi_ar = axi::AxiAr {
            id: uN[ID_W]:0,
            addr: aligned_addr,
            region: u4:0,
            len: ar_len,
            size: axsize<DATA_W_DIV8>(),
            burst: axi::AxiAxBurst::INCR,
            cache: axi::AxiArCache::DEV_NO_BUF,
            prot: u3:0,
            qos: u4:0,
        };

        let do_send_req = (state.fsm == Fsm::REQ);
        let tok2_1 = send_if(tok1_0, axi_ar_s, do_send_req, axi_ar);

        // RESP logic

        let do_recv_resp = state.fsm == Fsm::RESP;
        let (tok1_1, axi_r) = recv_if(tok0, axi_r_r, do_recv_resp, zero!<AxiR>());

        let is_last_group = (state.req_tran == u8:0);
        let is_last_tran = (state.tran_len == Addr:0);
        let req_tran = state.req_tran - u8:1;

        let low_lane = state.req_low_lane;
        let high_lane = if is_last_group { state.req_high_lane } else {Lane:3};
        let mask = lane_mask<DATA_W_DIV8>(low_lane, high_lane);

        let axi_st = AxiStream {
            data: axi_r.data,
            str: mask,
            keep: mask,
            last: axi_r.last,
            id: uN[ID_W]:0,
            dest: uN[DEST_W]:0,
        };
        let tok2_1 = send_if(tok1_1, axi_st_s, do_recv_resp, axi_st);

        match (state.fsm) {
            Fsm::IDLE => State {
                fsm: Fsm::REQ,
                tran_addr: req.addr,
                tran_len: req.len,
                ..zero!<State>()
            },
            Fsm::REQ => State {
                fsm: Fsm::RESP,
                req_tran: ar_len,
                tran_addr: next_tran_addr,
                tran_len: next_tran_len,
                req_low_lane: req_low_lane,
                req_high_lane: req_high_lane,
            },
            Fsm::RESP => {
                match (is_last_group, is_last_tran) {
                    (true, true) => zero!<State>(),
                    (true, _) => State {
                        fsm: Fsm::REQ,
                        ..state
                    },
                    (_, _) => State {
                        fsm: Fsm::RESP,
                        req_tran: req_tran,
                        req_low_lane: Lane:0,
                        ..state
                    }
                }
            },
            _ => zero!<State>(),
        }
    }
}

const INST_ADDR_W = u32:16;
const INST_DATA_W = u32:32;
const INST_DATA_W_DIV8 = INST_DATA_W / u32:8;
const INST_DEST_W = INST_DATA_W / u32:8;
const INST_ID_W = u32:4;

proc AxiReaderInst {
    type Req = TransferReq<INST_ADDR_W>;
    type AxiAr = axi::AxiAr<INST_ADDR_W, INST_ID_W>;
    type AxiR = axi::AxiR<INST_DATA_W, INST_ID_W>;
    type AxiStream = axi_st::AxiStream<INST_DATA_W, INST_DEST_W, INST_ID_W, INST_DATA_W_DIV8>;

    config(
        req_s: chan<Req> in,
        axi_ar_s: chan<AxiAr> out,
        axi_r_r: chan<AxiR> in,
        axi_st_s: chan<AxiStream> out) {

        spawn AxiReader<INST_ADDR_W, INST_DATA_W, INST_DEST_W, INST_ID_W>(
            req_s, axi_ar_s, axi_r_r, axi_st_s
        );
    }

    init { () }
    next(state: ()) {  }
}


const TEST_ADDR_W = u32:16;
const TEST_DATA_W = u32:32;
const TEST_DATA_W_DIV8 = TEST_DATA_W / u32:8;
const TEST_DEST_W = TEST_DATA_W / u32:8;
const TEST_ID_W = TEST_DATA_W / u32:8;

#[test_proc]
proc AxiReaderTest {
    type Req = TransferReq<TEST_ADDR_W>;
    type AxiAr = axi::AxiAr<TEST_ADDR_W, TEST_ID_W>;
    type AxiR = axi::AxiR<TEST_DATA_W, TEST_ID_W>;
    type AxiStream = axi_st::AxiStream<TEST_DATA_W, TEST_DEST_W, TEST_ID_W, TEST_DATA_W_DIV8>;

    type Addr = uN[TEST_ADDR_W];
    type Len = uN[TEST_ADDR_W];

    type AxiId = uN[TEST_ID_W];
    type AxiAddr = uN[TEST_ADDR_W];
    type AxiLen = u8;
    type AxiRegion = u4;
    type AxiSize = axi::AxiAxSize;
    type AxiBurst = axi::AxiAxBurst;
    type AxiCache = axi::AxiArCache;
    type AxiProt = u3;
    type AxiQos = u4;
    type AxiData = uN[TEST_DATA_W];
    type AxiReadResp = axi::AxiReadResp;

    type AxiStr = uN[TEST_DATA_W_DIV8];
    type AxiKeep = uN[TEST_DATA_W_DIV8];
    type AxiDest = uN[TEST_DEST_W];
    type AxiLast = u1;

    terminator: chan<bool> out;
    req_s: chan<Req> out;
    axi_ar_r: chan<AxiAr> in;
    axi_r_s: chan<AxiR> out;
    axi_st_r: chan<AxiStream> in;

    init {}

    config(terminator: chan<bool> out) {
        let (req_s, req_r) = chan<Req>("req");
        let (axi_ar_s, axi_ar_r) = chan<AxiAr>("axi_ar");
        let (axi_r_s, axi_r_r) = chan<AxiR>("axi_r");
        let (axi_st_s, axi_st_r) = chan<AxiStream>("axi_st");

        spawn AxiReader<TEST_ADDR_W, TEST_DATA_W, TEST_DEST_W, TEST_ID_W>(
            req_r, axi_ar_s, axi_r_r, axi_st_s);

        (terminator, req_s, axi_ar_r, axi_r_s, axi_st_r)
    }

    next (state: ()) {
        let tok = join();

        // Test 1: Single anligned transfer, all the bits used

        let req = Req { addr: Addr:0x1000, len: Len:4 };
        let tok = send(tok, req_s, req);

        let (tok, ar) = recv(tok, axi_ar_r);
        assert_eq(ar, AxiAr {
            id: AxiId:0,
            addr: AxiAddr:0x1000,
            region: AxiRegion:0x0,
            len: AxiLen:0x0,
            size: AxiSize::MAX_4B_TRANSFER,
            burst: AxiBurst::INCR,
            cache: AxiCache::DEV_NO_BUF,
            prot: AxiProt:0x0,
            qos: AxiQos:0x0
        });

        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x1122_3344,
            resp: AxiReadResp::OKAY,
            last: AxiLast:1,
        };
        let tok = send(tok, axi_r_s, r);

        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x1122_3344,
            str: AxiStr:0xF,
            keep: AxiKeep:0xF,
            last: AxiLast:true,
            id: AxiId:0,
            dest: AxiDest:0,
        });

        // Test2: Single aligned transfer with unused bits

        let req = Req { addr: Addr:0x1000, len: Len:2 };
        let tok = send(tok, req_s, req);

        let (tok, ar) = recv(tok, axi_ar_r);
        assert_eq(ar, AxiAr {
            id: AxiId:0,
            addr: AxiAddr:0x1000,
            region: AxiRegion:0x0,
            len: AxiLen:0x0,
            size: AxiSize::MAX_4B_TRANSFER,
            burst: AxiBurst::INCR,
            cache: AxiCache::DEV_NO_BUF,
            prot: AxiProt:0x0,
            qos: AxiQos:0x0
        });

        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x1122_3344,
            resp: AxiReadResp::OKAY,
            last: AxiLast:1,
        };
        let tok = send(tok, axi_r_s, r);

        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x1122_3344,
            str: AxiStr:0x3,
            keep: AxiKeep:0x3,
            last: AxiLast:true,
            id: AxiId:0,
            dest: AxiDest:0,
        });

        // Test3: Single unligned transfer, all the remaining bits used

        let req = Req { addr: Addr:0x123, len: Len:1 };
        let tok = send(tok, req_s, req);

        let (tok, ar) = recv(tok, axi_ar_r);
        assert_eq(ar, AxiAr {
            id: AxiId:0,
            addr: AxiAddr:0x120,
            region: AxiRegion:0x0,
            len: AxiLen:0x0,
            size: AxiSize::MAX_4B_TRANSFER,
            burst: AxiBurst::INCR,
            cache: AxiCache::DEV_NO_BUF,
            prot: AxiProt:0x0,
            qos: AxiQos:0x0
        });

        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x1122_3344,
            resp: AxiReadResp::OKAY,
            last: AxiLast:1,
        };
        let tok = send(tok, axi_r_s, r);

        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x1122_3344,
            str: AxiStr:0x8,
            keep: AxiKeep:0x8,
            last: AxiLast:true,
            id: AxiId:0,
            dest: AxiDest:0,
        });

        // Test4: Single unligned transfer with unused remaining bits

        let req = Req {addr: Addr:0x121, len: Len:1};
        let tok = send(tok, req_s, req);

        let (tok, ar) = recv(tok, axi_ar_r);
        assert_eq(ar, AxiAr {
            id: AxiId:0,
            addr: AxiAddr:0x120,
            region: AxiRegion:0x0,
            len: AxiLen:0x0,
            size: AxiSize::MAX_4B_TRANSFER,
            burst: AxiBurst::INCR,
            cache: AxiCache::DEV_NO_BUF,
            prot: AxiProt:0x0,
            qos: AxiQos:0x0
        });

        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x1122_3344,
            resp: AxiReadResp::OKAY,
            last: AxiLast:1,
        };
        let tok = send(tok, axi_r_s, r);

        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x1122_3344,
            str: AxiStr:0x2,
            keep: AxiKeep:0x2,
            last: AxiLast:true,
            id: AxiId:0,
            dest: AxiDest:0,
        });

        // Test 5: Multiple aligned transfers without crossing 4k boundary

        let req = Req { addr: Addr:0x2000, len: Len:16 };
        let tok = send(tok, req_s, req);

        let (tok, ar) = recv(tok, axi_ar_r);
        assert_eq(ar, AxiAr {
            id: AxiId:0,
            addr: AxiAddr:0x2000,
            region: AxiRegion:0x0,
            len: AxiLen:0x3,
            size: AxiSize::MAX_4B_TRANSFER,
            burst: AxiBurst::INCR,
            cache: AxiCache::DEV_NO_BUF,
            prot: AxiProt:0x0,
            qos: AxiQos:0x0
        });

        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x1122_3344,
            resp: AxiReadResp::OKAY,
            last: AxiLast:0,
        };
        let tok = send(tok, axi_r_s, r);
        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x5566_7788,
            resp: AxiReadResp::OKAY,
            last: AxiLast:0,
        };
        let tok = send(tok, axi_r_s, r);
        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x9900_AABB,
            resp: AxiReadResp::OKAY,
            last: AxiLast:0,
        };
        let tok = send(tok, axi_r_s, r);
        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0xCCDD_EEFF,
            resp: AxiReadResp::OKAY,
            last: AxiLast:1,
        };
        let tok = send(tok, axi_r_s, r);

        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x1122_3344,
            str: AxiStr:0xF,
            keep: AxiKeep:0xF,
            last: AxiLast:0,
            id: AxiId:0,
            dest: AxiDest:0,
        });
        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x5566_7788,
            str: AxiStr:0xF,
            keep: AxiKeep:0xF,
            last: AxiLast:0,
            id: AxiId:0,
            dest: AxiDest:0,
        });
        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x9900_AABB,
            str: AxiStr:0xF,
            keep: AxiKeep:0xF,
            last: AxiLast:0,
            id: AxiId:0,
            dest: AxiDest:0,
        });
        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0xCCDD_EEFF,
            str: AxiStr:0xF,
            keep: AxiKeep:0xF,
            last: AxiLast:1,
            id: AxiId:0,
            dest: AxiDest:0,
        });

        // Test 6: Multiple aligned transfers crossing 4k boundary

        let req = Req { addr: Addr:0xFF8, len: Len:16 };
        let tok = send(tok, req_s, req);

        let (tok, ar) = recv(tok, axi_ar_r);
        assert_eq(ar, AxiAr {
            id: AxiId:0,
            addr: AxiAddr:0xFF8,
            region: AxiRegion:0x0,
            len: AxiLen:0x1,
            size: AxiSize::MAX_4B_TRANSFER,
            burst: AxiBurst::INCR,
            cache: AxiCache::DEV_NO_BUF,
            prot: AxiProt:0x0,
            qos: AxiQos:0x0
        });

        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x1122_3344,
            resp: AxiReadResp::OKAY,
            last: AxiLast:0,
        };
        let tok = send(tok, axi_r_s, r);
        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x5566_7788,
            resp: AxiReadResp::OKAY,
            last: AxiLast:1,
        };
        let tok = send(tok, axi_r_s, r);

        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x1122_3344,
            str: AxiStr:0xF,
            keep: AxiKeep:0xF,
            last: AxiLast:0,
            id: AxiId:0,
            dest: AxiDest:0,
        });
        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x5566_7788,
            str: AxiStr:0xF,
            keep: AxiKeep:0xF,
            last: AxiLast:1,
            id: AxiId:0,
            dest: AxiDest:0,
        });

        let (tok, ar) = recv(tok, axi_ar_r);
        assert_eq(ar, AxiAr {
            id: AxiId:0,
            addr: AxiAddr:0x1000,
            region: AxiRegion:0x0,
            len: AxiLen:0x1,
            size: AxiSize::MAX_4B_TRANSFER,
            burst: AxiBurst::INCR,
            cache: AxiCache::DEV_NO_BUF,
            prot: AxiProt:0x0,
            qos: AxiQos:0x0
        });

        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x9900_AABB,
            resp: AxiReadResp::OKAY,
            last: AxiLast:0,
        };
        let tok = send(tok, axi_r_s, r);
        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0xCCDD_EEFF,
            resp: AxiReadResp::OKAY,
            last: AxiLast:1,
        };
        let tok = send(tok, axi_r_s, r);

        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x9900_AABB,
            str: AxiStr:0xF,
            keep: AxiKeep:0xF,
            last: AxiLast:0,
            id: AxiId:0,
            dest: AxiDest:0,
        });
        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0xCCDD_EEFF,
            str: AxiStr:0xF,
            keep: AxiKeep:0xF,
            last: AxiLast:1,
            id: AxiId:0,
            dest: AxiDest:0,
        });

        // Test 7: Multiple transfers starting from an unaligned address,
        // without crosing 4k boundary

        let req = Req { addr: Addr:0x2003, len: Len:16 };
        let tok = send(tok, req_s, req);

        let (tok, ar) = recv(tok, axi_ar_r);
        assert_eq(ar, AxiAr {
            id: AxiId:0,
            addr: AxiAddr:0x2000,
            region: AxiRegion:0x0,
            len: AxiLen:0x4,
            size: AxiSize::MAX_4B_TRANSFER,
            burst: AxiBurst::INCR,
            cache: AxiCache::DEV_NO_BUF,
            prot: AxiProt:0x0,
            qos: AxiQos:0x0
        });

        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x1122_3344,
            resp: AxiReadResp::OKAY,
            last: AxiLast:0,
        };
        let tok = send(tok, axi_r_s, r);
        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x5566_7788,
            resp: AxiReadResp::OKAY,
            last: AxiLast:0,
        };
        let tok = send(tok, axi_r_s, r);
        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x9900_AABB,
            resp: AxiReadResp::OKAY,
            last: AxiLast:0,
        };
        let tok = send(tok, axi_r_s, r);
        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0xCCDD_EEFF,
            resp: AxiReadResp::OKAY,
            last: AxiLast:0,
        };
        let tok = send(tok, axi_r_s, r);
        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x1122_3344,
            resp: AxiReadResp::OKAY,
            last: AxiLast:1,
        };
        let tok = send(tok, axi_r_s, r);

        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x1122_3344,
            str: AxiStr:0x8,
            keep: AxiKeep:0x8,
            last: AxiLast:0,
            id: AxiId:0,
            dest: AxiDest:0,
        });
        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x5566_7788,
            str: AxiStr:0xF,
            keep: AxiKeep:0xF,
            last: AxiLast:0,
            id: AxiId:0,
            dest: AxiDest:0,
        });
        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x9900_AABB,
            str: AxiStr:0xF,
            keep: AxiKeep:0xF,
            last: AxiLast:0,
            id: AxiId:0,
            dest: AxiDest:0,
        });
        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0xCCDD_EEFF,
            str: AxiStr:0xF,
            keep: AxiKeep:0xF,
            last: AxiLast:0,
            id: AxiId:0,
            dest: AxiDest:0,
        });
        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x1122_3344,
            str: AxiStr:0x7,
            keep: AxiKeep:0x7,
            last: AxiLast:1,
            id: AxiId:0,
            dest: AxiDest:0,
        });

        // Test 8: Multiple transfers starting from an unaligned address,
        // with crossing 4k boundary

        let req = Req { addr: Addr:0xFF6, len: Len:16 };
        let tok = send(tok, req_s, req);

        let (tok, ar) = recv(tok, axi_ar_r);
        assert_eq(ar, AxiAr {
            id: AxiId:0,
            addr: AxiAddr:0xFF4,
            region: AxiRegion:0x0,
            len: AxiLen:0x2,
            size: AxiSize::MAX_4B_TRANSFER,
            burst: AxiBurst::INCR,
            cache: AxiCache::DEV_NO_BUF,
            prot: AxiProt:0x0,
            qos: AxiQos:0x0
        });

        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x1122_3344,
            resp: AxiReadResp::OKAY,
            last: AxiLast:0,
        };
        let tok = send(tok, axi_r_s, r);
        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x5566_7788,
            resp: AxiReadResp::OKAY,
            last: AxiLast:0,
        };
        let tok = send(tok, axi_r_s, r);
        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x9900_AABB,
            resp: AxiReadResp::OKAY,
            last: AxiLast:1,
        };
        let tok = send(tok, axi_r_s, r);

        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x1122_3344,
            str: AxiStr:0xC,
            keep: AxiKeep:0xC,
            last: AxiLast:0,
            id: AxiId:0,
            dest: AxiDest:0,
        });
        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x5566_7788,
            str: AxiStr:0xF,
            keep: AxiKeep:0xF,
            last: AxiLast:0,
            id: AxiId:0,
            dest: AxiDest:0,
        });
        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x9900_AABB,
            str: AxiStr:0xF,
            keep: AxiKeep:0xF,
            last: AxiLast:1,
            id: AxiId:0,
            dest: AxiDest:0,
        });

        let (tok, ar) = recv(tok, axi_ar_r);
        assert_eq(ar, AxiAr {
            id: AxiId:0,
            addr: AxiAddr:0x1000,
            region: AxiRegion:0x0,
            len: AxiLen:0x1,
            size: AxiSize::MAX_4B_TRANSFER,
            burst: AxiBurst::INCR,
            cache: AxiCache::DEV_NO_BUF,
            prot: AxiProt:0x0,
            qos: AxiQos:0x0
        });

        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0xCCDD_EEFF,
            resp: AxiReadResp::OKAY,
            last: AxiLast:0,
        };
        let tok = send(tok, axi_r_s, r);
        let r = AxiR {
            id: AxiId:0,
            data: AxiData:0x1122_3344,
            resp: AxiReadResp::OKAY,
            last: AxiLast:1,
        };
        let tok = send(tok, axi_r_s, r);

        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0xCCDD_EEFF,
            str: AxiStr:0xF,
            keep: AxiKeep:0xF,
            last: AxiLast:0,
            id: AxiId:0,
            dest: AxiDest:0,
        });
        let (tok, st) = recv(tok, axi_st_r);
        assert_eq(st, AxiStream {
            data: AxiData:0x1122_3344,
            str: AxiStr:0x3,
            keep: AxiKeep:0x3,
            last: AxiLast:1,
            id: AxiId:0,
            dest: AxiDest:0,
        });

        // Test 9: Multiple transfers starting from aligned address,
        // without crossing 4k boundary, but longer than max burst size

        let req = Req { addr: Addr:0x1000, len: Len:0x2000 };
        let tok = send(tok, req_s, req);

        let (tok, ar) = recv(tok, axi_ar_r);
        assert_eq(ar, AxiAr {
            id: AxiId:0,
            addr: AxiAddr:0x1000,
            region: AxiRegion:0x0,
            len: AxiLen:0xFF,
            size: AxiSize::MAX_4B_TRANSFER,
            burst: AxiBurst::INCR,
            cache: AxiCache::DEV_NO_BUF,
            prot: AxiProt:0x0,
            qos: AxiQos:0x0
        });

        send(tok, terminator, true);
    }
}
