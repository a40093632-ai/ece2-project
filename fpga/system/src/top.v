`timescale 1ns/1ps
module top #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer SCAN_HZ=4000,
    parameter integer DEBOUNCE_MS=20,
    parameter [31:0] DELAY_SECONDS=5,
    parameter [31:0] DURATION_SECONDS=10
) (
    input wire clk_50mhz, rst_p, btn_start, btn_clear, btn_mode,
    output wire [7:0] seg_data, seg_com,
    output wire led_run
);
    localparam integer DB_CYCLES=(CLK_HZ/1000*DEBOUNCE_MS<1)?1:CLK_HZ/1000*DEBOUNCE_MS;
    (* ASYNC_REG="TRUE" *) reg [1:0] rst_pipe;
    always @(posedge clk_50mhz or posedge rst_p) begin
        if(rst_p) rst_pipe<=2'b11;
        else rst_pipe<={rst_pipe[0],1'b0};
    end
    wire rst=rst_pipe[1];
    wire start_pulse, clear_pulse, mode_pulse, tick_10ms, tick_scan;
    reg mode;
    always @(posedge clk_50mhz or posedge rst) begin
        if(rst) mode<=0;
        else if(mode_pulse) mode<=~mode;
    end
    button_onepulse #(.STABLE_CYCLES(DB_CYCLES)) start_button (
        .clk(clk_50mhz),.rst(rst),.btn_in(btn_start),.pulse(start_pulse));
    button_onepulse #(.STABLE_CYCLES(DB_CYCLES)) clear_button (
        .clk(clk_50mhz),.rst(rst),.btn_in(btn_clear),.pulse(clear_pulse));
    button_onepulse #(.STABLE_CYCLES(DB_CYCLES)) mode_button (
        .clk(clk_50mhz),.rst(rst),.btn_in(btn_mode),.pulse(mode_pulse));
    tick_gen #(.CLK_HZ(CLK_HZ),.SCAN_HZ(SCAN_HZ)) ticks (
        .clk(clk_50mhz),.rst(rst),.tick_10ms(tick_10ms),.tick_scan(tick_scan));
    wire [3:0] min_t,min_o,sec_t,sec_o,cs_t,cs_o;
    wire stopwatch_running;
    // A simultaneous mode press does not start either function.
    stopwatch watch (
        .clk(clk_50mhz),.rst(rst),.tick_10ms(tick_10ms),
        .start_pause(start_pulse && !mode && !mode_pulse),.clear(clear_pulse),
        .running(stopwatch_running),.min_t(min_t),.min_o(min_o),
        .sec_t(sec_t),.sec_o(sec_o),.cs_t(cs_t),.cs_o(cs_o));
    wire [1:0] schedule_state;
    wire [31:0] remaining;
    wire schedule_config_error;
    scheduler #(.CLK_HZ(CLK_HZ)) reservation (
        .clk(clk_50mhz),.rst(rst),.start(start_pulse && mode && !mode_pulse),
        .cancel(clear_pulse),.delay_seconds(DELAY_SECONDS),.duration_seconds(DURATION_SECONDS),
        .load_en(led_run),.state(schedule_state),.remaining_seconds(remaining),
        .config_error(schedule_config_error));
    wire [31:0] shown=(remaining>5999)?5999:remaining;
    wire [3:0] mt=shown/600, mo=(shown/60)%10;
    wire [3:0] st=(shown%60)/10, so=shown%10;
    wire [31:0] watch_digits={4'b0,4'b0,min_t,min_o,sec_t,sec_o,cs_t,cs_o};
    wire [31:0] reservation_digits={2'b0,schedule_state,12'b0,mt,mo,st,so};
    seg_scan8 display (
        .clk(clk_50mhz),.rst(rst),.tick_scan(tick_scan),
        .digits(mode?reservation_digits:watch_digits),
        .dp(mode?8'b00000100:8'b00010100),.seg_data(seg_data),.seg_com(seg_com));
endmodule
