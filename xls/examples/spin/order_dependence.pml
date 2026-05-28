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

/*
proc Worker<VALUE: u32> {
  req_r: chan<u32> in;
  resp_s: chan<u32> out;

  config(req_r: chan<u32> in, resp_s: chan<u32> out) {
    (req_r, resp_s)
  }

  init {  }

  next(state: ()) {
    let (tok, req) = recv(join(), req_r);
    let tok = send(tok, resp_s, req + VALUE);
  }
}
*/

proctype Worker(int param; chan in; chan out) {
  int val;

  do
  ::
    in ? val;
    val = val + param;
    assert(nfull(out));
    out ! val;
  od
}

/*
proc Receiver {
  req_r: chan<u32>[2] in;
  resp_s: chan<u32> out;

  config(req_r: chan<u32>[2] in, resp_s: chan<u32> out) {
    (req_r, resp_s)
  }

  init {  }

  next(state: ()) {
    let (tok0, req0, valid0) = recv_non_blocking(join(), req_r[0], u32:0);
    let (tok1, req1, valid1) = recv_non_blocking(join(), req_r[1], u32:0);
    let tok = send_if(join(tok0, tok1), resp_s, valid0 || valid1, req0 + req1);
  }
}
*/

proctype Receiver(chan in_0; chan in_1; chan out) {
  int req0;
  bool valid0;

  int req1;
  bool valid1;

  do
  ::
    atomic {
      if
      :: in_0 ? [req0] ->
        valid0 = 1;
        in_0 ? req0
      :: else ->
        valid0 = 0;
        req0 = 0;
      fi
    }
    if
    :: valid0 ->
      out ! req0;
    :: else
      skip
    fi

    atomic {
      if
      :: in_1 ? [req1] ->
        valid1 = 1;
        in_1 ? req1
      :: else ->
        valid1 = 0;
        req1 = 0;
      fi
    }
    if
    :: valid1 ->
      out ! req1;
    :: else
      skip
    fi
  od
}

/*
proc Arbiter {
    req_r: chan<u32> in;
    resp_s: chan<u32> out;
    worker_req_s: chan<u32>[2] out;
    receiver_resp_r: chan<u32> in;

    config(req_r: chan<u32> in, resp_s: chan<u32> out) {
        let (worker_req_s, worker_req_r) = chan<u32, u32:1>[2]("worker_req");
        let (receiver_req_s, receiver_req_r) = chan<u32, u32:1>[2]("receiver_req");
        let (receiver_resp_s, receiver_resp_r) = chan<u32, u32:1>("receiver_resp");

        spawn Worker<u32:5>(worker_req_r[0], receiver_req_s[0]);
        spawn Receiver(receiver_req_r, receiver_resp_s);
        spawn Worker<u32:16>(worker_req_r[1], receiver_req_s[1]);

        (req_r, resp_s, worker_req_s, receiver_resp_r)
    }

    init {  }

    next(state: ()) {
        let (tok, req, req_valid) = recv_non_blocking(join(), req_r, u32:0);
        let tok0 = send_if(tok, worker_req_s[0], req_valid, req);
        let tok1 = send_if(tok, worker_req_s[1], req_valid, req);

        let (tok, resp, valid) = recv_non_blocking(join(tok0, tok1), receiver_resp_r, u32:0);
        let tok = send_if(tok, resp_s, valid, resp);
    }
}
*/

proctype Arbiter(chan req_r; chan resp_s) {

  int param0 = 5;
  int param1 = 16;

  chan worker_req_0 = [8] of { int };
  chan receiver_req_0 = [8] of { int };

  chan worker_req_1 = [8] of { int };
  chan receiver_req_1 = [8] of { int };

  chan receiver_resp = [8] of { int };

  run Worker(param1, worker_req_1, receiver_req_1);
  run Receiver(receiver_req_0, receiver_req_1, receiver_resp);
  run Worker(param0, worker_req_0, receiver_req_0);

  int req;
  bool req_valid;

  int resp;
  bool resp_valid;

  do
  ::
    atomic {
      if
      :: req_r ? [req] ->
        req_valid = 1;
        req_r ? req
      :: else ->
        req_valid = 0;
        req = 0;
      fi
    }

    if
    :: req_valid ->
      worker_req_0 ! req;
      worker_req_1 ! req;
    :: else
      skip
    fi

    atomic {
      if
      :: receiver_resp ? [resp] ->
        resp_valid = 1;
        receiver_resp ? resp
      :: else ->
        resp_valid = 0;
        resp = 0;
      fi
    }

    if
    :: resp_valid ->
      resp_s ! resp;
    :: else
      skip
    fi
  od
}

chan req_r = [8] of { int };
chan resp_s = [8] of { int };

init {
  run Arbiter(req_r, resp_s);

  int req = 16;
  req_r ! req;

  int resp = 0;
  resp_s ? resp;
  assert(resp == 32);

  skip
}
