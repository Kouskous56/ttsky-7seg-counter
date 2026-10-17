![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# 7-Segment BCD Counter (TinyTapeout)

0–9 BCD counter on the onboard 7-segment display: prescaler with 4 switchable
speeds (`f_tick = f_clk / 2^k`, k = 18…24 — one tick every 262 k to 16.7 M
clocks), up/down direction, pause with dp indicator. Pure divider, so it is
clock-rate agnostic. Verilog, 8/8 cocotb tests green at RTL *and* gate level,
SymbiYosys proofs over the full 2^24 prescaler, LibreLane signoff clean.

- [Datasheet](docs/info.md) — how it works, how to test, pinout
- `src/tt_um_kouskos56_seg7.v` — RTL (unique top per TT rule)
- `test/` — cocotb suite, 8 tests (`make -B`), iverilog-capable harness
- `formal/` — SymbiYosys proofs of the prescaler, BCD counter, decoder and a
  bounded-response property, plus a negative control built from the pre-fix RTL
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

### Corroborated locally, offline

The same RTL hardened on this machine — `openlane2 2.3.10` in Docker (WSL) against
the volare sky130A @ `0fe599b2` already on disk, no network. It is the bare module:
no TT wrapper, no TT SDC, no fixed tile, so area and utilization are *not*
comparable to CI. Timing and signoff are.

| Metric | Local | CI |
|---|---|---|
| Worst setup slack @ `max_ss_100C_1v60` | +11.00 ns | +10.08 ns |
| Setup / hold violations (9 corners) | 0 / 0 | 0 / 0 |
| Magic DRC / KLayout DRC / LVS errors | 0 / 0 / 0 | 0 / – / 0 |
| Route DRC by iteration | 106 → 7 → 15 → 0 | 103 → 0 |
| Antenna / power-grid violations | 0 / 0 | – |
| Std cells / std-cell area | 286 / 2208 µm² | – / 2763 µm² |
| Core area | 4000 µm² (free-standing die) | fixed by the 1x1 tile |

The gate-level netlist from that run also passes the same functional checks under
iverilog (11 s): reset value, two ticks, pause, `ena` gating, the speed-jump
regression and the tied-off `uio` — so the hardening did not break the design.
Artifacts land in
`build/harden/` (git-ignored): GDS, `metrics.json`, netlist, `config.tcl`, run log.

The cocotb suite itself runs here too, but only in WSL (Ubuntu has `cocotb` 2.1.0 and
`make`; the Windows Python does not): `wsl -d Ubuntu`, then `make -B` in `test/` gives
**TESTS=8 PASS=8 FAIL=0** in 107 s of wall time.
`make -B GATES=yes` does *not* work against the local netlist — the openlane2 `nl/` view
has no `VPWR`/`VGND` ports, so [test/tb.v](test/tb.v)'s `GL_TEST` hookup fails to elaborate
with "port VPWR is not a port of user_project". That is a difference in how the two flows
emit a netlist, not a design problem; `test/smoke_tb_gl.v` (which compiles the cells without
`USE_POWER_PINS`, the way this netlist expects) is the local stand-in, and it passes.
[tools/harden_local.sh](tools/harden_local.sh) is the run itself; it refuses to start
unless the image and `$PDK_ROOT/sky130A` are already on disk, and passes `--manual-pdk`
so nothing is fetched.

## Quick check

```sh
cd test && make -B          # cocotb suite, 8 tests (WSL on this machine; needs cocotb + make)
cd test && iverilog -g2012 -o smoke.out smoke_tb.v ../src/tt_um_kouskos56_seg7.v && vvp smoke.out
python tools/datasheet_preview.py   # local PDF/HTML of docs/info.md + pinout
```

`smoke_tb.v` is the same design checked with nothing but iverilog, for machines
without cocotb or `make`. `tools/datasheet_preview.py` renders the two inputs the
`docs` workflow reads through `markdown-it-py` + `pdflatex`, so wording and pin
tables can be reviewed before pushing — it is a preview, not the TT datasheet
generator, and the layout differs. `formal/README.md` documents the SymbiYosys
builds.

## Submit

Target shuttle: **TTSKY26d** (all workflows pin `tt-gds-action@ttsky26d`,
PDK `sky130A`). Check the current deadline on the Tiny Tapeout website before
submitting.

Sync with `TinyTapeout/ttsky-verilog-template`, push, open a shuttle PR
(the GDS workflow hardens via `tt-gds-action`).
