`timescale 1ns/1ps
// 스톱워치 보드 단독 시험용 top
//   btn_start : START/PAUSE, btn_clear : 초기화+정지, rst_p : 전체 리셋
//   표시 : 0 0 M M. S S. c c,  led_run : 실행 중 켜짐
module stopwatch_top #(
    parameter integer CLK_HZ      = 50_000_000,
    parameter integer SCAN_HZ     = 4_000,
    parameter integer DEBOUNCE_MS = 20
) (
    input  wire       clk_50mhz,
    input  wire       rst_p,
    input  wire       btn_start,
    input  wire       btn_clear,
    output wire [7:0] seg_data,
    output wire [7:0] seg_com,
    output wire       led_run
);
    localparam integer DEBOUNCE_CYCLES =
        (CLK_HZ / 1000 * DEBOUNCE_MS < 1) ? 1 : CLK_HZ / 1000 * DEBOUNCE_MS;

    // 리셋: 누르면 바로 리셋, 뗀 뒤 2클록 후 해제
    (* ASYNC_REG = "TRUE" *) reg [1:0] rst_pipe;
    wire rst = rst_pipe[1];
    always @(posedge clk_50mhz or posedge rst_p) begin
        if (rst_p) rst_pipe <= 2'b11;
        else       rst_pipe <= {rst_pipe[0], 1'b0};
    end

    wire tick_10ms, tick_scan;
    wire start_pulse, clear_pulse;
    wire [3:0] min_t, min_o, sec_t, sec_o, cs_t, cs_o;

    tick_gen #(.CLK_HZ(CLK_HZ), .SCAN_HZ(SCAN_HZ)) u_tick (
        .clk(clk_50mhz), .rst(rst),
        .tick_10ms(tick_10ms), .tick_scan(tick_scan));

    button_onepulse #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_btn_start (
        .clk(clk_50mhz), .rst(rst), .btn_in(btn_start), .pulse(start_pulse));

    button_onepulse #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) u_btn_clear (
        .clk(clk_50mhz), .rst(rst), .btn_in(btn_clear), .pulse(clear_pulse));

    stopwatch u_sw (
        .clk(clk_50mhz), .rst(rst), .tick_10ms(tick_10ms),
        .start_pause(start_pulse), .clear(clear_pulse),
        .running(led_run),
        .min_t(min_t), .min_o(min_o), .sec_t(sec_t), .sec_o(sec_o),
        .cs_t(cs_t), .cs_o(cs_o));

    seg_scan8 u_disp (
        .clk(clk_50mhz), .rst(rst), .tick_scan(tick_scan),
        .digits({4'd0, 4'd0, min_t, min_o, sec_t, sec_o, cs_t, cs_o}),
        .dp(8'b0001_0100),
        .seg_data(seg_data), .seg_com(seg_com));
endmodule