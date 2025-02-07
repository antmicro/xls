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

// This file provides an example of how an infinite loop with I/O
// can be translated into a separate proc. This approach could be used
// to implement infinite loops in DSLX language

// Here is a possible syntax for the infinite loop in DSLX:
// proc IOExample {
//
//     input_r: chan<u32> in;
//     result_s: chan<u32> out;
//     data_r: chan<u32> in;
//
//     init {}
//
//     config(
//         input_r: chan<u32> in,
//         result_s: chan<u32> out,
//         data_r: chan<u32> in,
//     ) {
//         (input_r, result_s, data_r,)
//     }
//
//     next() {
//         let (tok, init_val) = recv(join(), input_r);
//
//         let result = loop (u32: sum) {
//             let (_, data) = recv(tok, data_r);
//             let sum = sum + data;
//
//             if sum > 100 {
//                 break sum;
//             } else {};
//
//             sum
//         }(init_val);
//
//         send(tok, result_s, result);
//     }
// }

struct LoopState {
    // An auxiliary variable indicating if the loop is active.
    // It is used to prevent reading from input when we are executing the loop logic
    active: bool,

    // other state variables
    sum: u32,
}

proc Loop {
    input_r: chan<u32> in;
    result_s: chan<u32> out;
    data_r: chan<u32> in;

    init { zero!<LoopState>() }

    config (
        input_r: chan<u32> in,
        result_s: chan<u32> out,

        // All the channels used in the loop should be forwarded to the "Loop" proc
        data_r: chan<u32> in,
    ) {
        (input_r, result_s, data_r)
    }

    next(state: LoopState) {
        // The proc should receive initial values for all state variables
        let (tok, sum) = recv_if(join(), input_r, !state.active, state.sum);

        // this is the main logic of the loop
        let (_, data) = recv(tok, data_r);
        let sum = sum + data;

        // condition before the break is used to send the result...
        let cond = sum > u32:100;
        let tok = send_if(tok, result_s, cond, sum);

        // .. and reset the loop proc to its initial state
        if cond {
            zero!<LoopState>()
        } else {
            LoopState { sum, active:true }
        }
    }
}

proc TranslatedIOExample {
    input_r: chan<u32> in;
    result_s: chan<u32> out;
    loop_input_s: chan<u32> out;
    loop_result_r: chan<u32> in;

    init {}

    config(
        input_r: chan<u32> in,
        result_s: chan<u32> out,
        data_r: chan<u32> in,
    ) {
        let (loop_input_s, loop_input_r) = chan<u32>("input");
        let (loop_result_s, loop_result_r) = chan<u32>("result");

        spawn Loop(
            loop_input_r, loop_result_s,
            // Channels used in the loop should be forwarded to the "Loop" proc
            data_r
        );

        (
            input_r, result_s,
            loop_input_s, loop_result_r,
        )
    }

    next(state: ()) {
        let (tok, init_val) = recv(join(), input_r);

        // the parent proc should send all input variables to the loop proc
        let tok = send(tok, loop_input_s, init_val);
        // later it should block on receiving the result of the loop
        let (tok, result) = recv(tok, loop_result_r);

        send(tok, result_s, result);
    }
}

#[test_proc]
proc TranslatedIOExampleTest {
    terminator: chan<bool> out;
    input_s: chan<u32> out;
    result_r: chan<u32> in;
    data_s: chan<u32> out;

    init {}

    config(terminator: chan<bool> out) {
        let (input_s, input_r) = chan<u32>("input");
        let (result_s, result_r) = chan<u32>("result");
        let (data_s, data_r) = chan<u32>("data");

        spawn TranslatedIOExample(input_r, result_s, data_r);
        (terminator, input_s, result_r, data_s)
    }

    next(state: ()) {
        let tok = send(join(), input_s, u32:10);
        let tok = send(tok, data_s, u32:89);
        let tok = send(tok, data_s, u32:101);
        let (tok, result) = recv(tok, result_r);

        assert_eq(result, u32:200);
        send(tok, terminator, true);
    }
}
