`timescale 1ns/1ps
// Parallel double-dabble over 32 clocks; coherent BCD snapshots for the peer display.
module display_value_adapter(
 input wire clk,rst,time_valid,measure_valid,measure_received,
 input wire [31:0] date_ymd,time_hms,bus_mv,current_ua,power_uw,
 input wire [2:0] weekday,
 input wire [63:0] total_uwh,
 output reg [31:0] date_bcd,meas_v_bcd,meas_i_bcd,meas_p_bcd,meas_e_bcd,
 output reg [23:0] time_bcd,
 output reg [7:0] dow_bcd,
 output reg time_ready,measure_ready,measure_seen,e_overflow
);
 reg [31:0] bin[0:6],bcd[0:6];
 reg [5:0] count;
 reg tv,mv,mr,ov;
 integer i;
 function [31:0] step;
  input [31:0] value;input bit_in;
  reg [31:0] adjusted;integer n;
  begin
   adjusted=value;
   for(n=0;n<8;n=n+1)if(adjusted[n*4+:4]>=5)adjusted[n*4+:4]=adjusted[n*4+:4]+3;
   step={adjusted[30:0],bit_in};
  end
 endfunction
 wire [31:0] full_i_bcd=step(bcd[4],bin[4][31]);
 wire [31:0] full_p_bcd=step(bcd[5],bin[5][31]);
 always @(posedge clk)begin
  if(rst)begin
   count<=0;date_bcd<=0;time_bcd<=0;dow_bcd<=0;meas_v_bcd<=0;meas_i_bcd<=0;meas_p_bcd<=0;meas_e_bcd<=0;
   time_ready<=0;measure_ready<=0;measure_seen<=0;e_overflow<=0;tv<=0;mv<=0;mr<=0;ov<=0;
   for(i=0;i<7;i=i+1)begin bin[i]<=0;bcd[i]<=0;end
  end else if(count==0)begin
   bin[0]<=date_ymd;bin[1]<=time_hms;bin[2]<={29'b0,weekday};bin[3]<=bus_mv;
   // Convert original integer units first; decimal scaling is then a BCD slice.
   bin[4]<=current_ua;bin[5]<=power_uw;
   bin[6]<=total_uwh>99999999?99999999:total_uwh[31:0];
   tv<=time_valid;mv<=measure_valid;mr<=measure_received;ov<=total_uwh>99999999;
   for(i=0;i<7;i=i+1)bcd[i]<=0;
   count<=1;
  end else begin
   for(i=0;i<7;i=i+1)begin bcd[i]<=step(bcd[i],bin[i][31]);bin[i]<=bin[i]<<1;end
   if(count==32)begin
    date_bcd<=step(bcd[0],bin[0][31]);time_bcd<=step(bcd[1],bin[1][31]);dow_bcd<=step(bcd[2],bin[2][31]);
    meas_v_bcd<=step(bcd[3],bin[3][31]);meas_i_bcd<={4'b0,full_i_bcd[31:4]};
    meas_p_bcd<={8'b0,full_p_bcd[31:8]};meas_e_bcd<=step(bcd[6],bin[6][31]);
    time_ready<=tv;measure_ready<=mv;measure_seen<=mr;e_overflow<=ov;count<=0;
   end else count<=count+1'b1;
  end
 end
endmodule
