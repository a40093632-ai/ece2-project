`timescale 1ns/1ps
// Reservation/integration owner's core. Display and STM firmware connect at these ports.
// CLK_HZ >=1000, divisible by 1000. rst: synchronized active high.
module reservation_control #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer BAUD=9600,
    parameter [31:0] DELAY_SECONDS=5,DURATION_SECONDS=10
)(
    input wire clk,rst,uart_rx,
    input wire start_pulse,clear_pulse,mode_pulse,set_pulse,
    output wire uart_tx,gate_en,led_run,
    output wire [1:0] page,measure_item,
    output wire date_selected,watch_start,watch_clear,
    output wire [2:0] reservation_state,
    output wire [3:0] reservation_reason,
    output wire [31:0] remaining_seconds,
    output wire [15:0] session_id,
    output reg [31:0] date_ymd,time_hms,
    output reg [2:0] weekday,
    output reg time_valid,
    output wire measure_valid,
    output reg measure_received,
    output reg [31:0] bus_mv,current_ua,power_uw,
    output reg [63:0] total_uwh,session_uwh,
    output reg [31:0] frame_errors
);
    wire [7:0] byte_rx,byte_tx;
    wire rx_valid,rx_error,tx_valid,tx_ready;
    wire time_event,measure_event,frame_error,t_ok,m_ok,ack;
    wire [15:0] t_seq,m_seq,m_session;
    wire [31:0] t_date,t_time,m_v,m_i,m_p;
    wire [2:0] t_day;
    wire [63:0] m_total,m_session_e;
    wire res_start,res_cancel,fresh_measure;
    reg have_time;
    reg [15:0] last_time_seq;
    reg [31:0] time_age;
    wire [15:0] time_delta=t_seq-last_time_seq;
    wire fresh_time=time_event && (!have_time || (time_delta!=0 && !time_delta[15]));
    assign led_run=gate_en;
    stage2_button_router buttons(.clk(clk),.rst(rst),.start_pulse(start_pulse),
        .clear_pulse(clear_pulse),.mode_pulse(mode_pulse),.set_pulse(set_pulse),
        .page(page),.date_selected(date_selected),.measure_item(measure_item),
        .watch_start(watch_start),.watch_clear(watch_clear),
        .reservation_start(res_start),.reservation_cancel(res_cancel));
    project_uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) rx_unit(
        .clk(clk),.rst(rst),.rx(uart_rx),.data(byte_rx),.data_valid(rx_valid),.framing_error(rx_error));
    project_frame_rx #(.CLK_HZ(CLK_HZ)) parser(
        .clk(clk),.rst(rst),.byte_data(byte_rx),.byte_valid(rx_valid),.byte_error(rx_error),
        .time_event(time_event),.measure_event(measure_event),.frame_error(frame_error),
        .time_seq(t_seq),.measure_seq(m_seq),.measure_session(m_session),
        .date_ymd(t_date),.time_hms(t_time),.weekday(t_day),.time_ok(t_ok),
        .measure_ok(m_ok),.session_ack(ack),.bus_mv(m_v),.current_ua(m_i),.power_uw(m_p),
        .total_uwh(m_total),.session_uwh(m_session_e));
    scheduler_guarded #(.CLK_HZ(CLK_HZ)) reservation(
        .clk(clk),.rst(rst),.start(res_start),.cancel(res_cancel),
        .delay_seconds(DELAY_SECONDS),.duration_seconds(DURATION_SECONDS),
        .measure_event(measure_event),.measure_ok(m_ok),.session_ack(ack),
        .measure_seq(m_seq),.measure_session(m_session),.load_en(gate_en),
        .measure_healthy(measure_valid),.state(reservation_state),.reason(reservation_reason),
        .remaining_seconds(remaining_seconds),.session_id(session_id),.fresh_measure(fresh_measure));
    project_status_tx #(.CLK_HZ(CLK_HZ)) status(
        .clk(clk),.rst(rst),.state(reservation_state),.reason(reservation_reason),
        .session_id(session_id),.remaining_seconds(remaining_seconds),.load_en(gate_en),
        .byte_ready(tx_ready),.byte_valid(tx_valid),.byte_data(byte_tx));
    project_uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) tx_unit(
        .clk(clk),.rst(rst),.valid(tx_valid),.data(byte_tx),.ready(tx_ready),.tx(uart_tx));
    always @(posedge clk)begin
        if(rst)begin
            measure_received<=0;have_time<=0;last_time_seq<=0;time_age<=3*CLK_HZ;time_valid<=0;
            date_ymd<=0;time_hms<=0;weekday<=0;bus_mv<=0;current_ua<=0;power_uw<=0;
            total_uwh<=0;session_uwh<=0;frame_errors<=0;
        end else begin
            if(fresh_time)begin
                have_time<=1;last_time_seq<=t_seq;time_age<=0;time_valid<=t_ok;
                if(t_ok)begin date_ymd<=t_date;time_hms<=t_time;weekday<=t_day; end
            end else if(time_age<3*CLK_HZ)time_age<=time_age+1'b1;
            if(!fresh_time && time_age>=3*CLK_HZ-1)begin
                time_valid<=0;have_time<=0; // Re-acquire sequence after MCU reboot/disconnect.
            end
            if(measure_event)measure_received<=1;
            if(fresh_measure)begin
                bus_mv<=m_v;current_ua<=m_i;power_uw<=m_p;total_uwh<=m_total;
                if(m_session==session_id && ack)session_uwh<=m_session_e;
            end
            if(reservation_state==4)session_uwh<=0; // Awaiting a new execution baseline.
            if(frame_error && frame_errors!=32'hffffffff)frame_errors<=frame_errors+1'b1;
        end
    end
endmodule
