`timescale 1ns/1ps
// 8N1, LSB first. data_valid/framing_error are one-clock pulses.
// rst is active high, synchronous to clk. Reset with the external line idle high.
module project_uart_rx #(
    parameter integer CLK_HZ = 50_000_000,
    parameter integer BAUD = 9600
) (
    input wire clk, rst, rx,
    output reg [7:0] data,
    output reg data_valid,
    output reg framing_error
);
    localparam integer DIV = (CLK_HZ + BAUD/2) / BAUD;
    localparam integer CW = (DIV < 2) ? 1 : $clog2(DIV);
    localparam [2:0] IDLE=0, START=1, DATA=2, STOP=3, WAIT_HIGH=4;
    (* ASYNC_REG="TRUE" *) reg [1:0] rx_sync;
    reg [2:0] state, bit_index;
    reg [CW-1:0] count;
    reg [7:0] shift;
    // Supported configuration: DIV >= 8. 50 MHz / 9600 -> 5208 clocks/bit.
    always @(posedge clk) begin
        if (rst) begin
            rx_sync <= 2'b11;
            state <= IDLE; bit_index <= 0; count <= 0; shift <= 0;
            data <= 0; data_valid <= 0; framing_error <= 0;
        end else begin
            rx_sync <= {rx_sync[0],rx};
            data_valid <= 0;
            framing_error <= 0;
            case (state)
                IDLE: if (!rx_sync[1]) begin
                    count <= DIV/2-1; state <= START;
                end
                START: if (count != 0) count <= count-1'b1;
                    else if (rx_sync[1]) state <= IDLE; // reject short low glitch
                    else begin count <= DIV-1; bit_index <= 0; state <= DATA; end
                DATA: if (count != 0) count <= count-1'b1;
                    else begin
                        shift[bit_index] <= rx_sync[1]; count <= DIV-1;
                        if (bit_index == 7) state <= STOP;
                        else bit_index <= bit_index+1'b1;
                    end
                STOP: if (count != 0) count <= count-1'b1;
                    else if (rx_sync[1]) begin
                        data <= shift; data_valid <= 1; state <= IDLE;
                    end else begin
                        framing_error <= 1; state <= WAIT_HIGH;
                    end
                WAIT_HIGH: if (rx_sync[1]) state <= IDLE;
                default: begin state <= IDLE; count <= 0; end
            endcase
        end
    end
endmodule
