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

proc BuggyWorker {
    req_r: chan<u32> in;
    resp_s: chan<u32> out;
    err: chan<u32> out;

    config(req_r: chan<u32> in, resp_s: chan<u32> out,
           err: chan<u32> out) {
        (req_r, resp_s, err)
    }

    init {  }

    next(state: ()) {
        let (tok, req0, valid0) = recv_non_blocking(
            join(), req_r, u32:0);
        // Oh no, a proc is unimplemented!
        let tok = send(tok, err, u32:500);
    }
}

proc Worker {
    req_r: chan<u32> in;
    resp_s: chan<u32> out;
    err: chan<u32> out;

    config(req_r: chan<u32> in, resp_s: chan<u32> out,
           err: chan<u32> out) {
        (req_r, resp_s, err)
    }

    init {  }

    next(state: ()) {
        let (tok, req) = recv(join(), req_r);
        let tok = send(tok, resp_s, req + u32:5);
    }
}

proc Toppy {
    req_r: chan<u32>[2] in;
    resp_s: chan<u32>[2] out;
    err: chan<u32> out;
    config(req_r: chan<()>[2] in, resp_s: chan<u32>[2] out,
           err: chan<u32> out) {
        spawn Worker(req_r[0], resp_s[0], err);
        spawn BuggyWorker(req_r[1], resp_s[1], err);
        ()
    }

    init {  }

    next(state: ()) {  }
}

#[test_proc]
proc Tester {
    req_s: chan<()>[2] out;
    resp_r: chan<u32>[2] in;
    err: chan<u32> in;
    terminator: chan<bool> out;

    config(terminator: chan<bool> out) {
        let (req_s, req_r) = chan<()>[2]("req");
        let (resp_s, resp_r) = chan<u32>[2]("resp");
        let (err_s, err_r) = chan<u32>("err");
        spawn Toppy(req_r, resp_s, err_s);

        (req_s, resp_r, err_r, terminator)
    }

    init {  }

    next(_: ()) {
        let tok1 = send(join(), req_s[1], u32:16);

        let (tok2, err, err_valid) = recv_non_blocking(tok1, err, u32:0);
        assert_eq(err == u32:500);
        assert_eq(err_valid);

        let tok0 = send(join(), req_s[0], u32:8);

        let tok = send(tok, terminator, true);
    }
}
