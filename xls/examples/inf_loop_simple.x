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
//
// This file provides a simple example of how an infinite loop without I/O
// can be translated into a separate proc. This approach could be used
// to implement infinite loops in DSLX language

// Here is a possible syntax for the infinite loop in DSLX:
//
// proc SimpleExample {
//     next(state: ()) {
//         let (tok, init_val) = recv(join(), input_r);
//
//         let result = loop (i: u32) {
//            if i % u32:2 == 0 {
//                trace_fmt!("Even");
//            } else {
//                trace_fmt!("Odd");
//            };
//
//            if i > 10 {
//                break i;
//            };
//            i + 1
//        }(init_val)
//
//        send(tok, result_s, result);
//    }
// }

struct LoopState {
    // An auxiliary variable indicating if the loop is active.
    // It is used to prevent reading from input when we are executing the loop logic
    active: bool,

    // other state variables
    i: u32,
}

proc Loop {
    input_r: chan<u32> in;
    result_s: chan<u32> out;

    init { zero!<LoopState>() }

    config (
        init_r: chan<u32> in,
        result_s: chan<u32> out,
    ) {
        (init_r, result_s)
    }

    next(state: LoopState) {
        // The proc should receive initial values for all state variables
        let (tok, i) = recv_if(join(), input_r, !state.active, state.i);

        // this is the main logic of the loop
        if i % u32:2 == u32:0 {
            trace_fmt!("Even")
        } else {
            trace_fmt!("Odd")
        };

        // condition before the break is used to send the result...
        let cond = i > u32:100;
        let tok = send_if(tok, result_s, cond, i);

        // .. and reset the loop proc to its initial state
        if cond {
            zero!<LoopState>()
        } else {
            LoopState { active:true, i: i + u32:1 }
        }
    }
}

// This proc shows how the original SimpleExample proc should be
// modified to make use of the "Loop" proc
proc TransformedSimpleExample {
    input_r: chan<u32> in;
    result_s: chan<u32> out;
    loop_input_s: chan<u32> out;
    loop_result_r: chan<u32> in;

    init {}

    config(
        input_r: chan<u32> in,
        result_s: chan<u32> out,
    ) {
        let (loop_input_s, loop_input_r) = chan<u32>("loop_input");
        let (loop_result_s, loop_result_r) = chan<u32>("loop_result");

        spawn Loop(loop_input_r, loop_result_s);

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
proc TransformedSimpleExampleTest {
    terminator: chan<bool> out;
    input_s: chan<u32> out;
    result_r: chan<u32> in;

    init {}

    config(terminator: chan<bool> out) {

        let (input_s, input_r) = chan<u32>("input");
        let (result_s, result_r) = chan<u32>("result");

        spawn TransformedSimpleExample(input_r, result_s);
        (terminator, input_s, result_r)
    }

    next(state: ()) {
        let tok = send(join(), input_s, u32:10);
        let (tok, _result) = recv(tok, result_r);
        send(tok, terminator, true);
    }
}
