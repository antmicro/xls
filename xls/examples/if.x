// Copyright 2022 The XLS Authors
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


fn slow_if<N: u32>(cond: bool, arg1: uN[N], arg2: uN[N]) -> uN[N] {
    if cond { arg1 } else { arg2 }
}

fn fast_if<N: u32>(cond: bool, arg1: uN[N], arg2: uN[N]) -> uN[N] {
    let mask = if (cond) {!bits[N]:0} else {bits[N]:0};
    (arg1 & mask) | (arg2 & !mask)
}

#[test]
fn fast_if_test() {
    assert_eq(if  true { u32:1 } else { u32:5 }, fast_if(true,  u32:1, u32:5));
    assert_eq(if false { u32:1 } else { u32:5 }, fast_if(false, u32:1, u32:5));
}

fn slow_if_inst(cond: bool, arg1: uN[1024], arg2: uN[1024]) -> uN[1024] {
    slow_if<u32:1024>(cond, arg1, arg2)
}

fn fast_if_inst(cond: bool, arg1: uN[1024], arg2: uN[1024]) -> uN[1024] {
    fast_if<u32:1024>(cond, arg1, arg2)
}
