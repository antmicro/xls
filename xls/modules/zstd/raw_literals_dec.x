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

// The proc should just pass incoming data as literals to LiteralsBuffer.
// Packets of 0 length are not passed further and a warning is log instead.

import xls.modules.zstd.common;

type LiteralsData = common::LiteralsData;
type LitData = common::LitData;
type LitLength = common::LitLength;

proc RawLiteralsDecoder {
    dispatcher_r: chan<LiteralsData> in;
    buffer_s: chan<LiteralsData> out;

    config(dispatcher_r: chan<LiteralsData> in, buffer_s: chan<LiteralsData> out) {
        (dispatcher_r, buffer_s)
    }

    init {  }

    next(tok: token, state: ()) {
        let (tok, resp) = recv(tok, dispatcher_r);
        let do_send = if resp.length == LitLength:0 {
            trace_fmt!("[WARNING] Packet of 0 length received by RawLiteralsDecoder");
            false
        } else {
            true
        };
        let tok = send_if(tok, buffer_s, do_send, resp);
    }
}

#[test_proc]
proc RawLiteralsDecoderTest {
    terminator: chan<bool> out;
    dispatcher_s: chan<LiteralsData> out;
    buffer_r: chan<LiteralsData> in;

    config(terminator: chan<bool> out) {
        let (dispatcher_s, dispatcher_r) = chan<LiteralsData>("dispatcher");
        let (buffer_s, buffer_r) = chan<LiteralsData>("buffer");

        spawn RawLiteralsDecoder(dispatcher_r, buffer_s);

        (terminator, dispatcher_s, buffer_r)
    }

    init {  }

    next(tok: token, state: ()) {
        let data = LiteralsData { data: LitData:0x11_22_33_44_55_66, length: LitLength:6, last: true };
        let tok = send(tok, dispatcher_s, data);
        let (tok, resp) = recv(tok, buffer_r);
        assert_eq(resp, data);

        let empty_data = LiteralsData { data: LitData:0, length: LitLength:0, last: true };
        let tok = send(tok, dispatcher_s, empty_data);

        // Resend the first packet to verify that the empty packet is dropped correctly.
        let tok = send(tok, dispatcher_s, data);
        let (tok, resp) = recv(tok, buffer_r);
        assert_eq(resp, data);

        let tok = send(tok, terminator, true);
    }
}
