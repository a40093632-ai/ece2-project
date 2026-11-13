`timescale 1ns/1ps
// start/cancel are synchronous one-clock pulses. Configuration is latched on start.
// States: 0 IDLE, 1 WAIT, 2 RUN, 3 DONE. Cancel has priority over start/expiry.
module scheduler #(
    parameter integer CLK_HZ = 50_000_000
) (
    input wire clk,
    input wire rst,
    input wire start,
    input wire cancel,
    input wire [31:0] delay_seconds,
    input wire [31:0] duration_seconds,
    output wire load_en,
    output reg [1:0] state,
    output reg [31:0] remaining_seconds,
    output reg config_error
);
    localparam [1:0] IDLE=0, WAIT=1, RUN=2, DONE=3;
    localparam integer COUNTER_WIDTH = (CLK_HZ < 2) ? 1 : $clog2(CLK_HZ);
    reg [COUNTER_WIDTH-1:0] second_count;
    reg [31:0] run_seconds;
    assign load_en = (state == RUN) && !rst && !cancel;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            remaining_seconds <= 0;
            run_seconds <= 0;
            second_count <= 0;
            config_error <= 0;
        end else if (cancel) begin
            state <= IDLE;
            remaining_seconds <= 0;
            run_seconds <= 0;
            second_count <= 0;
            config_error <= 0;
        end else begin
            config_error <= 0;
            case (state)
                IDLE, DONE: begin
                    second_count <= 0;
                    if (start) begin
                        if (duration_seconds == 0) begin
                            config_error <= 1;
                        end else begin
                            run_seconds <= duration_seconds;
                            if (delay_seconds == 0) begin
                                state <= RUN;
                                remaining_seconds <= duration_seconds;
                            end else begin
                                state <= WAIT;
                                remaining_seconds <= delay_seconds;
                            end
                        end
                    end
                end
                WAIT, RUN: begin
                    if (second_count == CLK_HZ-1) begin
                        second_count <= 0;
                        if (remaining_seconds == 1) begin
                            if (state == WAIT) begin
                                state <= RUN;
                                remaining_seconds <= run_seconds;
                            end else begin
                                state <= DONE;
                                remaining_seconds <= 0;
                            end
                        end else begin
                            remaining_seconds <= remaining_seconds - 1;
                        end
                    end else begin
                        second_count <= second_count + 1'b1;
                    end
                end
                default: begin
                    state <= IDLE;
                    remaining_seconds <= 0;
                    second_count <= 0;
                    run_seconds <= 0;
                end
            endcase
        end
    end
endmodule
