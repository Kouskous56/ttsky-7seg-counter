## How it works

This project is a 7-segment **BCD counter** (0-9) for the Tiny Tapeout
demo board. All logic lives on one synchronous clock (`clk`, 50 MHz).

The datapath has three stages:

1. **Prescaler / clock divider** — a 24-bit counter with a per-speed
   terminal count produces a single-cycle *tick* pulse (the
   clock-enable pattern, so the counter itself never sees a divided
   clock). The tick frequency is selected by `ui_in[1:0]`:

   | ui_in[1:0] | Division | Tick rate @50MHz |
   |------------|----------|------------------|
   | 00         | 2^24     | ~3 Hz (slowest)  |
   | 01         | 2^22     | ~12 Hz           |
   | 10         | 2^20     | ~48 Hz           |
   | 11         | 2^18     | ~190 Hz (fastest)|

2. **BCD counter** — counts on every tick from 0 to 9 and wraps.
   `ui_in[2]` selects the direction: 0 counts down (0 -> 9 -> 8 ...),
   1 counts up. `ui_in[3]` pauses the count (the current digit is
   held).

3. **7-segment decoder** — maps the 4-bit value to the segment pattern
   on `uo_out[6:0]`. The segments are active-high with a = bit 0,
   {g,f,e,d,c,b,a}, matching the demo board's onboard common-cathode
   display (no inverter needed). The decimal point `uo_out[7]` doubles
   as the pause indicator: it lights while `ui_in[3]` is held high.

`uio` is not used: `uio_out` and `uio_oe` are tied to 0 (the pins act
as inputs) and `uio_in` is tied off.

## How to test

With `rst_n` released (and `ena` high), set the switches:

1. Fastest counting: `ui_in[1:0] = 11` then watch `uo_out` cycle the
   segment patterns 0x3F -> 0x06 -> 0x5B -> ... at ~190 Hz.
2. Count down: set `ui_in[2] = 0` (or up with `ui_in[2] = 1`) and
   verify the wrap 9 -> 0 (or 0 -> 9).
3. Pause: set `ui_in[3] = 1` — the digit freezes and the dp turns on.

The Cocotb test (`test/test.py`) covers all of this automatically:
reset -> shows 0, count up 0-1-2-3, down wrap 0 -> 9 -> ... -> 0 -> 1,
pause/freeze + dp, `ena=0` gating, and "slowest speed does not tick
early" — 6 tests total.

## External hardware

None. The design drives the demo board's onboard single-digit
7-segment display; the only controls are the DIP switches on `ui`.