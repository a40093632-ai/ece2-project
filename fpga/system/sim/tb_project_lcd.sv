`timescale 1ns/1ps
module tb_project_lcd;
 reg clk=0,rst=1;
 always #5000 clk=~clk; // 100 kHz test clock; each driver tick remains 10 us.
 reg [1:0] page=0,item=0;
 reg [2:0] result_status=0;
 reg tv=0,mv=1,seen=1,overflow=0,run=0,gate=0;
 reg [2:0] state=0;reg [3:0] reason=0;
 reg [31:0] remain=0;
 wire [127:0] l1,l2;
 project_lcd_format fmt(
  .clk(clk),.rst(rst),
  .page(page),.measure_item(item),.time_valid(tv),.measure_valid(mv),.measure_seen(seen),.result_status(result_status),
  .e_overflow(overflow),.sw_running(run),.gate_en(gate),.date_bcd(32'h20261116),
  .time_bcd(24'h123456),.dow_bcd(8'h01),.sw_bcd(24'h010203),
  .rsv_state(state),.rsv_reason(reason),.rsv_remain_s(remain),
  .meas_v_bcd(32'h00005000),.meas_i_bcd(32'h00010080),.meas_p_bcd(32'h00004775),
  .meas_e_bcd(32'h00000694),.line1(l1),.line2(l2));
 integer checks=0;
 task automatic rows(input [127:0] a,b);
  repeat(70)@(negedge clk);#1;checks++;
  if(l1!==a || l2!==b)$fatal(1,"LCD text mismatch: '%s'/'%s', expected '%s'/'%s'",l1,l2,a,b);
 endtask
 initial begin
  rows("CLOCK           ","WAIT PC TIME    ");
  tv=1;rows("DATE 2026-11-16 ","12:34:56 MON    ");
  page=1;rows("STOPWATCH PAUSE ","01:02.03        ");
  run=1;rows("STOPWATCH RUN   ","01:02.03        ");
  page=2;rows("RSV 0 IDLE  OFF ","LEFT 0000000 s  ");
  state=4;rows("RSV 4 ARM   OFF ","LEFT 0000000 s  ");
  state=1;remain=5;rows("RSV 1 WAIT  OFF ","LEFT 0000005 s  ");
  state=2;remain=10;gate=1;rows("RSV 2 RUN   ON  ","LEFT 0000010 s  ");
  state=3;remain=0;gate=0;rows("RSV 3 DONE  OFF ","LEFT 0000000 s  ");
  state=5;reason=3;rows("RSV 5 FAULT OFF ","MEAS INVALID    ");
  reason=4;rows("RSV 5 FAULT OFF ","MEAS TIMEOUT    ");
  reason=5;rows("RSV 5 FAULT OFF ","ARM TIMEOUT     ");
  reason=6;rows("RSV 5 FAULT OFF ","CONFIG ERROR    ");
  reason=7;rows("RSV 5 FAULT OFF ","SESSION LOST    ");
  page=3;rows("V BUS           ","00005.000 V     ");
  item=1;rows("I LOAD          ","000100.80 mA    ");
  item=2;rows("P LOAD          ","0000477.5 mW    ");
  item=3;rows("E SESSION       ","00000.694 mWh   ");
  result_status=4;rows("E SESSION       ","0.000 mWh       ");
  item=0;rows("V BUS           ","NO RUN DATA     ");
  item=3;result_status=1;rows("E SESSION       ","RESULT PENDING  ");
  result_status=3;rows("E SESSION       ","RESULT MISSING  ");
  result_status=2;rows("E SESSIONPARTIAL","00000.694 mWh   ");
  mv=0;rows("E SESSIONPARTIAL","NO VALID SAMPLE ");
  mv=1;result_status=0;overflow=1;rows("E SESSION       ","VALUE OVERFLOW  ");
  mv=0;rows("E SESSION       ","MEAS INVALID    ");
  seen=0;rows("E SESSION       ","NO MCU DATA     ");
 end

 reg [127:0] src1="AAAAAAAAAAAAAAAA",src2="BBBBBBBBBBBBBBBB";
 wire en,rs,rw;wire [7:0] data;
 project_lcd_driver #(.CLK_HZ(100000),.REFRESH_TICKS(20)) driver(
  .clk(clk),.rst(rst),.line1(src1),.line2(src2),.lcd_e(en),.lcd_rs(rs),.lcd_rw(rw),.lcd_data(data));
 integer n=0,k;reg expected_rs;reg [7:0] expected;
 time raised,last_fall;
 always @(posedge en)if(!rst)raised=$time;
 always @(negedge en)if(!rst)begin
  if(rw!==0)$fatal(1,"LCD must stay write-only");
  if($time-raised<10000)$fatal(1,"E pulse too short");
  if(n==0 && $time<50000000)$fatal(1,"LCD power-up wait too short");
  if(n>=1 && n<=3 && $time-last_fall<5000000)$fatal(1,"Function-set recovery too short");
  if(n==5 && $time-last_fall<2000000)$fatal(1,"Clear recovery too short");
  expected_rs=0;
  if(n<7)case(n)
   0,1,2:expected=8'h38;3:expected=8'h08;4:expected=8'h01;5:expected=8'h06;6:expected=8'h0c;
  endcase
  else begin
   k=(n-7)%34;
   if(k==0)expected=8'h80;
   else if(k==17)expected=8'hc0;
   else begin expected_rs=1;expected=(n<41)?((k<17)?"A":"B"):((k<17)?"Z":"Y");end
  end
  if(rs!==expected_rs || data!==expected)$fatal(1,"LCD byte %0d: RS=%b data=%h expected %b/%h",n,rs,data,expected_rs,expected);
  if(n==8)begin src1="ZZZZZZZZZZZZZZZZ";src2="YYYYYYYYYYYYYYYY";end
  last_fall=$time;n++;
  if(n==75)begin
   $display("LCD PASS: %0d text cases, %0d bus bytes, initialization/timing/snapshot/refresh",checks,n);$finish;
  end
 end
 initial begin #20000;rst=0;#200000000;$fatal(1,"LCD test timeout");end
endmodule
