`timescale 1ns/1ps
// Coherent S snapshots, sequential decimal conversion and checksum construction.
module project_status_tx #(
 parameter integer CLK_HZ=50_000_000,PERIOD_MS=200
)(
 input wire clk,rst,input wire [2:0] state,input wire [3:0] reason,
 input wire [15:0] session_id,input wire [31:0] remaining_seconds,
 input wire load_en,byte_ready,output wire byte_valid,output wire [7:0] byte_data
);
 localparam integer PERIOD=(CLK_HZ/1000)*PERIOD_MS;
 localparam [1:0] IDLE=0,CONVERT=1,BUILD=2,SEND=3;
 reg [1:0] phase;
 reg [7:0] frame[0:27];reg [4:0] index;
 reg [5:0] convert_count;
 reg [31:0] bits_left;
 reg [19:0] bcd,adjusted;
 reg sent_once,snapshot_gate;
 reg [15:0] sequence_no,snapshot_sequence,last_session;
 reg [2:0] last_state;reg [3:0] last_reason;
 reg [31:0] count;
 reg [7:0] checksum,next_byte;
 integer j,k;
 function [7:0] h(input [3:0] n);
  begin h=(n<10)?8'h30+{4'b0,n}:8'h41+{4'b0,n}-8'd10;end
 endfunction
 assign byte_valid=(phase==SEND) && !rst;
 assign byte_data=frame[index];
 always @* begin
  adjusted=bcd;
  for(k=0;k<5;k=k+1)if(bcd[k*4+:4]>=5)adjusted[k*4+:4]=bcd[k*4+:4]+4'd3;
  case(index)
   0:next_byte="$";1:next_byte="S";2,7,12,14,20,22:next_byte=",";
   3:next_byte=h(snapshot_sequence[15:12]);4:next_byte=h(snapshot_sequence[11:8]);
   5:next_byte=h(snapshot_sequence[7:4]);6:next_byte=h(snapshot_sequence[3:0]);
   8:next_byte=h(last_session[15:12]);9:next_byte=h(last_session[11:8]);
   10:next_byte=h(last_session[7:4]);11:next_byte=h(last_session[3:0]);
   13:next_byte=8'h30+{5'b0,last_state};
   15:next_byte=h(bcd[19:16]);16:next_byte=h(bcd[15:12]);17:next_byte=h(bcd[11:8]);
   18:next_byte=h(bcd[7:4]);19:next_byte=h(bcd[3:0]);
   21:next_byte=8'h30+{7'b0,snapshot_gate};23:next_byte=h(last_reason);
   24:next_byte="*";25:next_byte=h(checksum[7:4]);26:next_byte=h(checksum[3:0]);
   default:next_byte=8'd10;
  endcase
 end
 always @(posedge clk)begin
  if(rst)begin
   phase<=IDLE;index<=0;convert_count<=0;bits_left<=0;bcd<=0;sent_once<=0;
   sequence_no<=0;snapshot_sequence<=0;snapshot_gate<=0;last_session<=0;
   last_state<=0;last_reason<=0;count<=0;checksum<=0;
   for(j=0;j<28;j=j+1)frame[j]<=0;
  end else begin
   if(count<PERIOD)count<=count+1'b1;
   case(phase)
    IDLE:if(!sent_once || count>=PERIOD-1 || state!=last_state || session_id!=last_session || reason!=last_reason)begin
     bits_left<=remaining_seconds;bcd<=0;convert_count<=0;phase<=CONVERT;
     snapshot_sequence<=sequence_no;sequence_no<=sequence_no+1'b1;
     last_state<=state;last_session<=session_id;last_reason<=reason;snapshot_gate<=load_en;
     sent_once<=1;count<=0;
    end
    CONVERT:begin
     bcd<={adjusted[18:0],bits_left[31]};bits_left<=bits_left<<1;
     if(convert_count==31)begin phase<=BUILD;index<=0;checksum<=0;end
     else convert_count<=convert_count+1'b1;
    end
    BUILD:begin
     frame[index]<=next_byte;
     if(index>=1 && index<=23)checksum<=checksum^next_byte;
     if(index==27)begin phase<=SEND;index<=0;end
     else index<=index+1'b1;
    end
    SEND:if(byte_ready)begin
     if(index==27)begin phase<=IDLE;index<=0;end
     else index<=index+1'b1;
    end
   endcase
  end
 end
endmodule
