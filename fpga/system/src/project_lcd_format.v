`timescale 1ns/1ps
// ASCII formatter; units match the existing seven-segment display adapter.
// Date/time on both LCD rows; SET still selects the seven-segment date/time.
module project_lcd_format(
 input wire clk,rst,
 input wire [1:0] page,measure_item,
 input wire time_valid,measure_valid,measure_seen,e_overflow,sw_running,gate_en,
 input wire [31:0] date_bcd,meas_v_bcd,meas_i_bcd,meas_p_bcd,meas_e_bcd,
 input wire [23:0] time_bcd,sw_bcd,
 input wire [7:0] dow_bcd,
 input wire [2:0] rsv_state,
 input wire [3:0] rsv_reason,
 input wire [31:0] rsv_remain_s,
 output reg [127:0] line1,line2
);
 function [7:0] digit(input [3:0] n);
  begin digit=(n<=9)?(8'h30+{4'b0,n}):8'h3f;end
 endfunction
 function [63:0] ascii8(input [31:0] bcd);
  integer i;
  begin for(i=0;i<8;i=i+1)ascii8[i*8+:8]=digit(bcd[i*4+:4]);end
 endfunction
 wire [63:0] d=ascii8(date_bcd),t=ascii8({8'b0,time_bcd}),w=ascii8({8'b0,sw_bcd});
 wire [63:0] v=ascii8(meas_v_bcd),a=ascii8(meas_i_bcd),p=ascii8(meas_p_bcd),e=ascii8(meas_e_bcd);
 wire [31:0] remain_bcd;
 remaining_seconds_bcd convert_remaining(.clk(clk),.rst(rst),.value(rsv_remain_s),.result(remain_bcd));
 wire [63:0] rem=ascii8(remain_bcd);
 reg [23:0] weekday;
 reg [39:0] state_name;
 always @* begin
  case(dow_bcd)
   8'h01:weekday="MON";8'h02:weekday="TUE";8'h03:weekday="WED";
   8'h04:weekday="THU";8'h05:weekday="FRI";8'h06:weekday="SAT";
   8'h07:weekday="SUN";default:weekday="---";
  endcase
  case(rsv_state)
   0:state_name="IDLE ";1:state_name="WAIT ";2:state_name="RUN  ";
   3:state_name="DONE ";4:state_name="ARM  ";5:state_name="FAULT";
   default:state_name="?????";
  endcase
  line1="                ";line2="                ";
  case(page)
   0:begin
    if(time_valid)begin
     line1={"DATE ",d[63:32],"-",d[31:16],"-",d[15:0]," "};
     line2={t[47:32],":",t[31:16],":",t[15:0]," ",weekday,"    "};
    end else begin line1="CLOCK           ";line2="WAIT PC TIME    ";end
   end
   1:begin
    line1=sw_running?"STOPWATCH RUN   ":"STOPWATCH PAUSE ";
    line2={w[47:32],":",w[31:16],".",w[15:0],"        "};
   end
   2:begin
    line1={"RSV ",digit({1'b0,rsv_state})," ",state_name," ",gate_en?"ON ":"OFF"," "};
    line2={"LEFT ",rem[55:0]," s  "};
    if(rsv_state==5)case(rsv_reason)
     3:line2="MEAS INVALID    ";4:line2="MEAS TIMEOUT    ";
     5:line2="ARM TIMEOUT     ";6:line2="CONFIG ERROR    ";
     7:line2="SESSION LOST    ";default:line2="CHECK MCU       ";
    endcase
   end
   3:begin
    case(measure_item)
     0:begin line1="V BUS           ";line2={v," mV     "};end
     1:begin line1="I LOAD          ";line2={a[63:16],".",a[15:0]," mA    "};end
     2:begin line1="P LOAD          ";line2={p[63:8],".",p[7:0]," mW    "};end
     3:begin line1="E TOTAL         ";line2={e[63:24],".",e[23:0]," mWh   "};end
    endcase
    if(!measure_seen)line2="NO MCU DATA     ";
    else if(!measure_valid)line2="MEAS INVALID    ";
    else if(measure_item==3 && e_overflow)line2="VALUE OVERFLOW  ";
   end
  endcase
 end
endmodule
