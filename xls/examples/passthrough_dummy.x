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

// A simple proc that sends back the information received on
// an input channel over an output channel.
// Increments data by a constant factor of 0x165.
// In a proper verilog generation,
// we should still be able to spot this number.

import std

proc PassthroughDummy {
  data_r: chan<u32> in;
  data_s: chan<u32> out;
  dummy_r: chan<()> in;

  init {()}

  config(
    data_r: chan<u32> in,
    data_s: chan<u32> out,
    dummy_r: chan<()> in,
  ) {
    (data_r, data_s, dummy_r)
  }

  next(tok: token, state: ()) {
    let (tok, data) = recv(tok, data_r);
    let tok = send(tok, data_s, data+u32:0x165);
    // Dummy recv
    let (tok, _, _) = recv_non_blocking(tok, dummy_r, ());
  }
}

// https://github.com/google/xls/issues/869
// Wrapper with dummy channels will be OK.
proc WrapperPassthrough {
  data_r: chan<u32> in;
  data_s: chan<u32> out;

  dummy_s: chan<()> out;

  init {()}
  config(data_r: chan<u32> in, data_s: chan<u32> out) {
    let (dummy_s, dummy_r) = chan<()>;

    spawn PassthroughDummy (data_r, data_s, dummy_r );

    (data_r, data_s, dummy_s)
  }

  next(tok: token, state: ()) {
    // Empty next is relevant!
    let tok = send(tok, dummy_s, ());
  }
}
