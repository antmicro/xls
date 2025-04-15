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

proc Assert {
    req_r: chan<bool> in;
    resp_s: chan<()> out;

    init {}
    config (req_r: chan<bool> in, resp_s: chan<()> out) { (req_r, resp_s) }
    next(state: ()) {
        let (tok, predicate) = recv(join(), req_r);
        assert!(predicate, "assert_label");
        send(tok, resp_s, ());
    }
}

#[test_proc]
proc TestAssertInHierarchy {
    terminator: chan<bool> out;
    req_s: chan<bool>[10] out;
    resp_r: chan<()>[10] in;

    init {}
    config(terminator: chan<bool> out) {
        let (req_s, req_r) = chan<bool>[10]("req");
        let (resp_s, resp_r) = chan<()>[10]("resp");
        unroll_for! (i, _): (u32, ()) in range(u32:0, u32:10) {
            spawn Assert(req_r[i], resp_s[i]);
        }(());

        (terminator, req_s, resp_r)
    }

    next(state: ()) {
        let tok = send(join(), req_s[7], false);
        let (tok, _) = recv(tok, resp_r[7]);
        send(tok, terminator, true);
    }
}

fn assert_in_func(predicate: bool) {
    assert!(predicate, "assert_label");
}

#[test_proc]
proc TestAssertInFunction {
    terminator: chan<bool> out;
    req_s: chan<bool>[10] out;
    resp_r: chan<()>[10] in;

    init {}
    config(terminator: chan<bool> out) { (terminator,) }
    next(state: ()) {
        assert!(false, "assert_label");
        send(join(), terminator, true);
    }
}

#[test_proc]
proc TestAssert {
    terminator: chan<bool> out;

    init {}
    config(terminator: chan<bool> out) { (terminator,) }
    next(state: ()) {
        assert!(false, "assert_label");
        send(join(), terminator, true);
    }
}

#[test_proc]
proc TestFail {
    terminator: chan<bool> out;

    init {}
    config(terminator: chan<bool> out) { (terminator,) }
    next(state: ()) {
        fail!("fail_label", ());
        send(join(), terminator, true);
    }
}

#[test_proc]
proc TestAssertLt {
    terminator: chan<bool> out;

    init {}
    config(terminator: chan<bool> out) { (terminator,) }
    next(state: ()) {
        assert_lt(u32:1, u32:0);
        send(join(), terminator, true);
    }
}

#[test_proc]
proc TestAssertEq {
    terminator: chan<bool> out;

    init {}
    config(terminator: chan<bool> out) { (terminator,) }
    next(state: ()) {
        assert_eq(u32:100, u32:99);
        send(join(), terminator, true);
    }
}

#[test]
fn test_assert() {
    assert!(false, "assert_label");
}

#[test]
fn test_fail() {
    fail!("fail_label", ());
}

#[test]
fn test_assert_eq() {
    assert_eq(u32:100, u32:99);
}

#[test]
fn test_assert_lt() {
    assert_lt(u32:1, u32:0);
}
