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

import xls.examples.common;

const NS = u32:3;
const NV = u32:2;

proc Proc {
  channel_array: chan<common::dv[NS][NV]>[2] in;
  outputs: chan<common::dv[NS][NV]>[2] out;
  config() {
    let (a, b) = chan<common::dv[NS][NV]>[2]("c");
    (b, a)
  }

  init { zero!<common::dv[NS][NV]>() }

  next(state: common::dv[NS][NV]) {
    let tok = join();
    let ready = true;
    let v =
              unroll_for! (st_slot_idx, store_data_value): (
                  u32, common::dv[NS][NV]
              ) in u32:0..NV {
                  let (_, sdv) = recv_if(
                      tok, channel_array[st_slot_idx],  // <<< failing on st_slot_idx
                      ready,
                      zero!<common::dv[NS][NV]>());
                  sdv
              }(zero!<common::dv[NS][NV]>());
    v
  }
}
