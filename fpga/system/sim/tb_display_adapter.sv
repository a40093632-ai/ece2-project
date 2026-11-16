`timescale 1ns/1ps
module tb_display_adapter;
 reg clk=0,rst=1,tv=1,mv=1,mr=1;always #5 clk=~clk;
 reg [31:0] date_in=20261116,time_in=123456,v=5000,i=100800,p=477500;
 reg [2:0] day=1;reg [63:0] e=694;
 wire [31:0] db,vb,ib,pb,eb;wire [23:0] tb;wire [7:0] dow;
 wire tr,mready,seen,overflow;
 display_value_adapter dut(.clk(clk),.rst(rst),.time_valid(tv),.measure_valid(mv),.measure_received(mr),
  .date_ymd(date_in),.time_hms(time_in),.weekday(day),.bus_mv(v),.current_ua(i),.power_uw(p),.total_uwh(e),
  .date_bcd(db),.time_bcd(tb),.dow_bcd(dow),.meas_v_bcd(vb),.meas_i_bcd(ib),.meas_p_bcd(pb),.meas_e_bcd(eb),
  .time_ready(tr),.measure_ready(mready),.measure_seen(seen),.e_overflow(overflow));
 integer checks=0;
 task automatic settle;repeat(70)@(negedge clk);endtask
 task automatic check(input bit condition,input string label_text);
  checks++;if(!condition)$fatal(1,"adapter FAIL %s",label_text);
 endtask
 initial begin
  repeat(4)@(negedge clk);rst=0;settle();
  check(db==32'h20261116 && tb==24'h123456 && dow==1,"date/time coherent snapshot");
  check(vb==32'h00005000 && ib==32'h00010080 && pb==32'h00004775 && eb==32'h00000694,"units and decimal scaling");
  date_in=20000229;time_in=0;day=2;i=999999;p=999999;settle();
  check(db==32'h20000229 && tb==0 && dow==2,"leap date and midnight");
  check(ib==32'h00099999 && pb==32'h00009999,"decimal truncation");
  e=100000000;settle();check(overflow && eb==32'h99999999,"energy overflow flag");
  tv=0;mv=0;settle();check(!tr && !mready && seen,"invalid flags");
  $display("DISPLAY ADAPTER PASS checks=%0d",checks);$finish;
 end
endmodule
