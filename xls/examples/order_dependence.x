// Copyright 2026 The XLS Authors
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

#![feature(type_inference_v2)]

// This proc will receive only one packet from a single channel, depending on
// which `recv_if_non_blocking` operation was first executed.
proc Receiver {
    req_r: chan<u32>[2] in;
    resp_s: chan<u32>[2] out;
    config(req_r: chan<()>[2] in, resp_s: chan<u32>[2] out) {
        (req_r, resp_s)
    }

    init { false }

    next(received: bool) {
        // First set of operations.
        let (tok0, req0, valid0) = recv_if_non_blocking(
            join(), req_r[0], !received, u32:0);
        let tok0 = send(tok0, resp_s[0], req0);
        let received = valid0 || received;

        // Second set of operations.
        let (tok1, req1, valid1) = recv_if_non_blocking(
            join(), req_r[1], !received, u32:0);
        let tok1 = send(tok1, resp_s[1], req1);
        let received = valid1 || received;
        received
    }
}

#[test_proc]
proc Sender {
    req_s: chan<()>[2] out;
    resp_r: chan<u32>[2] in;
    terminator: chan<bool> out;

    config(terminator: chan<bool> out) {
        let (req_s, req_r) = chan<()>[2]("req");
        let (resp_s, resp_r) = chan<u32>[2]("resp");
        spawn Receiver(req_r, resp_s);

        (req_s, resp_r, terminator)
    }

    init {  }

    next(_: ()) {
        let tok0 = send(join(), req_s[0], u32:8);
        let (tok0, resp0) = recv(tok, resp_r[0]);
        
        let tok1 = send(join(), req_s[1], u32:16);
        let (tok1, resp1) = recv(tok1, resp_r[1]);

        let tok = send(tok, terminator, true);
    }
}
