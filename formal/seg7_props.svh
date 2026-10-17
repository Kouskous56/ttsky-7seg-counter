// ---------------------------------------------------------------------------
// Formal property set for tt_um_kouskos56_seg7.
//
// This file is *not* a module. It is included from inside the DUT body through
//
//     `ifdef FORMAL
//         `include "seg7_props.svh"
//     `endif
//
// because Yosys has no `bind` support (and no yosys-slang plugin is installed),
// so a checker cannot reach `prescale`, `terminal` or `tick` from outside. The
// hook costs nothing in the shipped design: LibreLane, Icarus, Verilator and
// the TT precheck all compile with -DSYNTHESIS and leave FORMAL undefined, so
// the preprocessor drops the whole block. Only `read_verilog -formal` defines
// FORMAL, and only SymbiYosys runs that.
//
// Everything below names signals that already exist in the module, so these
// constrain the real prescaler/BCD/decoder rather than a model of them.
//
// Only immediate assertions inside clocked always blocks are used: that is the
// subset of SystemVerilog Yosys reliably translates, which keeps the checker
// usable with any sby engine.
//
// ---------------------------------------------------------------------------
// Two switches, set by the harness:
//
//   default           A reset is forced at step 0, so everything after it
//                     starts from the real power-on state. This build claims
//                     the reachable-state invariant (P4r) and, because the
//                     reachable set is a subset of what the free build checks,
//                     it is the narrower claim.
//
//   SEG7_FREE_INIT    Registers with no initial value are left unconstrained,
//                     so the solver picks `prescale` and `value` freely at step
//                     0. Every claim then holds for ALL 2^24 counter states --
//                     the strongest form of P1/P2, and the one that catches the
//                     `==` bug at depth 0. Reachable-state claims are gated off,
//                     since a free `value` of 10..15 is not a design bug.
//
//   SEG7_SKIP_DECODE  Drops P5s (segment equality) so the rest can be proven by
//                     k-induction. P5s is proven separately, exhaustively, by
//                     formal/seg7_decode.sby -- see the P5s comment below.
//
// Every register declared HERE is explicitly initialised, in every build. sby
// treats an uninitialised register as free at time 0, and a watchdog that
// starts at an arbitrary count reports a violation the design cannot produce.
// ---------------------------------------------------------------------------

`ifndef SEG7_FREE_INIT
    reg [1:0] f_boot = 2'd0;
    always @(posedge clk)
        if (f_boot !== 2'd3)
            f_boot <= f_boot + 2'd1;

    // Hold reset for the first cycle, then never assert it again -- the same
    // discipline the cocotb testbench uses.
    always @(posedge clk)
        if (f_boot === 2'd0) assume (!rst_n);

    reg f_seen_reset = 1'b0;
    always @(posedge clk)
        if (!rst_n) f_seen_reset <= 1'b1;

    wire f_state_ok = f_seen_reset;

    // Step 0 is the pre-reset state: `prescale` and `value` are still whatever
    // the solver picked, because the forced reset only lands on the 0 -> 1
    // edge. Claims about counter state must start at step 1 or they fail on a
    // state the board can never be in.
    wire f_gate_ok = f_boot !== 2'd0;
`else
    // This build may not assume the state ever came out of a reset.
    wire f_state_ok = 1'b0;
    // And it has no artificial pre-reset step: every state is a starting point.
    wire f_gate_ok = 1'b1;
`endif

    // Once reset has been released it stays released, so the f_*_d copies below
    // always describe an enabled edge rather than a reset edge.
    reg f_out_of_reset = 1'b0;
    always @(posedge clk) f_out_of_reset <= rst_n;
    always @(posedge clk)
        if (f_out_of_reset) assume (rst_n);

    reg [23:0] f_prescale_d = 24'd0;
    reg [3:0]  f_value_d    = 4'd0;
    reg [1:0]  f_speed_d    = 2'b00;
    reg        f_tick_d     = 1'b0;
    reg        f_ena_d      = 1'b0;
    reg        f_pause_d    = 1'b0;
    reg        f_up_d       = 1'b1;
    reg        f_rst_n_d    = 1'b0;

    always @(posedge clk) begin
        f_prescale_d <= prescale;
        f_value_d    <= value;
        f_speed_d    <= speed;
        f_tick_d     <= tick;
        f_ena_d      <= ena;
        f_pause_d    <= pause;
        f_up_d       <= up;
        f_rst_n_d    <= rst_n;
    end

    // True once reset has been released for a full cycle.
    wire f_settled = rst_n && f_rst_n_d && f_out_of_reset;

    // -----------------------------------------------------------------------
    // Reference functions, written from the datasheet rather than from the RTL.
    // -----------------------------------------------------------------------
    // f_tick = f_clk / 2^k, so the terminal count is 2^k - 1.
    function [23:0] f_expect_terminal;
        input [1:0] s;
        begin
            case (s)
                2'b00:   f_expect_terminal = 24'hFF_FFFF; // k = 24
                2'b01:   f_expect_terminal = 24'h3F_FFFF; // k = 22
                2'b10:   f_expect_terminal = 24'h0F_FFFF; // k = 20
                default: f_expect_terminal = 24'h03_FFFF; // k = 18
            endcase
        end
    endfunction

    // Segment table written on the *segment names* (a = bit 0, active high,
    // packed {g,f,e,d,c,b,a}) instead of copying the DUT's literals.
    //
    // The patterns below are derived from the lit segments per digit, which a
    // reader can check without reference to the RTL: 0 = abcdef, 1 = bc,
    // 2 = abdeg, 3 = abcdg, 4 = bcfg, 5 = acdfg, 6 = acdefg, 7 = abc, 8 = all,
    // 9 = abcdfg. Note this validates the case statement, not which bit of
    // uo_out drives which physical segment -- that mapping is a board wiring
    // fact, outside anything a formal tool on this netlist can see.
    //
    // It is only meaningful for a valid BCD digit, and P5 says so explicitly.
    // Digits 10..15 are unreachable, so the case's `default:` branch is dead
    // code, and Yosys optimises dead branches into don't-cares: in the formal
    // netlist `value = 11` drives seg = 100_0000, not the blank the RTL asks
    // for. That is not a design bug, so claiming anything about 10..15 here
    // would be claiming about an artefact of the netlist, not about the design.
    function [6:0] f_expect_segments;
        input [3:0] digit;
        reg a, b, c, d, e, f, g;
        begin
            case (digit)
                4'd0:    {g,f,e,d,c,b,a} = 7'b011_1111;
                4'd1:    {g,f,e,d,c,b,a} = 7'b000_0110;
                4'd2:    {g,f,e,d,c,b,a} = 7'b101_1011;
                4'd3:    {g,f,e,d,c,b,a} = 7'b100_1111;
                4'd4:    {g,f,e,d,c,b,a} = 7'b110_0110;
                4'd5:    {g,f,e,d,c,b,a} = 7'b110_1101;
                4'd6:    {g,f,e,d,c,b,a} = 7'b111_1101;
                4'd7:    {g,f,e,d,c,b,a} = 7'b000_0111;
                4'd8:    {g,f,e,d,c,b,a} = 7'b111_1111;
                default: {g,f,e,d,c,b,a} = 7'b110_1111; // 9
            endcase
            f_expect_segments = {g,f,e,d,c,b,a};
        end
    endfunction

    always @(posedge clk) begin
        // P0  terminal count matches the datasheet, for all four speeds.
        assert (terminal === f_expect_terminal(speed));

        // P1  the tick is exactly "counter at or past terminal" -- never
        //     earlier, never later. Combinational, so in the free build this is
        //     an exhaustive proof over every one of the 2^24 prescaler values
        //     at each of the four speed settings.
        if (f_gate_ok)
            assert (tick === (prescale >= terminal));

        // P2  no freeze. Past the terminal count for the *current* speed, the
        //     tick must fire on that very cycle. This is what the `==` -> `>=`
        //     change buys.
        if (f_gate_ok)
            assert (!(prescale > terminal) || tick);

        // P3  prescaler transfer: clear on a tick, otherwise +1, and hold while
        //     disabled -- the clock-enable pattern TT requires, stated as a
        //     consecutive relation so it needs no reachable-state assumption.
        if (f_settled && f_ena_d)
            assert (prescale === (f_tick_d ? 24'd0 : f_prescale_d + 24'd1));
        if (f_settled && !f_ena_d)
            assert (prescale === f_prescale_d);

        // P4  BCD step relation: only an enabled, unpaused tick moves the digit;
        //     up wraps 9 -> 0 and down wraps 0 -> 9.
        if (f_settled) begin
            if (f_ena_d && f_tick_d && !f_pause_d) begin
                if (f_up_d)
                    assert (value === (f_value_d == 4'd9 ? 4'd0 : f_value_d + 4'd1));
                else
                    assert (value === (f_value_d == 4'd0 ? 4'd9 : f_value_d - 4'd1));
            end else begin
                assert (value === f_value_d);
            end
        end

        // P5  outputs: dp mirrors pause, and the bidirectional pins stay driven
        //     low so the tile cannot fight the board for the bus.
        assert (uo_out[7] === pause);
        assert (uio_out === 8'd0 && uio_oe === 8'd0);

        // P5s decoder matches the segment table.
        //
        // Skippable, because it is the one claim k-induction cannot settle here
        // for a reason that has nothing to do with the design: `always @(*)` +
        // `case` makes Yosys infer the decoder as a ROM (`$auto$proc_rom...`),
        // and the ROM's out-of-range entries are don't-cares, which the formal
        // flow turns into free `$anyseq` inputs. The read then depends on that
        // free choice, so the equality stops being inductive even though it is
        // true cycle by cycle. Reproduce it on a 12-line ROM: BMC passes, k-
        // induction returns UNKNOWN with the same `anyseq_auto_setundef` witness.
        //
        // So P5s is proven on its own, in mode bmc with a free initial `value`
        // (formal/seg7_decode.sby). There `value` ranges over all 16 encodings
        // at step 0, which is an exhaustive check of the combinational decoder
        // -- a stronger result for this property than induction ever gives.
`ifndef SEG7_SKIP_DECODE
        if (value <= 4'd9)
            assert (uo_out[6:0] === f_expect_segments(value));
`endif

        // P7  releasing reset clears both counters.
        if (f_out_of_reset && rst_n && !f_rst_n_d) begin
            assert (prescale === 24'd0);
            assert (value === 4'd0);
        end

        // P4r reachable-state invariant: the digit never leaves 0..9. Claimed
        //     only in the build that forces a reset first.
        if (f_state_ok)
            assert (value <= 4'd9);
    end

    // -----------------------------------------------------------------------
    // P6  bounded response. `f_wd` counts enabled non-tick cycles since the most
    //     recent of {last tick, last speed change}; the gap may never exceed the
    //     terminal count of the speed now selected. That is the datasheet claim
    //     that raising the speed takes effect on the next cycle rather than
    //     after a full 2^24 wrap.
    //
    //     P6a is the lemma that makes P6 inductive: the watchdog and the
    //     prescaler clear together on a tick and step together otherwise, so the
    //     watchdog can never have counted further than the counter itself.
    //     Without it, k-induction hands the solver an arbitrary f_wd against a
    //     small terminal count and P6 fails on a state the design cannot be in.
    // -----------------------------------------------------------------------
    reg [23:0] f_wd = 24'd0;
    always @(posedge clk) begin
        if (!rst_n)
            f_wd <= 24'd0;
        else if (ena) begin
            if (tick || (speed != f_speed_d && f_ena_d))
                f_wd <= 24'd0;
            else
                f_wd <= f_wd + 24'd1;
        end
    end

    always @(posedge clk) begin
        assert (f_wd <= prescale);                    // P6a  lemma
        if (f_settled && ena && !tick)
            assert (f_wd <= terminal);                // P6   bounded response
    end
