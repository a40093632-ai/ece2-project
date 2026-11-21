`timescale 1ns/1ps
// Integrated second-stage top. 1 reset;2 start/pause;3 local clear/cancel;4 mode;5 set.
module top #(
 parameter integer CLK_HZ=50_000_000,SCAN_HZ=4000,DEBOUNCE_MS=20,
 parameter integer BAUD=9600,
 parameter [31:0] DELAY_SECONDS=5,DURATION_SECONDS=10
)(
 input wire clk_50mhz,rst_p,btn_start,btn_clear,btn_mode,btn_set,uart_rx,
 output wire uart_tx,gate_en,
 output wire [7:0] led,seg_data,seg_com,
 output wire lcd_e,lcd_rs,lcd_rw,
 output wire [7:0] lcd_data
);
 localparam integer DB=(CLK_HZ/1000*DEBOUNCE_MS<1)?1:CLK_HZ/1000*DEBOUNCE_MS;
 (* ASYNC_REG="TRUE" *)reg [1:0] rst_pipe;
 always @(posedge clk_50mhz or posedge rst_p)begin
  if(rst_p)rst_pipe<=2'b11;else rst_pipe<={rst_pipe[0],1'b0};
 end
 wire rst=rst_pipe[1];
 wire sp,cp,mp,stp,tick_10ms,tick_scan,ws,wc,wr,raw_gate,unused_led_run;
 wire [1:0] page,item;
 wire ds,tv,mv,mseen;
 wire display_valid,display_energy_valid;
 wire [1:0] result_status;
 wire [2:0] state,weekday;
 wire [3:0] reason,mt,mo,ss_t,ss_o,ct,co;
 wire [31:0] remain,date_ymd,time_hms,vbus,current,power,frame_errors;
 wire [15:0] sid;
 wire [63:0] etotal,esession;
 button_onepulse #(.STABLE_CYCLES(DB)) b2(.clk(clk_50mhz),.rst(rst),.btn_in(btn_start),.pulse(sp));
 button_onepulse #(.STABLE_CYCLES(DB)) b3(.clk(clk_50mhz),.rst(rst),.btn_in(btn_clear),.pulse(cp));
 button_onepulse #(.STABLE_CYCLES(DB)) b4(.clk(clk_50mhz),.rst(rst),.btn_in(btn_mode),.pulse(mp));
 button_onepulse #(.STABLE_CYCLES(DB)) b5(.clk(clk_50mhz),.rst(rst),.btn_in(btn_set),.pulse(stp));
 tick_gen #(.CLK_HZ(CLK_HZ),.SCAN_HZ(SCAN_HZ)) tick(
  .clk(clk_50mhz),.rst(rst),.tick_10ms(tick_10ms),.tick_scan(tick_scan));
 reservation_control #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.DELAY_SECONDS(DELAY_SECONDS),.DURATION_SECONDS(DURATION_SECONDS)) control(
  .clk(clk_50mhz),.rst(rst),.uart_rx(uart_rx),.uart_tx(uart_tx),
  .start_pulse(sp),.clear_pulse(cp),.mode_pulse(mp),.set_pulse(stp),.gate_en(raw_gate),.led_run(unused_led_run),
  .page(page),.measure_item(item),.date_selected(ds),.watch_start(ws),.watch_clear(wc),
  .reservation_state(state),.reservation_reason(reason),.remaining_seconds(remain),.session_id(sid),
  .date_ymd(date_ymd),.time_hms(time_hms),.weekday(weekday),.time_valid(tv),
  .measure_valid(mv),.measure_received(mseen),.bus_mv(vbus),.current_ua(current),.power_uw(power),
  .display_valid(display_valid),.display_energy_valid(display_energy_valid),.result_status(result_status),
  .total_uwh(etotal),.session_uwh(esession),.frame_errors(frame_errors));
 assign gate_en=raw_gate && !rst_p && !rst;
 assign led[7]=gate_en;
 stopwatch watch(.clk(clk_50mhz),.rst(rst),.tick_10ms(tick_10ms),.start_pause(ws),.clear(wc),.running(wr),
  .min_t(mt),.min_o(mo),.sec_t(ss_t),.sec_o(ss_o),.cs_t(ct),.cs_o(co));
 wire [31:0] db,vb,ib,pb,eb,digits;
 wire [23:0] tb;
 wire [7:0] wb,dp;
 wire tready,mready,seen,overflow;
 display_value_adapter adapter(.clk(clk_50mhz),.rst(rst),.time_valid(tv),
  .measure_valid(item==3 ? display_energy_valid : display_valid),.measure_received(mseen),
  .date_ymd(date_ymd),.time_hms(time_hms),.weekday(weekday),.bus_mv(vbus),.current_ua(current),.power_uw(power),
  .total_uwh(esession),.date_bcd(db),.time_bcd(tb),.dow_bcd(wb),.meas_v_bcd(vb),.meas_i_bcd(ib),
  .meas_p_bcd(pb),.meas_e_bcd(eb),.time_ready(tready),.measure_ready(mready),.measure_seen(seen),.e_overflow(overflow));
 display_ctrl #(.CANCEL_ALL_SCREENS(0),.EXTERNAL_SELECTION(1)) display(
  .clk(clk_50mhz),.rst(rst),.tick_10ms(tick_10ms),.external_screen(page),.external_measure_item(item),.external_date_selected(ds),
  .mode_pulse(1'b0),.set_pulse(1'b0),.start_pulse(1'b0),.clear_pulse(1'b0),
  .time_valid(tv && tready),.date_bcd(db),.time_bcd(tb),.dow_bcd(wb),.sw_bcd({mt,mo,ss_t,ss_o,ct,co}),.sw_running(wr),
  .rsv_state(state),.rsv_remain_s(remain),.rsv_wait(state==1 || state==4),.rsv_run(state==2),.rsv_fault(state==5),
  .meas_rx(mready),.meas_valid(mready),.e_overflow(overflow),.meas_v_bcd(vb),.meas_i_bcd(ib),.meas_p_bcd(pb),.meas_e_bcd(eb),
  .sw_start_pause(),.sw_clear(),.rsv_start(),.rsv_cancel(),.fault_ack(),.screen(),.digits(digits),.dp(dp),.led(led[6:0]));
 seg_scan8 scan(.clk(clk_50mhz),.rst(rst),.tick_scan(tick_scan),.digits(digits),.dp(dp),.seg_data(seg_data),.seg_com(seg_com));
 // LCD is an additional display sink; it cannot change reservation/Gate logic.
 wire [127:0] lcd_line1,lcd_line2;
 project_lcd_format lcd_text(
  .clk(clk_50mhz),.rst(rst),
  .page(page),.measure_item(item),.time_valid(tv && tready),
  .measure_valid(mready),.measure_seen(seen),.e_overflow(overflow),.result_status(result_status),
  .sw_running(wr),.gate_en(gate_en),.date_bcd(db),.time_bcd(tb),.dow_bcd(wb),
  .sw_bcd({mt,mo,ss_t,ss_o,ct,co}),.rsv_state(state),.rsv_reason(reason),
  .rsv_remain_s(remain),.meas_v_bcd(vb),.meas_i_bcd(ib),.meas_p_bcd(pb),.meas_e_bcd(eb),
  .line1(lcd_line1),.line2(lcd_line2));
 project_lcd_driver #(.CLK_HZ(CLK_HZ)) lcd(
  .clk(clk_50mhz),.rst(rst),.line1(lcd_line1),.line2(lcd_line2),
  .lcd_e(lcd_e),.lcd_rs(lcd_rs),.lcd_rw(lcd_rw),.lcd_data(lcd_data));
endmodule
