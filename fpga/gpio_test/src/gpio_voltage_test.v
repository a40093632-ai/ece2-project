`timescale 1ns/1ps
// Voltage measurement only: disconnect MOSFET/load/UART wiring first.
// Button 2 -> latched HIGH, button 3 -> LOW, button 1 -> reset LOW.
module gpio_voltage_test #(
    parameter integer CLK_HZ=50_000_000,DEBOUNCE_MS=20
)(
    input wire clk_50mhz,rst_p,btn_high,btn_low,
    output wire test_pin,led_run
);
    localparam integer DB=(CLK_HZ/1000)*DEBOUNCE_MS;
    (* ASYNC_REG="TRUE" *)reg [1:0] rst_pipe;
    always @(posedge clk_50mhz or posedge rst_p)begin
        if(rst_p)rst_pipe<=2'b11;
        else rst_pipe<={rst_pipe[0],1'b0};
    end
    wire rst=rst_pipe[1];
    wire high_pulse,low_pulse;
    reg level;
    button_onepulse #(.STABLE_CYCLES(DB)) hi(
        .clk(clk_50mhz),.rst(rst),.btn_in(btn_high),.pulse(high_pulse));
    button_onepulse #(.STABLE_CYCLES(DB)) lo(
        .clk(clk_50mhz),.rst(rst),.btn_in(btn_low),.pulse(low_pulse));
    always @(posedge clk_50mhz)begin
        if(rst)level<=0;
        else if(low_pulse)level<=0;
        else if(high_pulse)level<=1;
    end
    assign test_pin=level && !rst_p && !rst;
    assign led_run=test_pin;
endmodule
