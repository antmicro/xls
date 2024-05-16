// Copyright 2024 The XLS Authors
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

pub proc AssertProc {
    data_in_r: chan<u32> in;
    data_out_s: chan<u32> out;

    config(
        data_in_r: chan<u32> in,
        data_out_s: chan<u32> out,
    ) {

        (data_in_r, data_out_s)
    }

    init {}

    next(tok: token, state: ()) {
        let (tok, data) = recv(tok, data_in_r);
        // The following assert should trigger an interpreter failure which would lead to
        // a success of a negative test case in `error_modules_test.py`.
        assert!(false, "should_trigger_interpreter_failure");
        //fail!("triggers_interpreter_failure", ());
        let tok = send(tok, data_out_s, data);
    }
}

#[test_proc]
proc AssertProcTest {
    terminator: chan<bool> out;
    dut_data_in_s: chan<u32> out;
    dut_data_out_r: chan<u32> in;

    config(terminator: chan<bool> out) {
        let (dut_data_in_s, dut_data_in_r) = chan<u32>("dut_data_in");
        let (dut_data_out_s, dut_data_out_r) = chan<u32>("dut_data_out");
        spawn AssertProc(dut_data_in_r, dut_data_out_s);
        (terminator, dut_data_in_s, dut_data_out_r)
    }

    init { () }

    next(tok: token, state: ()) {
        let test_data = u32:1;
        let tok = send(tok, dut_data_in_s, test_data);
        let (tok, recv_value) = recv(tok, dut_data_out_r);

        assert_eq(recv_value, test_data);

        send(tok, terminator, true);
    }
}
