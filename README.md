![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# 7-Segment BCD Counter (TinyTapeout)

0–9 BCD counter on the onboard 7-segment display: prescaler with 4 switchable
speeds (`f_tick = f_clk / 2^k`, k = 18…24 — 95 Hz to 1.5 Hz on a 25 MHz board
clock), up/down direction, pause with dp indicator. Pure divider, so it is
clock-rate agnostic. Verilog, 8/8 cocotb tests green at RTL *and* gate level,
LibreLane signoff clean.

- [Datasheet](docs/info.md) — how it works, how to test, pinout
- `src/tt_um_kouskos56_seg7.v` — RTL (unique top per TT rule)
- `test/` — cocotb suite, 8 tests (`make -B`), iverilog-capable harness
- `info.yaml` — yaml_version 6 submission metadata

## Silicon status

From the `gds` workflow run (LibreLane, sky130A, `@ttsky26d`):

| Metric | Result |
|---|---|
| Setup / hold violations | 0 across all 9 corners |
| Worst setup slack | +10.08 ns @ `ss_100C_1v60`, 20 ns clock |
| Magic DRC / LVS errors | 0 / 0 |
| Route DRC | converged 103 → 0 |
| Std-cell area / utilization | 2763 µm² / 16.8 % (1x1 tile) |

Critical path is `ena` → register D-pin (the SDC's 4 ns input delay dominates),
so the 24-bit prescaler increment is not the limiter.

## Quick check

```sh
cd test && make -B          # needs: pip install cocotb
```

## Submit

Target shuttle: **TTSKY26d** (all workflows pin `tt-gds-action@ttsky26d`,
PDK `sky130A`). Check the current deadline on the Tiny Tapeout website before
submitting.

Sync with `TinyTapeout/ttsky-verilog-template`, push, open a shuttle PR
(the GDS workflow hardens via `tt-gds-action`).
