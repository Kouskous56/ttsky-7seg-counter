`timescale 1ns / 1ps
// ---------------------------------------------------------------------------
// Offline self-checking smoke test: iverilog + vvp only.
//
//   iverilog -g2012 -o smoke.out smoke_tb.v ../src/tt_um_kouskos56_seg7.v
//   vvp smoke.out
//
// The cocotb suite in test.py is the real coverage (8 tests, RTL and gate
// level, in CI). This file exists because cocotb and `make` are not available
// on every machine that touches the design, and a design nobody can simulate
// locally is a design nobody can debug. It checks a subset: reset value, two
// ticks at the fastest speed, pause freeze + dp, ena gating, the
// `prescale >= terminal` regression, and the tied-off uio pins. ~7 s of wall
// time, dominated by the 2-million-cycle prescaler parking.
//
// The regression check reaches into `dut.prescale`; that is deliberate, since
// the point is to see the tick fire on the cycle after a speed increase rather
// than infer it from the display.
// ---------------------------------------------------------------------------
module smoke_tb;
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

    // dp follows pause combinationally, so releasing pause while disabling the
    // clock changes uo_out[7] but must not move the digit.
    ui_in = 8'b0111; ena = 0;
    #(2 * PER) check(uo_out[6:0] === hold[6:0], "ena=0 holds the count");
    ena = 1;

    // The `>=` regression: park the prescaler far above the fastest terminal
    // count under speed 00, then jump to 11. The tick must fire on the next
    // cycle, not after the 24-bit counter wraps and re-reaches the terminal.
    ui_in = 8'b0100;
    #(2_000_000 * 20);
    check(dut.prescale > 24'd1_000_000, "prescaler parked past 2^18-1");
    ui_in = 8'b0111;
    #200                                  // ten clock cycles later
    check(dut.prescale < 24'd100, "speed jump ticks at once");

    check(uio_out === 8'h00 && uio_oe === 8'h00, "uio pins driven low");

    if (errors == 0) $display("SMOKE PASS");
    else             $display("SMOKE FAIL: %0d error(s)", errors);
    $finish;
  end
endmodule
