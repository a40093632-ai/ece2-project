`timescale 1ns/1ps
// Same external port names and pin assignments as stopwatch_top.
// START arms a fixed relative reservation. CLEAR cancels. LED8 indicates load_en.
// Display: state digit (0/1/2/3), three zeros, remaining MM.SS (up to 99:59).
module scheduler_top #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer SCAN_HZ=4_000,
    parameter integer DEBOUNCE_MS=20,
    parameter [31:0] DELAY_SECONDS=5,
    parameter [31:0] DURATION_SECONDS=10
) (
    input wire clk_50mhz, rst_p, btn_start, btn_clear,
    output wire [7:0] seg_data, seg_com,
    output wire led_run
);
    localparam integer DB_CYCLES=(CLK_HZ/1000*DEBOUNCE_MS < 1) ? 1 : CLK_HZ/1000*DEBOUNCE_MS;
    (* ASYNC_REG="TRUE" *) reg [1:0] rst_pipe;
    always @(posedge clk_50mhz or posedge rst_p) begin
        if (rst_p) rst_pipe <= 2'b11;
        else rst_pipe <= {rst_pipe[0],1'b0};
    end
    wire rst=rst_pipe[1];
    wire start_pulse, cancel_pulse, tick_scan, unused_tick;
    wire [1:0] state;
    wire [31:0] remaining;
    wire config_error;
    button_onepulse #(.STABLE_CYCLES(DB_CYCLES)) start_button (
        .clk(clk_50mhz),.rst(rst),.btn_in(btn_start),.pulse(start_pulse));
    button_onepulse #(.STABLE_CYCLES(DB_CYCLES)) cancel_button (
        .clk(clk_50mhz),.rst(rst),.btn_in(btn_clear),.pulse(cancel_pulse));
    scheduler #(.CLK_HZ(CLK_HZ)) control (
        .clk(clk_50mhz),.rst(rst),.start(start_pulse),.cancel(cancel_pulse),
        .delay_seconds(DELAY_SECONDS),.duration_seconds(DURATION_SECONDS),
        .load_en(led_run),.state(state),.remaining_seconds(remaining),.config_error(config_error));
    tick_gen #(.CLK_HZ(CLK_HZ),.SCAN_HZ(SCAN_HZ)) ticks (
        .clk(clk_50mhz),.rst(rst),.tick_10ms(unused_tick),.tick_scan(tick_scan));
    wire [31:0] shown_seconds=(remaining>5999) ? 5999 : remaining;
    wire [3:0] minute_tens=shown_seconds/600;
    wire [3:0] minute_ones=(shown_seconds/60)%10;
    wire [3:0] second_tens=(shown_seconds%60)/10;
    wire [3:0] second_ones=shown_seconds%10;
    seg_scan8 display (
        .clk(clk_50mhz),.rst(rst),.tick_scan(tick_scan),
        .digits({2'b00,state,12'b0,minute_tens,minute_ones,second_tens,second_ones}),
        .dp(8'b00000100),.seg_data(seg_data),.seg_com(seg_com));
endmodule
