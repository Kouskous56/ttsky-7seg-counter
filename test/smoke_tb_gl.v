`timescale 1ns / 1ps
// ---------------------------------------------------------------------------
// Gate-level companion to smoke_tb.v: the same checks against a hardened
// netlist, so a local hardening run can be shown to have preserved behaviour.
//
//   iverilog -g2012 -DFUNCTIONAL -DSIM -DUNIT_DELAY=#1 \
//     $PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v \
//     $PDK_ROOT/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v \
//     <run>/final/netlist/tt_um_kouskos56_seg7.v smoke_tb_gl.v
//   vvp a.out
//
// The checks are purely behavioural here: a netlist has no `prescale` to peek
// at, so the speed-jump regression is watched on the display instead of on the
// counter. That also makes this file usable as a post-layout sanity check in CI
// if the cocotb gate-level run is ever unavailable.
// ---------------------------------------------------------------------------
module smoke_tb_gl;
  reg clk = 0, rst_n = 0, ena = 1;
  reg [7:0] ui_in = 0, uio_in = 0;
  reg [7:0] hold;
  wire [7:0] uo_out, uio_out, uio_oe;
  integer errors = 0;

  tt_um_kouskos56_seg7 dut (
    .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in),
    .uio_out(uio_out), .uio_oe(uio_oe), .ena(ena), .clk(clk), .rst_n(rst_n));

  always #10 clk = ~clk;                  // 50 MHz
  localparam PER = (1 << 18) * 20;        // one tick period at speed 11, in ns

  task check(input cond, input [8*36:1] msg);
    begin
      if (!cond) begin
        errors = errors + 1;
        $display("FAIL %0s  (uo_out=%b)", msg, uo_out);
      end else
        $display("ok   %0s  (uo_out=%b)", msg, uo_out);
    end
  endtask

  initial begin
    ui_in = 8'b0100;                      // speed 00 (slowest), count up
    #50 rst_n = 1;
    check(uo_out === 8'h3F, "reset shows 0 dp off");

    ui_in = 8'b0111;                      // fastest
    #(PER + 200)  check(uo_out === 8'h06, "one tick -> 1");
    #(PER + 200)  check(uo_out === 8'h5B, "two ticks -> 2");

    ui_in = 8'b1111;                      // + pause
    #200 hold = uo_out;
    #(PER + 200) begin
      check(uo_out[6:0] === hold[6:0], "pause holds the digit");
      check(uo_out[7] === 1'b1, "pause lights dp");
    end

    ui_in = 8'b0111; ena = 0;
    #(2 * PER) check(uo_out[6:0] === hold[6:0], "ena=0 holds the count");
    ena = 1;

    // Park the prescaler past the fastest terminal count under speed 00: the
    // digit must not move. Then jump to 11 and require a tick within 100
    // cycles -- with `==` it would wait for a 24-bit wrap.
    ui_in = 8'b0100;
    hold = uo_out;
    #(2_000_000 * 20);
    check(uo_out[6:0] === hold[6:0], "no tick while parked at the slowest speed");
    ui_in = 8'b0111;
    #2000                                 // one hundred clock cycles
    check(uo_out[6:0] !== hold[6:0], "speed jump ticks within 100 cycles");

    check(uio_out === 8'h00 && uio_oe === 8'h00, "uio pins driven low");

    if (errors == 0) $display("GL SMOKE PASS");
    else             $display("GL SMOKE FAIL: %0d error(s)", errors);
    $finish;
  end
endmodule
