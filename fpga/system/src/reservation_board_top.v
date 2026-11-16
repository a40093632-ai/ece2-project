`timescale 1ns/1ps
// Standalone reservation/communications bring-up top; no seven-segment display.
// Final system uses reservation_control + the other member's display/stopwatch.
module reservation_board_top #(
    parameter integer CLK_HZ=50_000_000,BAUD=9600,DEBOUNCE_MS=20
)(
    input wire clk_50mhz,rst_p,btn_start,btn_clear,btn_mode,btn_set,
    input wire uart_rx,
    output wire uart_tx,gate_en,
    output wire [7:0] led
);
    localparam integer DB=(CLK_HZ/1000)*DEBOUNCE_MS;
    (* ASYNC_REG="TRUE" *)reg [1:0] rst_pipe;
    always @(posedge clk_50mhz or posedge rst_p)begin
        if(rst_p)rst_pipe<=2'b11;
        else rst_pipe<={rst_pipe[0],1'b0};
    end
    wire rst=rst_pipe[1];
    wire start_pulse,clear_pulse,mode_pulse,set_pulse;
    wire [1:0] page,measure_item;
    wire [2:0] state,weekday;
    wire [3:0] reason;
    wire [31:0] remaining,date_ymd,time_hms,bus_mv,current_ua,power_uw,frame_errors;
    wire [15:0] session_id;
    wire [63:0] total_uwh,session_uwh;
    wire date_selected,watch_start,watch_clear,time_valid,measure_valid,led_run;
    button_onepulse #(.STABLE_CYCLES(DB)) b2(.clk(clk_50mhz),.rst(rst),.btn_in(btn_start),.pulse(start_pulse));
    button_onepulse #(.STABLE_CYCLES(DB)) b3(.clk(clk_50mhz),.rst(rst),.btn_in(btn_clear),.pulse(clear_pulse));
    button_onepulse #(.STABLE_CYCLES(DB)) b4(.clk(clk_50mhz),.rst(rst),.btn_in(btn_mode),.pulse(mode_pulse));
    button_onepulse #(.STABLE_CYCLES(DB)) b5(.clk(clk_50mhz),.rst(rst),.btn_in(btn_set),.pulse(set_pulse));
    wire gate_internal;
    // Asserted physical reset suppresses Gate even before reset synchronization.
    assign gate_en=gate_internal && !rst_p && !rst;
    assign led={gate_en,measure_valid,time_valid,page,state};
    reservation_control #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) core(
        .clk(clk_50mhz),.rst(rst),.uart_rx(uart_rx),.uart_tx(uart_tx),
        .start_pulse(start_pulse),.clear_pulse(clear_pulse),.mode_pulse(mode_pulse),.set_pulse(set_pulse),
        .gate_en(gate_internal),.led_run(led_run),.page(page),.measure_item(measure_item),
        .date_selected(date_selected),.watch_start(watch_start),.watch_clear(watch_clear),
        .reservation_state(state),.reservation_reason(reason),.remaining_seconds(remaining),
        .session_id(session_id),.date_ymd(date_ymd),.time_hms(time_hms),.weekday(weekday),
        .time_valid(time_valid),.measure_valid(measure_valid),.bus_mv(bus_mv),
        .current_ua(current_ua),.power_uw(power_uw),.total_uwh(total_uwh),.session_uwh(session_uwh),
        .frame_errors(frame_errors));
endmodule
