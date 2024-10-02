#!/usr/bin/env python
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


from enum import Enum
from pathlib import Path
import tempfile

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, Event
from cocotb.binary import BinaryValue
from cocotb_bus.scoreboard import Scoreboard

from cocotbext.axi.axi_master import AxiMaster
from cocotbext.axi.axi_channels import AxiAWBus, AxiWBus, AxiBBus, AxiWriteBus, AxiARBus, AxiRBus, AxiReadBus, AxiBus, AxiBTransaction, AxiBSource, AxiBSink, AxiBMonitor, AxiRTransaction, AxiRSource, AxiRSink, AxiRMonitor
from cocotbext.axi.axi_ram import AxiRam
from cocotbext.axi.sparse_memory import SparseMemory

import zstandard

from xls.common import runfiles
from xls.modules.zstd.cocotb.channel import (
  XLSChannel,
  XLSChannelDriver,
  XLSChannelMonitor,
)
from xls.modules.zstd.cocotb.data_generator import GenerateFrame, BlockType
from xls.modules.zstd.cocotb.memory import init_axi_mem, AxiRamFromFile
from xls.modules.zstd.cocotb.utils import reset, run_test
from xls.modules.zstd.cocotb.xlsstruct import XLSStruct, xls_dataclass

MAX_ENCODED_FRAME_SIZE_B = 16384

# Override default widths of AXI response signals
signal_widths = {"bresp": 3}
AxiBBus._signal_widths = signal_widths
AxiBTransaction._signal_widths = signal_widths
AxiBSource._signal_widths = signal_widths
AxiBSink._signal_widths = signal_widths
AxiBMonitor._signal_widths = signal_widths
signal_widths = {"rresp": 3, "rlast": 1}
AxiRBus._signal_widths = signal_widths
AxiRTransaction._signal_widths = signal_widths
AxiRSource._signal_widths = signal_widths
AxiRSink._signal_widths = signal_widths
AxiRMonitor._signal_widths = signal_widths

@xls_dataclass
class NotifyStruct(XLSStruct):
  pass

class CSR(Enum):
  """
  Maps the offsets to the ZSTD Decoder registers
  """
  Status = 0x0
  Start = 0x4
  Reset = 0x8
  InputBuffer = 0xC
  OutputBuffer = 0x10
  WhoAmI = 0x14

class Status(Enum):
  """
  Codes for the Status register
  """
  IDLE = 0x0
  RUNNING = 0x1

def set_termination_event(monitor, event, transactions):
  def terminate_cb(_):
    if monitor.stats.received_transactions == transactions:
      event.set()
  monitor.add_callback(terminate_cb)

def connect_axi_read_bus(dut, name=""):
  AXI_AR = "axi_ar"
  AXI_R = "axi_r"

  if name != "":
      name += "_"

  bus_axi_ar = AxiARBus.from_prefix(dut, name + AXI_AR)
  bus_axi_r = AxiRBus.from_prefix(dut, name + AXI_R)

  return AxiReadBus(bus_axi_ar, bus_axi_r)

def connect_axi_write_bus(dut, name=""):
  AXI_AW = "axi_aw"
  AXI_W = "axi_w"
  AXI_B = "axi_b"

  if name != "":
      name += "_"

  bus_axi_aw = AxiAWBus.from_prefix(dut, name + AXI_AW)
  bus_axi_w = AxiWBus.from_prefix(dut, name + AXI_W)
  bus_axi_b = AxiBBus.from_prefix(dut, name + AXI_B)

  return AxiWriteBus(bus_axi_aw, bus_axi_w, bus_axi_b)

def connect_axi_bus(dut, name=""):
  bus_axi_read = connect_axi_read_bus(dut, name)
  bus_axi_write = connect_axi_write_bus(dut, name)

  return AxiBus(bus_axi_write, bus_axi_read)

def get_decoded_frame_buffer(ifh, address, memory=SparseMemory(size=MAX_ENCODED_FRAME_SIZE_B)):
  dctx = zstandard.ZstdDecompressor()
  memory.write(address, dctx.decompress(ifh.read()))
  return memory

async def csr_write(cpu, csr, data):
  if type(data) is int:
    data = data.to_bytes(4, byteorder='little')
  assert len(data) <= 4
  await cpu.write(csr.value, data)

async def csr_read(cpu, csr):
  return await cpu.read(csr.value, 4)

async def test_csr(dut):

  clock = Clock(dut.clk, 10, units="us")
  cocotb.start_soon(clock.start())

  dut.rst.setimmediatevalue(0)
  await ClockCycles(dut.clk, 20)
  dut.rst.setimmediatevalue(1)
  await ClockCycles(dut.clk, 20)
  dut.rst.setimmediatevalue(0)

  csr_bus = connect_axi_bus(dut, "csr")

  cpu = AxiMaster(csr_bus, dut.clk, dut.rst)

  await ClockCycles(dut.clk, 10)
  i = 0
  for reg in CSR:
    expected = bytearray.fromhex("EFBEADDE")
    expected[0] += i
    await csr_write(cpu, reg, expected)
    read = await csr_read(cpu, reg)
    assert read.data == expected
    i += 1
  await ClockCycles(dut.clk, 10)

async def configure_decoder(cpu, ibuf_addr, obuf_addr):
  status = await csr_read(cpu, CSR.Status)
  if int.from_bytes(status.data, byteorder='little') != Status.IDLE.value:
    await csr_write(cpu, CSR.Reset, 0x1)
  await csr_write(cpu, CSR.InputBuffer, ibuf_addr)
  await csr_write(cpu, CSR.OutputBuffer, obuf_addr)

async def start_decoder(cpu):
  await csr_write(cpu, CSR.Start, 0x1)

async def wait_for_idle(cpu):
  status = await csr_read(cpu, CSR.Status)
  while (int.from_bytes(status.data, byteorder='little') != Status.IDLE.value):
    status = await csr_read(cpu, CSR.Status)

async def mock_decoder(dut, memory, mem_bus, csr, csr_bus, encoded_frame_path, obuf_addr):
  MOCK_NOTIFY_CHANNEL = "notify"
  driver_notify = XLSChannelDriver(dut, MOCK_NOTIFY_CHANNEL, dut.clk)
  start = int.from_bytes(csr.read(CSR.Start.value, 4), byteorder='little')
  status = int.from_bytes(csr.read(CSR.Status.value, 4), byteorder='little')
  while ((start != 0x1) | (status != Status.IDLE.value)):
    start = int.from_bytes(csr.read(CSR.Start.value, 4), byteorder='little')
    status = int.from_bytes(csr.read(CSR.Status.value, 4), byteorder='little')
  csr.write_dword(CSR.Start.value, 0x0)
  csr.write_dword(CSR.Status.value, Status.RUNNING.value)
  with open(encoded_frame_path, "rb") as encoded_frame_fh:
    get_decoded_frame_buffer(encoded_frame_fh, obuf_addr, memory)
  memory.hexdump(obuf_addr, memory.size-obuf_addr)
  csr.write_dword(CSR.Status.value, Status.IDLE.value)
  #TODO: signal finished decoding on the IRQ line
  await driver_notify.send(NotifyStruct())

async def test_decoder(dut, test_cases, block_type):
  NOTIFY_CHANNEL = "notify"

  clock = Clock(dut.clk, 10, units="us")
  cocotb.start_soon(clock.start())

  dut.rst.setimmediatevalue(0)
  await ClockCycles(dut.clk, 20)
  dut.rst.setimmediatevalue(1)
  await ClockCycles(dut.clk, 20)
  dut.rst.setimmediatevalue(0)

  memory_bus = connect_axi_bus(dut, "memory")
  csr_bus = connect_axi_bus(dut, "csr")
  notify_channel = XLSChannel(dut, NOTIFY_CHANNEL, dut.clk, start_now=True)
  monitor_notify = XLSChannelMonitor(dut, NOTIFY_CHANNEL, dut.clk, NotifyStruct)

  terminate = Event()
  set_termination_event(monitor_notify, terminate, 1)

  cpu = AxiMaster(csr_bus, dut.clk, dut.rst)

  for i in range(test_cases):
    #FIXME: use delete_on_close=False after moving to python 3.12
    with tempfile.NamedTemporaryFile(delete=False) as encoded:
      mem_size = MAX_ENCODED_FRAME_SIZE_B
      GenerateFrame(i+1, block_type, encoded.name)
      decoded_frame_memory = get_decoded_frame_buffer(encoded, 0x0)
      #decoded_frame_memory.hexdump(0, mem_size)
      encoded.close()
      memory = AxiRamFromFile(bus=memory_bus, clock=dut.clk, reset=dut.rst, path=encoded.name, size=mem_size)
      memory.hexdump(0, mem_size)
      ibuf_addr = 0x0
      obuf_addr = mem_size // 2
      await configure_decoder(cpu, ibuf_addr, obuf_addr)
      await start_decoder(cpu)
      ##await mock_decoder(dut, memory, memory_bus, csr, csr_bus, encoded.name, obuf_addr)
      #await terminate.wait()
      #await wait_for_idle(cpu)
      #decoded_frame = memory.read(obuf_addr, memory.size-obuf_addr)
      #expected_decoded_frame = decoded_frame_memory.read(0, memory.size-obuf_addr)
      #assert decoded_frame == expected_decoded_frame

  await ClockCycles(dut.clk, 1000)

@cocotb.test(timeout_time=50, timeout_unit="ms")
async def zstd_csr_test(dut):
  await test_csr(dut)

@cocotb.test(timeout_time=20000, timeout_unit="ms")
async def zstd_raw_frames_test(dut):
  test_cases = 1
  block_type = BlockType.RAW
  await test_decoder(dut, test_cases, block_type)

@cocotb.test(timeout_time=20000, timeout_unit="ms")
async def zstd_rle_frames_test(dut):
  test_cases = 1
  block_type = BlockType.RLE
  await test_decoder(dut, test_cases, block_type)

@cocotb.test(timeout_time=20000, timeout_unit="ms")
async def zstd_compressed_frames_test(dut):
  test_cases = 1
  block_type = BlockType.COMPRESSED
  await test_decoder(dut, test_cases, block_type)

@cocotb.test(timeout_time=20000, timeout_unit="ms")
async def zstd_random_frames_test(dut):
  test_cases = 1
  block_type = BlockType.RANDOM
  await test_decoder(dut, test_cases, block_type)

if __name__ == "__main__":
  toplevel = "zstd_dec_wrapper"
  verilog_sources = [
    "xls/modules/zstd/dec.v",
    "xls/modules/zstd/xls_fifo_wrapper.v",
    "xls/modules/zstd/zstd_dec_wrapper.v",
    "xls/modules/zstd/axi_interconnect_wrapper.v",
    "xls/modules/zstd/axi_interconnect.v",
    "xls/modules/zstd/arbiter.v",
    "xls/modules/zstd/priority_encoder.v",
  ]
  test_module=[Path(__file__).stem]
  run_test(toplevel, test_module, verilog_sources)
