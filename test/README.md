# Testbench for the 7-segment BCD counter (tt_um_kouskos56_seg7)

The cocotb tests in [test.py](test.py) drive the DUT and check the outputs: reset shows 0, count up, down wrap 0->9->...->0->1, pause freeze + dp, ena gating, slowest speed no early tick, uio pins contention-free, and speed increase not skipped (regression for the `prescale >= terminal` fix). Run: `make -B` (needs cocotb, see requirements.txt).
See below to get started or for more information, check the [website](https://tinytapeout.com/hdl/testing/).

## How to run without cocotb

[smoke_tb.v](smoke_tb.v) is a self-checking iverilog testbench covering a subset
(reset value, two ticks, pause freeze + dp, ena gating, the `prescale >= terminal`
regression, tied-off `uio`). It needs nothing but `iverilog` and `vvp`, for machines
where cocotb or `make` are unavailable:

```sh
iverilog -g2012 -o smoke.out smoke_tb.v ../src/tt_um_kouskos56_seg7.v && vvp smoke.out
```

It prints `SMOKE PASS` (9 checks) in a few seconds. Against `formal/negative_control/`
(the pre-fix RTL) it fails the speed-jump check, which is the point of that check. The
control's module is named `..._seg7_eq`, so rename it first:

```sh
sed 's/^module tt_um_kouskos56_seg7_eq/module tt_um_kouskos56_seg7/' \
  formal/negative_control/tt_um_kouskos56_seg7_eq.v > /tmp/eq_named.v
iverilog -g2012 -o smoke_eq.out smoke_tb.v /tmp/eq_named.v && vvp smoke_eq.out
# FAIL speed jump ticks at once  ->  SMOKE FAIL: 1 error(s)
```

[smoke_tb_gl.v](smoke_tb_gl.v) is the same suite against a hardened gate-level
netlist (`-DFUNCTIONAL -DSIM -DUNIT_DELAY=#1` plus the sky130 cell models); it
checks the display instead of the counter, since a netlist has no `prescale` to
reference. `tools/harden_local.sh` prints the exact command.

## Setting up

1. Edit [Makefile](Makefile) and modify `PROJECT_SOURCES` to point to your Verilog files.
2. Edit [tb.v](tb.v) and replace `tt_um_kouskos56_seg7` with your module name.

## How to run

To run the RTL simulation:

```sh
make -B
```

To run gatelevel simulation, first harden your project and copy `../runs/wokwi/results/final/verilog/gl/{your_module_name}.v` to `gate_level_netlist.v`.

Then run:

```sh
make -B GATES=yes
```

If you wish to save the waveform in VCD format instead of FST format, edit tb.v to use `$dumpfile("tb.vcd");` and then run:

```sh
make -B FST=
```

This will generate `tb.vcd` instead of `tb.fst`.

## How to view the waveform file

Using GTKWave

```sh
gtkwave tb.fst tb.gtkw
```

Using Surfer

```sh
surfer tb.fst
```
