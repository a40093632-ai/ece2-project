`timescale 1ns/1ps
// 스톱워치: MM:SS.cc (분 00~99, 초 00~59, 1/100초 00~99)
//   start_pause : 1클록 펄스. 정지->시작, 실행->일시정지, 일시정지->재개
//   clear       : 1클록 펄스. 00:00.00으로 초기화하고 정지 (start_pause보다 우선)
//   tick_10ms   : 0.01초 enable, running일 때만 증가
module stopwatch (
    input  wire       clk,
    input  wire       rst,
    input  wire       tick_10ms,
    input  wire       start_pause,
    input  wire       clear,
    output reg        running,
    output reg  [3:0] min_t,
    output reg  [3:0] min_o,
    output reg  [3:0] sec_t,
    output reg  [3:0] sec_o,
    output reg  [3:0] cs_t,
    output reg  [3:0] cs_o
);
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            running <= 1'b0;
            min_t <= 4'd0; min_o <= 4'd0;
            sec_t <= 4'd0; sec_o <= 4'd0;
            cs_t  <= 4'd0; cs_o  <= 4'd0;
        end else if (clear) begin
            running <= 1'b0;
            min_t <= 4'd0; min_o <= 4'd0;
            sec_t <= 4'd0; sec_o <= 4'd0;
            cs_t  <= 4'd0; cs_o  <= 4'd0;
        end else begin
            if (start_pause)
                running <= ~running;

            if (running && tick_10ms) begin
                if (cs_o != 4'd9) begin
                    cs_o <= cs_o + 1'b1;
                end else begin
                    cs_o <= 4'd0;
                    if (cs_t != 4'd9) begin
                        cs_t <= cs_t + 1'b1;
                    end else begin
                        cs_t <= 4'd0;                    // 99 -> 00 : 초 증가
                        if (sec_o != 4'd9) begin
                            sec_o <= sec_o + 1'b1;
                        end else begin
                            sec_o <= 4'd0;
                            if (sec_t != 4'd5) begin
                                sec_t <= sec_t + 1'b1;
                            end else begin
                                sec_t <= 4'd0;           // 59 -> 00 : 분 증가
                                if (min_o != 4'd9) begin
                                    min_o <= min_o + 1'b1;
                                end else begin
                                    min_o <= 4'd0;
                                    if (min_t != 4'd9)
                                        min_t <= min_t + 1'b1;
                                    else
                                        min_t <= 4'd0;   // 99:59.99 -> 00:00.00
                                end
                            end
                        end
                    end
                end
            end
        end
    end
endmodule