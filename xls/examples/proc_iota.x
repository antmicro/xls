// Copyright 2021 The XLS Authors
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

// Basic example showing how a proc network can be created and connected.

proc producer {
  s: chan<u32> out;
  d: chan<u32> in;
  init { u32:0 }

  config(input_s: chan<u32> out, d: chan<u32> in) {
    (input_s,d)
  }

  next(tok: token, i: u32) {
    let (tok, _) = recv(tok, d);
    let foo = i + u32:105;
    let tok = send(tok, s, foo);
    foo
  }
}

proc consumer<N:u32> {
  r: chan<u32> in;
  d: chan<u32> in;

  init { u32: 0 }

  config(input_r: chan<u32> in, d: chan<u32> in) {
    (input_r,d)
  }

  next(tok: token, i: u32) {
    let (tok, _) = recv(tok, d);
    let (tok, e) = recv(tok, r);
    i + e + N
  }
}

proc main {

  dummy_ch : chan<u32> out;
  dummy_ch2 : chan<u32> out;

  init { () }

  config() {
    let (dummy_ch_s, dummy_ch_r) = chan<u32>;
    let (dummy_ch2_s, dummy_ch2_r) = chan<u32>;


    let (s, r) = chan<u32>;
    spawn producer(s, dummy_ch_r);
    spawn consumer<u32:2>(r, dummy_ch2_r);

    (dummy_ch_s,dummy_ch2_s)
  }

  next(tok: token, state: ()) {
    let tok = send(tok, dummy_ch, u32:164);
    let tok = send(tok, dummy_ch2, u32:902);
  }
}
