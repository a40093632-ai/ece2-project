`timescale 1ns/1ps
// Inputs are debounced single-clock pulses, not raw board button levels.
// Page:0 clock,1 stopwatch,2 reservation,3 measurements. Global reset -> clock.
module stage2_button_router(
    input wire clk,rst,start_pulse,clear_pulse,mode_pulse,set_pulse,
    output reg [1:0] page,
    output reg date_selected,
    output reg [1:0] measure_item,
    output wire watch_start,watch_clear,reservation_start,reservation_cancel
);
    wire local_action=!mode_pulse && !set_pulse;
    assign watch_start=start_pulse && !clear_pulse && local_action && page==1;
    assign watch_clear=clear_pulse && local_action && page==1;
    assign reservation_start=start_pulse && !clear_pulse && local_action && page==2;
    assign reservation_cancel=clear_pulse && local_action && page==2;
    always @(posedge clk)begin
        if(rst)begin page<=0;date_selected<=0;measure_item<=0; end
        else if(mode_pulse)page<=page+1'b1;
        else if(set_pulse)begin
            if(page==0)date_selected<=~date_selected;
            if(page==3)measure_item<=measure_item+1'b1;
        end
    end
endmodule
