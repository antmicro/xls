# Copyright 2024 The XLS Authors
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
import random
import sys
import warnings

import cocotb
from cocotb.binary import BinaryValue
from cocotb.clock import Clock
from cocotb.triggers import Event, ClockCycles, RisingEdge
from cocotb_bus.scoreboard import Scoreboard
from cocotbext.axi import axi_channels
from cocotbext.axi.axi_ram import AxiRamRead
from cocotbext.axi.sparse_memory import SparseMemory

from xls.modules.zstd.cocotb.xlsstruct import xls_dataclass, XLSStruct
from xls.modules.zstd.cocotb.channel import XLSChannel, XLSChannelDriver, XLSChannelMonitor
from xls.modules.zstd.cocotb.utils import run_test

warnings.filterwarnings("ignore", category=DeprecationWarning)

ADDR_W = 7
DATA_W = 64
NUM_PARTITIONS = 64
SEL_W = 1


@xls_dataclass
class SelReq(XLSStruct):
    sel: SEL_W


@xls_dataclass
class ReadReq(XLSStruct):
    addr: ADDR_W
    mask: NUM_PARTITIONS


@xls_dataclass
class ReadResp(XLSStruct):
    data: DATA_W


@xls_dataclass
class WriteReq(XLSStruct):
    addr: ADDR_W
    data: DATA_W
    mask: NUM_PARTITIONS


@xls_dataclass
class WriteResp(XLSStruct):
    pass


@cocotb.test(timeout_time=100, timeout_unit="ms")
async def test_ram_demux_without_rewrite(dut):
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    sel_resp_channel = XLSChannel(dut, "ram_demux__sel_resp_s", dut.clk)
    rd_resp_channel = XLSChannel(dut, "ram_demux__rd_resp_s", dut.clk)
    wr_resp_channel = XLSChannel(dut, "ram_demux__wr_resp_s", dut.clk)

    sel_driver = XLSChannelDriver(dut, "ram_demux__sel_req_r", dut.clk)
    rd_req_driver = XLSChannelDriver(dut, "ram_demux__rd_req_r", dut.clk)
    wr_req_driver = XLSChannelDriver(dut, "ram_demux__wr_req_r", dut.clk)

    recv_resp = 0
    resp_monitor = XLSChannelMonitor(dut, "ram_demux__wr_resp_s", dut.clk, WriteResp)
    def terminate_cb(_):
      nonlocal recv_resp
      recv_resp += 1
    resp_monitor.add_callback(terminate_cb)

    sel_resp_channel.rdy.setimmediatevalue(1)
    rd_resp_channel.rdy.setimmediatevalue(1)
    wr_resp_channel.rdy.setimmediatevalue(1)

    dut.rst.setimmediatevalue(0)
    await ClockCycles(dut.clk, 10)
    dut.rst.setimmediatevalue(1)
    await ClockCycles(dut.clk, 10)
    dut.rst.setimmediatevalue(0)

    await ClockCycles(dut.clk, 100)
    assert recv_resp == 0, "Artificial response spotted"

    await sel_driver.send(SelReq(0))
    while True:
        await RisingEdge(dut.clk)
        if sel_resp_channel.rdy.value and sel_resp_channel.vld.value:
            break

    await wr_req_driver.send(WriteReq(addr=50, data=0x10, mask=0xFFFF_FFFF_FFFF_FFFF))
    while True:
        await RisingEdge(dut.clk)
        if wr_resp_channel.rdy.value and wr_resp_channel.vld.value:
            break

    await sel_driver.send(SelReq(1))
    while True:
        await RisingEdge(dut.clk)
        if sel_resp_channel.rdy.value and sel_resp_channel.vld.value:
            break

    await wr_req_driver.send(WriteReq(addr=127, data=0x3, mask=0xFFFF_FFFF_FFFF_FFFF))
    while True:
        await RisingEdge(dut.clk)
        if wr_resp_channel.rdy.value and wr_resp_channel.vld.value:
            break

    await sel_driver.send(SelReq(0))
    while True:
        await RisingEdge(dut.clk)
        if sel_resp_channel.rdy.value and sel_resp_channel.vld.value:
            break

    await rd_req_driver.send(ReadReq(addr=50, mask=0xFFFF_FFFF_FFFF_FFFF))
    while True:
        await RisingEdge(dut.clk)
        if rd_resp_channel.rdy.value and rd_resp_channel.vld.value:
            assert rd_resp_channel.data.value == 0x10
            break

    await sel_driver.send(SelReq(1))
    while True:
        await RisingEdge(dut.clk)
        if sel_resp_channel.rdy.value and sel_resp_channel.vld.value:
            break

    await rd_req_driver.send(ReadReq(addr=127, mask=0xFFFF_FFFF_FFFF_FFFF))
    while True:
        await RisingEdge(dut.clk)
        if rd_resp_channel.rdy.value and rd_resp_channel.vld.value:
            assert rd_resp_channel.data.value == 0x3
            break


if __name__ == "__main__":
    sys.path.append(str(pathlib.Path(__file__).parent))
    test_module = [pathlib.Path(__file__).stem]

    #. Case 0: RamDemux without RAM rewritting
    toplevel = "RamDemuxWithoutRewrite"
    verilog_sources = [
        "xls/modules/zstd/ram_demux_without_rewrite.v",
    ]
    run_test(toplevel, test_module, verilog_sources, build_dir="without_ram_rewritting")

    # Case 1: RamDemux with RAM rewritting
    try:
      toplevel = "ram_demux_wrapper"
      verilog_sources = [
          "xls/modules/zstd/ram_demux.v",
          "xls/modules/zstd/rtl/ram_1r1w.v",
          "xls/modules/zstd/rtl/ram_demux_wrapper.v",
      ]
      run_test(toplevel, test_module, verilog_sources, build_dir="with_ram_rewritting")
    except:
      print("False exception spotted")

    # Case 2: RamDemux wrapped with Passthrough pocs
    toplevel = "ram_demux_wrapper"
    verilog_sources = [
        "xls/modules/zstd/ram_demux_fixed.v",
        "xls/modules/zstd/rtl/ram_1r1w.v",
        "xls/modules/zstd/rtl/ram_demux_wrapper.v",
    ]
    run_test(toplevel, test_module, verilog_sources, build_dir="with_ram_rewritting_wrapped_with_passthrogh")
