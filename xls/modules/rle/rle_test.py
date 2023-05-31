import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge

@cocotb.test()
async def rle_test(dut):
    clock = Clock(dut.clk, 10, units="us")
    cocotb.start_soon(clock.start())

    await FallingEdge(dut.clk)
    for _ in range(10):
        await FallingEdge(dut.clk)
