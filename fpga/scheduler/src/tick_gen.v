`timescale 1ns/1ps
// 50MHz 기준 enable 펄스 생성
//   tick_10ms : 0.01초마다 1클록 폭 펄스 (CLK_HZ/100 = 500,000클록)
//   tick_scan : 7세그먼트 자리 스캔용 펄스 (CLK_HZ/SCAN_HZ 클록)
module tick_gen #(
    parameter integer CLK_HZ  = 50_000_000,
    parameter integer SCAN_HZ = 4_000
) (
    input  wire clk,
    input  wire rst,
    output reg  tick_10ms,
    output reg  tick_scan
);
    localparam integer CC_CYCLES   = (CLK_HZ / 100 < 1) ? 1 : CLK_HZ / 100;
    localparam integer SCAN_CYCLES = (CLK_HZ / SCAN_HZ < 1) ? 1 : CLK_HZ / SCAN_HZ;
    localparam integer CC_W   = (CC_CYCLES   < 2) ? 1 : $clog2(CC_CYCLES);
    localparam integer SCAN_W = (SCAN_CYCLES < 2) ? 1 : $clog2(SCAN_CYCLES);

    reg [CC_W-1:0]   cc_cnt;
    reg [SCAN_W-1:0] scan_cnt;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cc_cnt    <= 0;
            tick_10ms <= 1'b0;
        end else if (cc_cnt == CC_CYCLES - 1) begin
            cc_cnt    <= 0;
            tick_10ms <= 1'b1;
        end else begin
            cc_cnt    <= cc_cnt + 1'b1;
            tick_10ms <= 1'b0;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            scan_cnt  <= 0;
            tick_scan <= 1'b0;
        end else if (scan_cnt == SCAN_CYCLES - 1) begin
            scan_cnt  <= 0;
            tick_scan <= 1'b1;
        end else begin
            scan_cnt  <= scan_cnt + 1'b1;
            tick_scan <= 1'b0;
        end
    end
endmodule