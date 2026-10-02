![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# 7-Segment BCD Counter (TinyTapeout)

0–9 BCD counter on the onboard 7-segment display: prescaler with 4 switchable
speeds (~3 Hz – ~190 Hz @50 MHz), up/down direction, pause with dp indicator.
Verilog, cocotb 7/7 green, OpenLane/LibreLane hardened clean.

- [Datasheet](docs/info.md) — how it works, how to test, pinout
- `src/tt_um_kouskos56_seg7.v` — RTL (unique top per TT rule)
- `test/` — cocotb suite, 7 tests (`make -B`), iverilog-capable harness
- `info.yaml` — yaml_version 6 submission metadata

## Quick check

```sh
cd test && make -B          # needs: pip install cocotb
```

## Submit

Sync with `TinyTapeout/ttsky-verilog-template`, push, open a shuttle PR
(the GDS workflow hardens via `tt-gds-action`).
