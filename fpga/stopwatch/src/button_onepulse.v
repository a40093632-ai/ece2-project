`timescale 1ns/1ps
// 버튼 입력: 2단 동기화 -> 디바운스 -> 눌린 순간 1클록 펄스
// 보드 버튼은 누르면 1 (active-high)
//   50MHz에서 STABLE_CYCLES 1,000,000 = 20ms
module button_onepulse #(
    parameter integer STABLE_CYCLES = 1_000_000
) (
    input  wire clk,
    input  wire rst,
    input  wire btn_in,
    output reg  pulse
);
    localparam integer W = (STABLE_CYCLES < 2) ? 1 : $clog2(STABLE_CYCLES);

    (* ASYNC_REG = "TRUE" *) reg btn_meta, btn_sync;
    reg [W-1:0] count;
    reg         accepted;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            btn_meta <= 1'b0;
            btn_sync <= 1'b0;
        end else begin
            btn_meta <= btn_in;
            btn_sync <= btn_meta;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count    <= 0;
            accepted <= 1'b0;
            pulse    <= 1'b0;
        end else begin
            pulse <= 1'b0;
            if (btn_sync == accepted) begin
                count <= 0;
            end else if (count == STABLE_CYCLES - 1) begin
                count    <= 0;
                accepted <= btn_sync;
                pulse    <= btn_sync;   // 누를 때(0->1)만 펄스
            end else begin
                count <= count + 1'b1;
            end
        end
    end
endmodule