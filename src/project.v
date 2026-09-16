`default_nettype none

module tt_um_example (
    input  wire [7:0] ui_in,    // ui_in[1:0] speed, ui_in[2] direction, ui_in[3] pause
    output wire [7:0] uo_out,   // uo_out[6:0] segments, uo_out[7] dp
    input  wire [7:0] uio_in,   // unused
    output wire [7:0] uio_out,  // tied to 0
    output wire [7:0] uio_oe,   // tied to 0 (input only)
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // ------------------------------------------------------------------
    // Controls
    //   ui_in[1:0] speed  : 00 = div 2^24 (~3Hz), 01 = div 2^22 (~12Hz),
    //                       10 = div 2^20 (~48Hz), 11 = div 2^18 (~190Hz @50MHz)
    //   ui_in[2]   up     : 0 = count down, 1 = count up
    //   ui_in[3]   pause  : 1 = hold the count (dp lights up)
    // ------------------------------------------------------------------
    wire [1:0] speed = ui_in[1:0];
    wire       up    = ui_in[2];
    wire       pause = ui_in[3];

    // ------------------------------------------------------------------
    // Prescaler: counter with per-speed terminal count (clock-enable tick).
    //   tick is a single-cycle pulse; everything stays on the same clock.
    // ------------------------------------------------------------------
    reg [23:0] prescale;
    wire [23:0] terminal;
    assign terminal = (speed == 2'b00) ? 24'hFF_FFFF : // 2^24 - 1
                      (speed == 2'b01) ? 24'h3F_FFFF : // 2^22 - 1
                      (speed == 2'b10) ? 24'h0F_FFFF : // 2^20 - 1
                                         24'h03_FFFF;  // 2^18 - 1
    wire tick = (prescale == terminal);

    always @(posedge clk) begin
        if (!rst_n)
            prescale <= 24'd0;
        else if (ena)
            prescale <= tick ? 24'd0 : prescale + 24'd1;
    end

    // ------------------------------------------------------------------
    // BCD counter 0-9
    // ------------------------------------------------------------------
    reg [3:0] value;
    always @(posedge clk) begin
        if (!rst_n)
            value <= 4'd0;
        else if (ena && tick && !pause) begin
            if (up)
                value <= (value == 4'd9) ? 4'd0 : value + 4'd1;
            else
                value <= (value == 4'd0) ? 4'd9 : value - 4'd1;
        end
    end

    // ------------------------------------------------------------------
    // 7-segment decoder. Active-high, a = bit 0: {g,f,e,d,c,b,a}
    //   Connects to the onboard common-cathode display on the demo board.
    // ------------------------------------------------------------------
    reg [6:0] seg;
    always @(*) begin
        case (value)
            4'd0: seg = 7'b011_1111; // 0x3F
            4'd1: seg = 7'b000_0110; // 0x06
            4'd2: seg = 7'b101_1011; // 0x5B
            4'd3: seg = 7'b100_1111; // 0x4F
            4'd4: seg = 7'b110_0110; // 0x66
            4'd5: seg = 7'b110_1101; // 0x6D
            4'd6: seg = 7'b111_1101; // 0x7D
            4'd7: seg = 7'b000_0111; // 0x07
            4'd8: seg = 7'b111_1111; // 0x7F
            4'd9: seg = 7'b110_1111; // 0x6F
            default: seg = 7'b000_0000;
        endcase
    end

    assign uo_out[6:0] = seg;
    assign uo_out[7]   = pause; // decimal point doubles as pause indicator
    assign uio_out     = 8'd0;
    assign uio_oe      = 8'd0;

    wire _unused = &{uio_in, ui_in[7:4], 1'b0};

endmodule
