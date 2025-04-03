// Copyright 2025 The XLS Authors
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

struct SimpleMux2State<
    N: u32,
    N_WIDTH: u32 = {std::clog2(N + u32:1)}
> {
    sel: uN[N_WIDTH],
    active: bool,
}

pub proc SimpleMux2<
    N: u32,
    INIT_SEL: u32 = {u32:0},
    N_WIDTH: u32 = {std::clog2(N + u32:1)}
> {
    type Sel = uN[N_WIDTH];
    type Req = u32;
    type Resp = u32;
    type State = SimpleMux2State<N>;

    sel_req_r: chan<Sel> in;
    sel_resp_s: chan<()> out;

    n_req_r: chan<Req>[N] in;
    n_resp_s: chan<Resp>[N] out;

    req_s: chan<Req> out;
    resp_r: chan<Resp> in;

    config(
        sel_req_r: chan<Sel> in,
        sel_resp_s: chan<()> out,

        n_req_r: chan<Req>[N] in,
        n_resp_s: chan<Resp>[N] out,

        req_s: chan<Req> out,
        resp_r: chan<Resp> in,
    ) {
        (
           sel_req_r, sel_resp_s,
           n_req_r, n_resp_s,
           req_s, resp_r,
        )
    }

    init {
        State {
            sel: checked_cast<Sel>(INIT_SEL),
            active: false,
        }
    }

    next(state: State) {
        let tok0 = join();

        let (tok1_0, n_req, n_req_valid) = unroll_for!(i, (tok, req, req_valid)): (Sel, (token, Req, bool)) in range(Sel:0, N as Sel) {
            let (tok, r, v) = recv_if_non_blocking(tok, n_req_r[i], state.sel == i && !state.active, zero!<Req>());
            if v { (tok, r, true) } else { (tok, req, req_valid) }
        }((tok0, zero!<Req>(), false));
        let tok2_0 = send_if(tok1_0, req_s, n_req_valid, n_req);

        let active = state.active || n_req_valid;
        let (tok2_1, resp, resp_valid) = recv_if_non_blocking(tok1_0, resp_r, active, zero!<Resp>());
        let tok3_0 = unroll_for! (i, tok): (Sel, token) in range(Sel:0, N as Sel) {
            send_if(tok, n_resp_s[i], state.sel == i && resp_valid, resp)
        }(tok2_1);

        let active = (state.active || n_req_valid) && !resp_valid;
        let (tok3_1, sel, sel_valid) = recv_if_non_blocking(tok2_1, sel_req_r, !active, state.sel);
        let tok4_0 = send_if(tok3_1, sel_resp_s, !active && sel_valid, ());

        State { active, sel }
    }
}


const INST_N = u32:10;
const INST_N_WIDTH = std::clog2(INST_N + u32:1);

pub proc SimpleMux2Inst {
    type Sel = uN[INST_N_WIDTH];
    type Req = u32;
    type Resp = u32;

    init {}
    config(
        sel_req_r: chan<Sel> in,
        sel_resp_s: chan<()> out,
        n_req_r: chan<Req>[INST_N] in,
        n_resp_s: chan<Resp>[INST_N] out,
        req_s: chan<Req> out,
        resp_r: chan<Resp> in,
     ) {

        spawn SimpleMux2<INST_N>(
            sel_req_r, sel_resp_s,
            n_req_r, n_resp_s,
            req_s, resp_r,
        );

        ()
    }

    next(state: ()) {}
}


const TEST_N = u32:5;
const TEST_N_WIDTH = std::clog2(TEST_N + u32:1);

#[test_proc]
proc SimpleMux2Test {
    type Sel = uN[TEST_N_WIDTH];
    type Req = u32;
    type Resp = u32;

    terminator: chan<bool> out;

    sel_req_s: chan<Sel> out;
    sel_resp_r: chan<()> in;

    n_req_s: chan<Req>[TEST_N] out;
    n_resp_r: chan<Resp>[TEST_N] in;

    req_r: chan<Req> in;
    resp_s: chan<Resp> out;

    init {}
    config(terminator: chan<bool> out,) {

        let (sel_req_s, sel_req_r) = chan<Sel>("sel_req");
        let (sel_resp_s, sel_resp_r) = chan<()>("sel_resp");

        let (n_req_s, n_req_r) = chan<Req>[TEST_N]("n_req");
        let (n_resp_s, n_resp_r) = chan<Resp>[TEST_N]("n_resp");

        let (req_s, req_r) = chan<Req>("req");
        let (resp_s, resp_r) = chan<Resp>("resp");

        spawn SimpleMux2<TEST_N>(
            sel_req_r, sel_resp_s,
            n_req_r, n_resp_s,
            req_s, resp_r,
        );

        (
            terminator,
            sel_req_s, sel_resp_r,
            n_req_s, n_resp_r,
            req_r, resp_s,
        )
    }

    next(state: ()) {
        let tok = join();

        let tok = send(tok, sel_req_s, Sel:3);
        let (tok, _) = recv(tok, sel_resp_r);

        let tok = send(tok, n_req_s[3], zero!<Req>());
        let (tok, _) = recv(tok, req_r);

        // Cannot switch during the transmission
        let tok = send(tok, sel_req_s, Sel:1);

        let tok = send(tok, resp_s, zero!<Resp>());
        let (tok, _) = recv(tok, n_resp_r[3]);

        // Now we should be able to receive the select
        let (tok, _) = recv(tok, sel_resp_r);

        let tok = send(tok, n_req_s[1], zero!<Req>());
        let (tok, _) = recv(tok, req_r);

        let tok = send(tok, resp_s, zero!<Resp>());
        let (tok, _) = recv(tok, n_resp_r[1]);

        send(tok, terminator, true);
    }
}
