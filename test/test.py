import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

# 7-segment patterns, active-high, a = bit 0
SEG = {
    0: 0x3F,
    1: 0x06,
    2: 0x5B,
    3: 0x4F,
    4: 0x66,
    5: 0x6D,
    6: 0x7D,
    7: 0x07,
    8: 0x7F,
    9: 0x6F,
}

# Fastest speed: prescaler period = 2^18 clock cycles (terminal 2^18-1)
TICK = 1 << 18
# Small slack for assertion sampling (GLS-safe)
SLACK = 8

SW_SPEED = 0b11  # fastest
SW_UP = 1 << 2  # ui_in[2] = 1 -> count up (0 -> count down)
SW_DOWN = 0  # ui_in[2] = 0 -> count down
SW_PAUSE = 1 << 3


async def init(dut):
    """Power-up: run 50 MHz clock, release reset cleanly."""
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    dut.ui_in.value = 0
    dut.ena.value = 1
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 4)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


def seg_value(dut):
    return int(dut.uo_out.value) & 0x7F


@cocotb.test()
async def test_reset_shows_zero(dut):
    """After reset the display shows 0 and the dp is off."""
    await init(dut)
    assert seg_value(dut) == SEG[0], (
        f"expected {SEG[0]:02X} ('0'), got {seg_value(dut):02X}"
    )
    assert int(dut.uo_out.value) & 0x80 == 0, "dp should be off"


@cocotb.test()
async def test_count_up(dut):
    """Every tick increments: 0 -> 1 -> 2 -> 3."""
    await init(dut)
    dut.ui_in.value = SW_SPEED | SW_UP  # fastest, count up
    for expected in (1, 2, 3):
        await ClockCycles(dut.clk, TICK + SLACK)
        assert seg_value(dut) == SEG[expected], (
            f"expected {SEG[expected]:02X} ('{expected}'), got {seg_value(dut):02X}"
        )


@cocotb.test()
async def test_count_down_wrap(dut):
    """Down counting wraps 0 -> 9 -> 8 ... -> 0, then up resumes at 1."""
    await init(dut)
    dut.ui_in.value = SW_SPEED | SW_DOWN
    # 0 -> 9 -> 8 (wrap at the low end)
    await ClockCycles(dut.clk, TICK + SLACK)
    assert seg_value(dut) == SEG[9], f"expected 9, got {seg_value(dut):02X}"
    await ClockCycles(dut.clk, TICK + SLACK)
    assert seg_value(dut) == SEG[8], f"expected 8, got {seg_value(dut):02X}"
    # keep going down: ... -> 5
    for _ in range(3):
        await ClockCycles(dut.clk, TICK + SLACK)
    assert seg_value(dut) == SEG[5], f"expected 5, got {seg_value(dut):02X}"
    # ... -> 0 (full wraparound through all ten digits)
    for _ in range(5):
        await ClockCycles(dut.clk, TICK + SLACK)
    assert seg_value(dut) == SEG[0], f"expected 0, got {seg_value(dut):02X}"
    # flip direction: 0 -> 1
    dut.ui_in.value = SW_SPEED | SW_UP  # up
    await ClockCycles(dut.clk, TICK + SLACK)
    assert seg_value(dut) == SEG[1], f"expected 1, got {seg_value(dut):02X}"


@cocotb.test()
async def test_pause_holds_and_dp(dut):
    """Pause freezes the count and lights dp; resumes on release."""
    await init(dut)
    dut.ui_in.value = SW_SPEED | SW_UP
    await ClockCycles(dut.clk, TICK + SLACK)
    assert seg_value(dut) == SEG[1], f"expected 1, got {seg_value(dut):02X}"

    dut.ui_in.value = SW_SPEED | SW_UP | SW_PAUSE
    await Timer(1, unit="ns")  # let the non-blocking write settle
    assert int(dut.uo_out.value) & 0x80 != 0, "dp should be on while paused"
    await ClockCycles(dut.clk, 3 * TICK)
    assert seg_value(dut) == SEG[1], (
        f"count should be frozen at 1, got {seg_value(dut):02X}"
    )

    dut.ui_in.value = SW_SPEED | SW_UP  # release pause
    await ClockCycles(dut.clk, TICK + SLACK)
    assert seg_value(dut) == SEG[2], f"expected 2, got {seg_value(dut):02X}"
    assert int(dut.uo_out.value) & 0x80 == 0, "dp should be off after release"


@cocotb.test()
async def test_ena_gates_counting(dut):
    """With ena=0 nothing counts, even at fastest speed."""
    await init(dut)
    dut.ui_in.value = SW_SPEED
    dut.ena.value = 0
    await ClockCycles(dut.clk, 3 * TICK)
    assert seg_value(dut) == SEG[0], (
        f"count should be frozen at 0, got {seg_value(dut):02X}"
    )


@cocotb.test()
async def test_slowest_speed_no_early_tick(dut):
    """Speed 00 (div 2^24) must not tick within several fastest-speed periods."""
    await init(dut)
    # ui_in stays 0 -> speed 00
    await ClockCycles(dut.clk, 2 * TICK)
    assert seg_value(dut) == SEG[0], (
        f"slowest speed ticked too early, got {seg_value(dut):02X}"
    )
