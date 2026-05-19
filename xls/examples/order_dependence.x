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

    config(req_r: chan<u32> in, resp_s: chan<u32> out, err: chan<u32> out) {
        (req_r, resp_s, err)
    }

    init {  }

    next(state: ()) {
        let (tok, _req0) = recv(join(), req_r);
        let tok = send(tok, resp_s, u32:0);
        // Oh no, a proc is unimplemented!
        let tok = send(tok, err, u32:500);
    }
}

proc Worker {
    req_r: chan<u32> in;
    resp_s: chan<u32> out;
    err: chan<u32> out;

    config(req_r: chan<u32> in, resp_s: chan<u32> out, err: chan<u32> out) {
        (req_r, resp_s, err)
    }

    init {  }

    next(state: ()) {
        let (tok, req) = recv(join(), req_r);
        let tok = send(tok, resp_s, req + u32:5);
        // Everything is alright.
        let tok = send(tok, err, u32:200);
    }
}

proc Toppy {
    config(req_r: chan<u32> in, resp_s: chan<u32> out, err: chan<u32> out) {
        // Bad example - assigning single channel to multiple procs.
        // Switch spawn order to receive different results in `Tester`.
        spawn BuggyWorker(req_r, resp_s, err);
        spawn Worker(req_r, resp_s, err);
        ()
    }

    init {  }

    next(state: ()) {  }
}

#[test_proc]
proc Tester {
    req_s: chan<u32> out;
    resp_r: chan<u32> in;
    err: chan<u32> in;
    terminator: chan<bool> out;

    config(terminator: chan<bool> out) {
        let (req_s, req_r) = chan<u32>("req");
        let (resp_s, resp_r) = chan<u32>("resp");
        let (err_s, err_r) = chan<u32>("err");
        spawn Toppy(req_r, resp_s, err_s);

        (req_s, resp_r, err_r, terminator)
    }

    init {  }

    next(_: ()) {
        let tok = send(join(), req_s, u32:16);

        let (tok, resp) = recv(tok, resp_r);
        trace_fmt!("Received resp: {}", resp);

        let (tok, err) = recv(tok, err);
        trace_fmt!("Received err: {}", err);

        let tok = send(tok, terminator, true);
    }
}
