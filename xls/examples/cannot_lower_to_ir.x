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

// From `ProcWithUnconvertibleConfigGivesUsefulError` IR converter test
// as an example of proc that cannot be converted to IR.
proc Adder {
  req_r: chan<u32> in;
  resp_s: chan<u32> out;

  config(req_r: chan<u32> in, resp_s: chan<u32> out) {
    (req_r, resp_s)
  }

  init {  }

  next(_: ()) {
    let (tok, data) = recv(join(), req_r);
    let processed = data + u32:5;
    let tok = send(tok, resp_s, processed);
  }
}

#[test_proc]
proc Testing {
  req_s: chan<u32> out;
  resp_r: chan<u32> in;
  terminator: chan<bool> out;

  config(terminator: chan<bool> out) {
    let (req_s, req_r) = chan<u32>("req");
    let (resp_s, resp_r) = chan<u32>("resp");
    spawn Adder(req_r, resp_s);

    (req_s, resp_r, terminator)
  }

  init {  }

  next(_: ()) {
    let tok = send(join(), req_s, u32:16);
    let (tok, _data) = recv(tok, resp_r);

    let tok = send(tok, req_s, u32:32);
    let (tok, _data) = recv(tok, resp_r);

    let tok = send(tok, terminator, true);
  }
}
