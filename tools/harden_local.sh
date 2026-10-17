#!/usr/bin/env bash
# Harden the shipped RTL locally, offline, in Docker under WSL (or any Linux with
# docker + a volare sky130). Companion to the "Corroborated locally" numbers in
# README.md; it is NOT the Tiny Tapeout flow -- CI runs ciel/LibreLane with the TT
# wrapper, its SDC and a fixed 1x1 tile, so expect different area/utilization and
# a slightly different slack.
#
#   bash tools/harden_local.sh
#
# Requires, already on disk (this script never downloads anything):
#   - image ghcr.io/efabless/openlane2:2.3.10
#   - $PDK_ROOT/sky130A, e.g. a volare install at commit 0fe599b2
#
# --manual-pdk is the flag that keeps it offline: without it openlane2 asks volare
# for its own preferred PDK commit and reaches the network.
set -uo pipefail

IMG=${IMG:-ghcr.io/efabless/openlane2:2.3.10}
PDK_ROOT=${PDK_ROOT:-$HOME/.volare}
REPO=$(cd "$(dirname "$0")/.." && pwd)
WORK=${WORK:-$REPO/build/harden-work}

docker image inspect "$IMG" >/dev/null 2>&1 || { echo "missing image $IMG (no pull: local-only)"; exit 1; }
[ -d "$PDK_ROOT/sky130A" ] || { echo "missing $PDK_ROOT/sky130A"; exit 1; }

rm -rf "$WORK"; mkdir -p "$WORK/src"
cp "$REPO/src/tt_um_kouskos56_seg7.v" "$WORK/src/"

cat > "$WORK/config.tcl" <<'TCL'
set ::env(DESIGN_NAME) tt_um_kouskos56_seg7
set ::env(VERILOG_FILES) [list $::env(DESIGN_DIR)/src/tt_um_kouskos56_seg7.v]
set ::env(CLOCK_PORT) clk
set ::env(CLOCK_NET) clk
set ::env(CLOCK_PERIOD) 20
set ::env(QUIT_ON_TIMING_VIOLATIONS) 1
set ::env(QUIT_ON_MAGIC_DRC) 1
set ::env(QUIT_ON_LVS_ERROR) 1
TCL

docker run --rm \
  -e PDK_ROOT=/pdk -e PDK=sky130A \
  -v "$PDK_ROOT":/pdk:ro \
  -v "$WORK":/work -w /work \
  --entrypoint openlane "$IMG" \
  --manual-pdk --pdk-root /pdk --overwrite --run-tag local \
  --save-views-to /work/views \
  /work/config.tcl

echo
echo "final views: $WORK/views  (gds/, nl/, metrics.json)"
echo "Then check the netlist functionally (about 11 s):"
echo "  iverilog -g2012 -DFUNCTIONAL -DSIM -DUNIT_DELAY=#1 \\"
echo "    \$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v \\"
echo "    \$PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v \\"
echo "    $WORK/views/nl/tt_um_kouskos56_seg7.nl.v \\"
echo "    $REPO/test/smoke_tb_gl.v && vvp gl.out"
echo "  (smoke_tb_gl.v is smoke_tb.v without the hierarchical \$dut.prescale"
echo "   peeks, which a netlist has none of.)"
