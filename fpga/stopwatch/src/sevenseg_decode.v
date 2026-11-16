`timescale 1ns/1ps
// 표시 코드: 0~9 숫자, 4'hA '-', 4'hB 'E', 그 외 빈칸
// segments = {a,b,c,d,e,f,g,dp}, 1이면 켜짐
module sevenseg_decode(
    input  wire [3:0] digit,
    output reg  [7:0] segments
);
    always @* begin
        case (digit)
            4'd0: segments = 8'b1111_1100;
            4'd1: segments = 8'b0110_0000;
            4'd2: segments = 8'b1101_1010;
            4'd3: segments = 8'b1111_0010;
            4'd4: segments = 8'b0110_0110;
            4'd5: segments = 8'b1011_0110;
            4'd6: segments = 8'b1011_1110;
            4'd7: segments = 8'b1110_0000;
            4'd8: segments = 8'b1111_1110;
            4'd9: segments = 8'b1111_0110;
            4'hA: segments = 8'b0000_0010;   // '-'
            4'hB: segments = 8'b1001_1110;   // 'E'
            default: segments = 8'b0000_0000; // 빈칸
        endcase
    end
endmodule