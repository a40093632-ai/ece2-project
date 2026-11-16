`timescale 1ns/1ps
module tb_button_router;
    reg clk=0,rst=1,start_pulse=0,clear_pulse=0,mode_pulse=0,set_pulse=0;
    wire [1:0] page,measure_item;
    wire date_selected,watch_start,watch_clear,reservation_start,reservation_cancel;
    integer checks=0;
    always #5 clk=~clk;
    stage2_button_router dut(.*);
    task automatic check(input bit c,input string msg);
        checks++;if(!c)$fatal(1,"FAIL %s",msg);
    endtask
    task automatic mode;
        @(negedge clk);mode_pulse=1;@(negedge clk);mode_pulse=0;#1;
    endtask
    task automatic set_button;
        @(negedge clk);set_pulse=1;@(negedge clk);set_pulse=0;#1;
    endtask
    task automatic clear_button;
        @(negedge clk);clear_pulse=1;#1;
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=0;#1;
        check(page==0,"reset page CLOCK");set_button();check(date_selected,"SET clock/date");
        clear_button();check(!watch_clear && !reservation_cancel,"CLOCK clear affects no execution");
        clear_pulse=0;mode();check(page==1,"stopwatch page");
        clear_button();check(watch_clear && !reservation_cancel,"watch clear never cancels reservation");
        clear_pulse=0;mode();check(page==2,"reservation page");
        clear_button();check(!watch_clear && reservation_cancel,"reservation cancel never clears watch");
        clear_pulse=0;mode();check(page==3,"measurement page");
        clear_button();check(!watch_clear && !reservation_cancel,"measurement clear affects no execution");
        clear_pulse=0;set_button();check(measure_item==1,"SET measurement item");
        repeat(3)set_button();check(measure_item==0,"SET cycles four items");
        mode();check(page==0,"four pages wrap");
        mode();@(negedge clk);start_pulse=1;#1;check(watch_start && !reservation_start,"watch START routed");
        clear_pulse=1;#1;check(!watch_start && watch_clear,"clear priority over start");
        mode_pulse=1;#1;check(!watch_start && !watch_clear,"simultaneous MODE suppresses local action");
        @(negedge clk);start_pulse=0;clear_pulse=0;mode_pulse=0;rst=1;
        @(negedge clk);check(page==0,"global reset restores page");
        $display("BUTTON ROUTER PASS checks=%0d",checks);$finish;
    end
endmodule
