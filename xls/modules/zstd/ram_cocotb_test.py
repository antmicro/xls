# Copyright 2025 The XLS Authors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import pathlib

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

from xls.modules.zstd.cocotb.utils import run_test

async def reset_dut(dut, rst_len=10):
  dut.rst.setimmediatevalue(0)
  await ClockCycles(dut.clk, rst_len)
  dut.rst.setimmediatevalue(1)
  await RisingEdge(dut.clk)
  dut.rst.setimmediatevalue(0)

@cocotb.test(timeout_time=200, timeout_unit="ms")
async def comp_frame(dut):
  clock = Clock(dut.clk, 10, units="us")
  cocotb.start_soon(clock.start())

  await reset_dut(dut);

  dut.wr_data.value = 0x1234
  dut.wr_addr.value = 0x100
  dut.wr_en.value = 0x1
  dut.wr_mask.value = 0x1

  await RisingEdge(dut.clk)

  dut.wr_en.value = 0x0
  dut.rd_addr.value = 0x100
  dut.rd_en.value = 0x1
  dut.rd_mask.value = 0x1

  await RisingEdge(dut.clk)
  dut.rd_en.value = 0x0

  await ClockCycles(dut.clk, 5)
  assert(dut.rd_data.value == 0x1234);


if __name__ == "__main__":
  toplevel = "ram_1r1w_delayed_wrapper"
  verilog_sources = [
    "xls/modules/zstd/rtl/ram_1r1w.v",
    "xls/modules/zstd/rtl/ram_1r1w_delayed_wrapper.v",
  ]
  test_module = [pathlib.Path(__file__).stem]
  run_test(toplevel, test_module, verilog_sources)
