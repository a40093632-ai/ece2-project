`timescale 1ns/1ps
// 8자리 7세그먼트 스캔
//   digits : {d7..d0}, d7이 가장 왼쪽
//   dp     : 자리별 DP 켜기
//   seg_data : {a,b,c,d,e,f,g,dp}, 1이면 켜짐
//   seg_com  : 0이면 선택, seg_com[0] = 가장 오른쪽 자리
module seg_scan8 (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_scan,
    input  wire [31:0] digits,
    input  wire [7:0]  dp,
    output reg  [7:0]  seg_data,
    output reg  [7:0]  seg_com
);
    reg  [2:0] sel;
    wire [3:0] nibble = digits[sel*4 +: 4];
    wire [7:0] seg_raw;

    sevenseg_decode u_dec (.digit(nibble), .segments(seg_raw));

    always @(posedge clk or posedge rst) begin
        if (rst)
            sel <= 3'd0;
        else if (tick_scan)
            sel <= sel + 1'b1;
    end

    always @* begin
        seg_com  = ~(8'b0000_0001 << sel);
        seg_data = seg_raw | {7'b0, dp[sel]};
    end
endmodule