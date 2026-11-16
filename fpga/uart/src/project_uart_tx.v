`timescale 1ns/1ps
// 8N1, LSB first. Transfer accepted on a rising edge with valid && ready.
// Producer must keep valid/data until accepted; there is no FIFO in this module.
module project_uart_tx #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 9600
) (
    input wire clk, rst, valid,
    input wire [7:0] data,
    output wire ready, tx
);
    localparam integer DIV = (CLK_HZ + BAUD/2) / BAUD;
    localparam integer CW = (DIV < 2) ? 1 : $clog2(DIV);
    reg [9:0] shift;
    reg [3:0] remaining;
    reg [CW-1:0] count;
    assign ready = !rst && (remaining == 0);
    assign tx = (rst || remaining == 0) ? 1'b1 : shift[0];
    always @(posedge clk) begin
        if (rst) begin shift <= 10'h3ff; remaining <= 0; count <= 0; end
        else if (remaining == 0) begin
            if (valid) begin
                shift <= {1'b1,data,1'b0}; remaining <= 10; count <= DIV-1;
            end
        end else if (count != 0) count <= count-1'b1;
        else begin
            count <= DIV-1; shift <= {1'b1,shift[9:1]}; remaining <= remaining-1'b1;
        end
    end
endmodule
