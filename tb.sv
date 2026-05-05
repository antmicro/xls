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

// Copyright (c) 2025-2026 Antmicro <www.antmicro.com>
// SPDX-License-Identifier: Apache-2.0

`timescale 1ns/1ns

module tb;
  reg clk = 1;
  reg rst = 0;
  reg [31:0] req_r;
  reg req_r_vld;
  reg resp_s_rdy;
  wire req_r_rdy;
  wire [31:0] resp_s;
  wire resp_s_vld;

  Arbiter order_dependence(
    .clk(clk),
    .rst(rst),
    ._req_r(req_r),
    ._req_r_vld(req_r_vld),
    ._resp_s_rdy(resp_s_rdy),
    ._req_r_rdy(req_r_rdy),
    ._resp_s(resp_s),
    ._resp_s_vld(resp_s_vld)
  );

  always #2 clk = ~clk;

  initial
  begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb);

    rst = 1'h1;

    #4
    rst = 1'h0;

    #4
    req_r = 32'h0000_0007;
    req_r_vld = 1'h1;
    resp_s_rdy = 1'h1;

    #4
    req_r = 32'h0000_0000;
    req_r_vld = 1'h0;

    #24
    $finish;
  end
endmodule
