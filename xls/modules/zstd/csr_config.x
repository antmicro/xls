// Copyrijht 2023-2024 The XLS Authors
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

// This file contains implementation of a proc that handles CSRs. It provides
// an AXI interface for reading and writing the values as well as separate
// request/response channels. Apart from that it has an output channel which
// notifies aboud changes made to CSRs.

import std;
import xls.modules.zstd.memory.axi;

pub struct CsrRdReq<LOG2_REGS_N: u32> {
    csr: uN[LOG2_REGS_N],
}

pub struct CsrRdResp<LOG2_REGS_N: u32, DATA_W: u32> {
    csr: uN[LOG2_REGS_N],
    value: uN[DATA_W],
}

pub struct CsrWrReq<LOG2_REGS_N: u32, DATA_W: u32> {
    csr: uN[LOG2_REGS_N],
    value: uN[DATA_W],
}

pub struct CsrWrResp { }

pub struct CsrChange<LOG2_REGS_N: u32> {
    csr: uN[LOG2_REGS_N],
}

struct CsrConfigState<ID_W: u32, ADDR_W:u32, DATA_W:u32, REGS_N: u32> {
    register_file: uN[DATA_W][REGS_N],
    w_id: uN[ID_W],
    w_addr: uN[ADDR_W],
    r_id: uN[ID_W],
    r_addr: uN[ADDR_W],
}

pub proc CsrConfig<
    ID_W: u32, ADDR_W: u32, DATA_W: u32, REGS_N: u32,
    //REGS_INIT: u64[64] = {u64[64]:[u64:0, ...]},
    DATA_W_DIV8: u32 = { DATA_W / u32:8 },
    LOG2_REGS_N: u32 = { std::clog2(REGS_N) },
> {
    type AxiAw = axi::AxiAw<ADDR_W, ID_W>;
    type AxiW = axi::AxiW<DATA_W, DATA_W_DIV8>;
    type AxiB = axi::AxiB<ID_W>;
    type AxiAr = axi::AxiAr<ADDR_W, ID_W>;
    type AxiR = axi::AxiR<DATA_W, ID_W>;

    type RdReq = CsrRdReq<LOG2_REGS_N>;
    type RdResp = CsrRdResp<LOG2_REGS_N, DATA_W>;
    type WrReq = CsrWrReq<LOG2_REGS_N, DATA_W>;
    type WrResp = CsrWrResp;
    type Change = CsrChange<LOG2_REGS_N>;

    type State = CsrConfigState<ID_W, ADDR_W, DATA_W, REGS_N>;
    type Data = uN[DATA_W];
    type RegN = uN[LOG2_REGS_N];

    axi_aw_r: chan<AxiAw> in;
    axi_w_r: chan<AxiW> in;
    axi_b_s: chan<AxiB> out;
    axi_ar_r: chan<AxiAr> in;
    axi_r_s: chan<AxiR> out;

    csr_rd_req_r: chan<RdReq> in;
    csr_rd_resp_s: chan<RdResp> out;
    csr_wr_req_r: chan<WrReq> in;
    csr_wr_resp_s: chan<WrResp> out;
    csr_change_s: chan<Change> out;

    config (
        axi_aw_r: chan<AxiAw> in,
        axi_w_r: chan<AxiW> in,
        axi_b_s: chan<AxiB> out,
        axi_ar_r: chan<AxiAr> in,
        axi_r_s: chan<AxiR> out,

        csr_rd_req_r: chan<RdReq> in,
        csr_rd_resp_s: chan<RdResp> out,
        csr_wr_req_r: chan<WrReq> in,
        csr_wr_resp_s: chan<WrResp> out,
        csr_change_s: chan<Change> out,
    ) {
        (
            axi_aw_r, axi_w_r, axi_b_s,
            axi_ar_r, axi_r_s,
            csr_rd_req_r, csr_rd_resp_s,
            csr_wr_req_r, csr_wr_resp_s,
            csr_change_s,
        )
    }

    init {
        zero!<State>()
    }

    next (state: State) {
        let register_file = state.register_file;

        // write to CSR via AXI
        let (tok, axi_aw, axi_aw_valid) = recv_non_blocking(join(), axi_aw_r, zero!<AxiAw>());

        // validate axi aw
        assert!(!(axi_aw_valid && axi_aw.addr as u32 >= REGS_N), "invalid_aw_addr");
        assert!(!(axi_aw_valid && axi_aw.len != u8:0), "invalid_aw_len");

        let (w_id, w_addr) = if axi_aw_valid {
            (axi_aw.id, axi_aw.addr)
        } else {
            (state.w_id, state.w_addr)
        };

        let (tok, axi_w, axi_w_valid) = recv_non_blocking(tok, axi_w_r, zero!<AxiW>());

        // update register value
        let register_file = if axi_w_valid {
            let (w_data, _, _) = for (i, (w_data, strb, mask)): (u32, (uN[DATA_W], uN[DATA_W_DIV8], uN[DATA_W])) in range(u32:0, DATA_W_DIV8) {
                let w_data = if axi_w.strb as u1 {
                    w_data | (axi_w.data & mask)
                } else {
                    w_data
                };
                (
                    w_data,
                    strb >> u32:1,
                    mask << u32:8,
                )
            }((uN[DATA_W]:0, axi_w.strb, uN[DATA_W]:0xFF));
            update(register_file, w_addr, w_data)
        } else {
            state.register_file
        };

        send_if(tok, axi_b_s, axi_w_valid, AxiB {
            resp: axi::AxiWriteResp::OKAY,
            id: w_id,
        });

        // write to CSR
        let (tok, csr_wr_req, csr_wr_req_valid) = recv_if_non_blocking(tok, csr_wr_req_r, !axi_aw_valid, zero!<WrReq>());

        let register_file = if csr_wr_req_valid {
            update(register_file, csr_wr_req.csr as u32, csr_wr_req.value)
        } else {
            register_file
        };

        let tok = send_if(tok, csr_wr_resp_s, csr_wr_req_valid, WrResp {});

        // send change notification
        let csr_updated = if axi_w_valid {
            w_addr as RegN
        } else {
            csr_wr_req.csr
        };
        let tok = send_if(tok, csr_change_s, csr_wr_req_valid | axi_w_valid, Change { csr: csr_updated });

        // read from CSR via AXI
        let (tok, axi_ar, axi_ar_valid) = recv_non_blocking(join(), axi_ar_r, zero!<AxiAr>());

        // validate ar bundle
        assert!(!(axi_ar_valid && axi_ar.addr as u32 >= REGS_N), "invalid_ar_addr");
        assert!(!(axi_ar_valid && axi_ar.len != u8:0), "invalid_ar_len");

        let (r_id, r_addr) = if axi_ar_valid { (axi_ar.id, axi_ar.addr) } else { (state.r_id, state.r_addr) };

        send_if(tok, axi_r_s, axi_ar_valid, AxiR {
            id: r_id,
            data: register_file[r_addr],
            resp: axi::AxiReadResp::OKAY,
            last: true,
        });

        // read from CSR
        let (tok, csr_rd_req, csr_req_valid) = recv_non_blocking(join(), csr_rd_req_r, zero!<RdReq>());

        send_if(tok, csr_rd_resp_s, csr_req_valid, RdResp {
            csr: csr_rd_req.csr,
            value: register_file[csr_rd_req.csr as u32],
        });

        State {
            w_id: w_id,
            w_addr: w_addr,
            r_id: r_id,
            r_addr: r_addr,
            register_file: register_file,
        }
    }
}

const INST_ID_W = u32:32;
const INST_DATA_W = u32:32;
const INST_ADDR_W = u32:2;
const INST_REGS_N = u32:4;
const INST_DATA_W_DIV8 = INST_DATA_W / u32:8;
const INST_LOG2_REGS_N = std::clog2(INST_REGS_N);

proc CsrConfigInst {
    type InstAxiAw = axi::AxiAw<INST_ADDR_W, INST_ID_W>;
    type InstAxiW = axi::AxiW<INST_DATA_W, INST_DATA_W_DIV8>;
    type InstAxiB = axi::AxiB<INST_ID_W>;
    type InstAxiAr = axi::AxiAr<INST_ADDR_W, INST_ID_W>;
    type InstAxiR = axi::AxiR<INST_DATA_W, INST_ID_W>;

    type InstCsrRdReq = CsrRdReq<INST_LOG2_REGS_N>;
    type InstCsrRdResp = CsrRdResp<INST_LOG2_REGS_N, INST_DATA_W>;
    type InstCsrWrReq = CsrWrReq<INST_LOG2_REGS_N, INST_DATA_W>;
    type InstCsrWrResp = CsrWrResp;
    type InstCsrChange = CsrChange<INST_LOG2_REGS_N>;

    config(
        axi_aw_r: chan<InstAxiAw> in,
        axi_w_r: chan<InstAxiW> in,
        axi_b_s: chan<InstAxiB> out,
        axi_ar_r: chan<InstAxiAr> in,
        axi_r_s: chan<InstAxiR> out,


        csr_rd_req_r: chan<InstCsrRdReq> in,
        csr_rd_resp_s: chan<InstCsrRdResp> out,
        csr_wr_req_r: chan<InstCsrWrReq> in,
        csr_wr_resp_s: chan<InstCsrWrResp> out,
        csr_change_s: chan<InstCsrChange> out,
    ) {
        spawn CsrConfig<INST_ID_W, INST_ADDR_W, INST_DATA_W, INST_REGS_N> (
            axi_aw_r, axi_w_r, axi_b_s,
            axi_ar_r, axi_r_s,
            csr_rd_req_r, csr_rd_resp_s,
            csr_wr_req_r, csr_wr_resp_s,
            csr_change_s,
        );
    }

    init { }

    next (state: ()) { }
}

const TEST_ID_W = u32:32;
const TEST_DATA_W = u32:32;
const TEST_ADDR_W = u32:2;
const TEST_REGS_N = u32:4;
const TEST_DATA_W_DIV8 = TEST_DATA_W / u32:8;
const TEST_LOG2_REGS_N = std::clog2(TEST_REGS_N);

type TestCsr = uN[TEST_LOG2_REGS_N];
type TestValue = uN[TEST_DATA_W];

struct TestData {
    csr: uN[TEST_LOG2_REGS_N],
    value: uN[TEST_DATA_W],
}

const TEST_DATA = TestData[20]:[
    TestData{ csr: TestCsr:0, value: TestValue:0xca32_9f4a },
    TestData{ csr: TestCsr:1, value: TestValue:0x0fb3_fa42 },
    TestData{ csr: TestCsr:2, value: TestValue:0xe7ee_da41 },
    TestData{ csr: TestCsr:3, value: TestValue:0xef51_f98c },
    TestData{ csr: TestCsr:0, value: TestValue:0x97a3_a2d2 },
    TestData{ csr: TestCsr:0, value: TestValue:0xea06_e94b },
    TestData{ csr: TestCsr:1, value: TestValue:0x5fac_17ce },
    TestData{ csr: TestCsr:3, value: TestValue:0xf9d8_9938 },
    TestData{ csr: TestCsr:2, value: TestValue:0xc262_2d2e },
    TestData{ csr: TestCsr:2, value: TestValue:0xb4dd_424e },
    TestData{ csr: TestCsr:1, value: TestValue:0x01f9_b9e4 },
    TestData{ csr: TestCsr:1, value: TestValue:0x3020_6eec },
    TestData{ csr: TestCsr:3, value: TestValue:0x3124_87b5 },
    TestData{ csr: TestCsr:0, value: TestValue:0x0a49_f5e3 },
    TestData{ csr: TestCsr:2, value: TestValue:0xde3b_5d0f },
    TestData{ csr: TestCsr:3, value: TestValue:0x5948_c1b3 },
    TestData{ csr: TestCsr:0, value: TestValue:0xa26d_851f },
    TestData{ csr: TestCsr:3, value: TestValue:0x3fa9_59c0 },
    TestData{ csr: TestCsr:1, value: TestValue:0x4efd_dd09 },
    TestData{ csr: TestCsr:1, value: TestValue:0x6d75_058a },
];

#[test_proc]
proc CsrConfig_test {
    type TestAxiAw = axi::AxiAw<TEST_ADDR_W, TEST_ID_W>;
    type TestAxiW = axi::AxiW<TEST_DATA_W, TEST_DATA_W_DIV8>;
    type TestAxiB = axi::AxiB<TEST_ID_W>;
    type TestAxiAr = axi::AxiAr<TEST_ADDR_W, TEST_ID_W>;
    type TestAxiR = axi::AxiR<TEST_DATA_W, TEST_ID_W>;


    type TestCsrRdReq = CsrRdReq<TEST_LOG2_REGS_N>;
    type TestCsrRdResp = CsrRdResp<TEST_LOG2_REGS_N, TEST_DATA_W>;
    type TestCsrWrReq = CsrWrReq<TEST_LOG2_REGS_N, TEST_DATA_W>;
    type TestCsrWrResp = CsrWrResp;
    type TestCsrChange = CsrChange<TEST_LOG2_REGS_N>;

    terminator: chan<bool> out;

    axi_aw_s: chan<TestAxiAw> out;
    axi_w_s: chan<TestAxiW> out;
    axi_b_r: chan<TestAxiB> in;
    axi_ar_s: chan<TestAxiAr> out;
    axi_r_r: chan<TestAxiR> in;

    csr_rd_req_s: chan<TestCsrRdReq> out;
    csr_rd_resp_r: chan<TestCsrRdResp> in;
    csr_wr_req_s: chan<TestCsrWrReq> out;
    csr_wr_resp_r: chan<TestCsrWrResp> in;
    csr_change_r: chan<TestCsrChange> in;

    config (terminator: chan<bool> out) {
        let (axi_aw_s, axi_aw_r) = chan<TestAxiAw>("axi_aw");
        let (axi_w_s, axi_w_r) = chan<TestAxiW>("axi_w");
        let (axi_b_s, axi_b_r) = chan<TestAxiB>("axi_b");
        let (axi_ar_s, axi_ar_r) = chan<TestAxiAr>("axi_ar");
        let (axi_r_s, axi_r_r) = chan<TestAxiR>("axi_r");

        let (csr_rd_req_s, csr_rd_req_r) = chan<TestCsrRdReq>("csr_rd_req");
        let (csr_rd_resp_s, csr_rd_resp_r) = chan<TestCsrRdResp>("csr_rd_resp");

        let (csr_wr_req_s, csr_wr_req_r) = chan<TestCsrWrReq>("csr_wr_req");
        let (csr_wr_resp_s, csr_wr_resp_r) = chan<TestCsrWrResp>("csr_wr_resp");

        let (csr_change_s, csr_change_r) = chan<TestCsrChange>("csr_change");

        spawn CsrConfig<TEST_ID_W, TEST_ADDR_W, TEST_DATA_W, TEST_REGS_N> (
            axi_aw_r, axi_w_r, axi_b_s,
            axi_ar_r, axi_r_s,
            csr_rd_req_r, csr_rd_resp_s,
            csr_wr_req_r, csr_wr_resp_s,
            csr_change_s,
        );

        (
            terminator,
            axi_aw_s, axi_w_s, axi_b_r,
            axi_ar_s, axi_r_r,
            csr_rd_req_s, csr_rd_resp_r,
            csr_wr_req_s, csr_wr_resp_r,
            csr_change_r,
        )
    }

    init { }

    next (state: ()) {
        let expected_values = zero!<uN[TEST_DATA_W][TEST_REGS_N]>();

        // test writing via AXI
        let (tok, expected_values) = for ((i, test_data), (tok, expected_values)): ((u32, TestData), (token, uN[TEST_DATA_W][TEST_REGS_N])) in enumerate(TEST_DATA) {
            // write CSR via AXI
            let axi_aw = TestAxiAw {
                id: i as uN[TEST_ID_W],
                addr: test_data.csr as uN[TEST_ADDR_W],
                size: axi::AxiAxSize::MAX_4B_TRANSFER,
                len: u8:0,
                burst: axi::AxiAxBurst::FIXED,
            };
            let tok = send(tok, axi_aw_s, axi_aw);
            trace_fmt!("Sent #{} aw bundle {:#x}", i + u32:1, axi_aw);

            let axi_w = TestAxiW {
                data: test_data.value,
                strb: !uN[TEST_DATA_W_DIV8]:0,
                last: true,
            };
            let tok = send(tok, axi_w_s, axi_w);
            trace_fmt!("Sent #{} w bundle {:#x}", i + u32:1, axi_w);

            let (tok, axi_b) = recv(tok, axi_b_r);

            assert_eq(axi::AxiWriteResp::OKAY, axi_b.resp);
            assert_eq(i as uN[TEST_ID_W], axi_b.id);

            // read CSR change
            let (tok, csr_change) = recv(tok, csr_change_r);
            trace_fmt!("Received #{} CSR change {:#x}", i + u32:1, csr_change);

            assert_eq(test_data.csr, csr_change.csr);

            // update expected values
            let expected_values = update(expected_values, test_data.csr as u32, test_data.value);

            let tok = for (test_csr, tok): (u32, token) in u32:0..u32:4 {
                // read CSRs via AXI
                let axi_ar = TestAxiAr {
                    id: i as uN[TEST_ID_W],
                    addr: test_csr as uN[TEST_ADDR_W],
                    len: u8:0,
                    ..zero!<TestAxiAr>()
                };
                let tok = send(tok, axi_ar_s, axi_ar);
                trace_fmt!("Sent #{} {:#x}", i + u32:1, axi_ar);

                let (tok, axi_r) = recv(tok, axi_r_r);
                trace_fmt!("Received #{} {:#x}", i + u32:1, axi_r);

                assert_eq(i as uN[TEST_ID_W], axi_r.id);
                assert_eq(expected_values[test_csr as u32], axi_r.data);
                assert_eq(axi::AxiReadResp::OKAY, axi_r.resp);
                assert_eq(true, axi_r.last);

                // send read request
                let csr_rd_req = CsrRdReq { csr: test_csr as TestCsr };
                let tok = send(tok, csr_rd_req_s, csr_rd_req);
                trace_fmt!("Sent #{} CSR read request {:#x}", i + u32:1, csr_rd_req);

                let (tok, csr_rd_resp) = recv(tok, csr_rd_resp_r);
                trace_fmt!("Received #{} CSR read response {:#x}", i + u32:1, csr_rd_resp);

                assert_eq(test_csr as TestCsr, csr_rd_resp.csr);
                assert_eq(expected_values[test_csr as u32], csr_rd_resp.value);

                tok
            }(tok);

            (tok, expected_values)
        }((join(), expected_values));

        // test writing via request channel
        let (tok, _) = for ((i, test_data), (tok, expected_values)): ((u32, TestData), (token, uN[TEST_DATA_W][TEST_REGS_N])) in enumerate(TEST_DATA) {
            // write CSR via request channel
            let csr_wr_req = TestCsrWrReq {
                csr: test_data.csr,
                value: test_data.value,
            };
            let tok = send(tok, csr_wr_req_s, csr_wr_req);
            trace_fmt!("Sent #{} CSR write request {:#x}", i + u32:1, csr_wr_req);

            let (tok, csr_wr_resp) = recv(tok, csr_wr_resp_r);
            trace_fmt!("Received #{} CSR write response {:#x}", i + u32:1, csr_wr_resp);

            // read CSR change
            let (tok, csr_change) = recv(tok, csr_change_r);
            trace_fmt!("Received #{} CSR change {:#x}", i + u32:1, csr_change);

            assert_eq(test_data.csr, csr_change.csr);

            // update expected values
            let expected_values = update(expected_values, test_data.csr as u32, test_data.value);

            let tok = for (test_csr, tok): (u32, token) in u32:0..u32:4 {
                // read CSRs via AXI
                let axi_ar = TestAxiAr {
                    id: i as uN[TEST_ID_W],
                    addr: test_csr as uN[TEST_ADDR_W],
                    len: u8:0,
                    ..zero!<TestAxiAr>()
                };
                let tok = send(tok, axi_ar_s, axi_ar);
                trace_fmt!("Sent #{} {:#x}", i + u32:1, axi_ar);

                let (tok, axi_r) = recv(tok, axi_r_r);
                trace_fmt!("Received #{} {:#x}", i + u32:1, axi_r);

                assert_eq(i as uN[TEST_ID_W], axi_r.id);
                assert_eq(expected_values[test_csr as u32], axi_r.data);
                assert_eq(axi::AxiReadResp::OKAY, axi_r.resp);
                assert_eq(true, axi_r.last);

                // send read request
                let csr_rd_req = CsrRdReq { csr: test_csr as TestCsr};
                let tok = send(tok, csr_rd_req_s, csr_rd_req);
                trace_fmt!("Sent #{} CSR read request {:#x}", i + u32:1, csr_rd_req);

                let (tok, csr_rd_resp) = recv(tok, csr_rd_resp_r);
                trace_fmt!("Received #{} CSR read response {:#x}", i + u32:1, csr_rd_resp);

                assert_eq(test_csr as TestCsr, csr_rd_resp.csr);
                assert_eq(expected_values[test_csr as u32], csr_rd_resp.value);

                tok
            }(tok);

            (tok, expected_values)
        }((join(), expected_values));

        send(tok, terminator, true);
    }
}
