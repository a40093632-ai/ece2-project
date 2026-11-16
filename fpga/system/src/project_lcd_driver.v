`timescale 1ns/1ps
// Combo II-DLD S75 16x2 LCD, 8-bit write-only interface.
// Clock-enable at 10 us: 50 ms startup, three function sets with 5 ms recovery,
// >=2 ms clear recovery, 10 us setup and E-high, >=50 us ordinary recovery.
// Capture both rows together at frame start; never clear during refresh.
module project_lcd_driver #(
 parameter integer CLK_HZ=50_000_000,
 parameter integer POWER_TICKS=5000, REFRESH_TICKS=10000
)(
 input wire clk,rst,
 input wire [127:0] line1,line2,
 output reg lcd_e,lcd_rs,
 output wire lcd_rw,
 output reg [7:0] lcd_data
);
 localparam integer DIV=(CLK_HZ/100000<1)?1:CLK_HZ/100000;
 localparam integer CW=(DIV<2)?1:$clog2(DIV);
 reg [CW-1:0] count;
 wire tick=(count==DIV-1);
 reg [1:0] phase;
 reg [5:0] index;
 integer power_wait,byte_wait;
 reg [127:0] row1,row2;
 reg next_rs;
 reg [7:0] next_data;
 assign lcd_rw=1'b0;
 always @* begin
  next_rs=1'b0;next_data=8'h00;
  case(index)
   0,1,2:next_data=8'h38; // 8-bit, 2 rows, 5x8 font
   3:next_data=8'h08;     // display off
   4:next_data=8'h01;     // clear once during initialization
   5:next_data=8'h06;     // increment, no shift
   6:next_data=8'h0c;     // display on, cursor/blink off
   7:next_data=8'h80;
   24:next_data=8'hc0;
   default:begin
    next_rs=1'b1;
    if(index>=8 && index<=23)next_data=row1[127-(index-8)*8 -: 8];
    else if(index>=25 && index<=40)next_data=row2[127-(index-25)*8 -: 8];
    else next_data=8'h20;
   end
  endcase
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   count<=0;phase<=0;index<=0;power_wait<=0;byte_wait<=0;
   lcd_e<=0;lcd_rs<=0;lcd_data<=0;row1<=0;row2<=0;
  end else begin
   if(tick)count<=0;else count<=count+1'b1;
   if(tick)begin
    if(power_wait<POWER_TICKS)begin power_wait<=power_wait+1;lcd_e<=0;end
    else case(phase)
     0:begin
      if(index==7)begin row1<=line1;row2<=line2;end
      lcd_e<=0;lcd_rs<=next_rs;lcd_data<=next_data;phase<=1;
     end
     1:begin lcd_e<=1;phase<=2;end
     2:begin
      lcd_e<=0;phase<=3;
      if(index<=2)byte_wait<=500;
      else if(index==4)byte_wait<=200;
      else if(index==40)byte_wait<=(REFRESH_TICKS<5)?5:REFRESH_TICKS;
      else byte_wait<=5;
     end
     3:begin
      if(byte_wait>0)byte_wait<=byte_wait-1;
      else begin index<=(index==40)?7:index+1'b1;phase<=0;end
     end
    endcase
   end
  end
 end
endmodule
