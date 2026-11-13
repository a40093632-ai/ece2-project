`timescale 1ns/1ps
module tb_system;
    reg clk=0,rst=1,start=0,clear=0,mode=0;
    wire [7:0] seg_data,seg_com;
    wire load;
    integer checks=0;
    top #(.CLK_HZ(1000),.SCAN_HZ(250),.DEBOUNCE_MS(2),
          .DELAY_SECONDS(1),.DURATION_SECONDS(2)) dut (
        .clk_50mhz(clk),.rst_p(rst),.btn_start(start),.btn_clear(clear),
        .btn_mode(mode),.seg_data(seg_data),.seg_com(seg_com),.led_run(load));
    always #5 clk=~clk;
    task cycles(input integer n);
        repeat(n) begin @(posedge clk); #1; end
    endtask
    task check(input bit ok,input string text);
        checks++;
        if(!ok) $fatal(1,"FAIL %s",text);
    endtask
    task press(input integer button_id);
        @(negedge clk);
        case(button_id) 0:start=1; 1:clear=1; 2:mode=1; endcase
        cycles(10);
        @(negedge clk); start=0; clear=0; mode=0;
        cycles(10);
    endtask
    initial begin
        $dumpfile("wave.vcd"); $dumpvars(0,tb_system);
        cycles(5); @(negedge clk); rst=0; cycles(5);
        check(!load && !dut.mode,"reset OFF, stopwatch mode");
        press(0); cycles(100);
        check(dut.stopwatch_running && dut.cs_o+10*dut.cs_t>0,"stopwatch starts");
        check(dut.schedule_state==0 && !load,"stopwatch start does not arm reservation");
        press(0); check(!dut.stopwatch_running,"stopwatch pauses");
        press(2); check(dut.mode,"mode button selects reservation");
        press(0); check(dut.schedule_state==1 && !load,"reservation waits");
        cycles(1000); check(dut.schedule_state==2 && load,"reservation ON");
        press(2); check(!dut.mode && load,"mode switch retains running reservation");
        cycles(2000); check(dut.schedule_state==3 && !load,"OFF after duration in another screen");
        press(2); press(0); cycles(1000); check(load,"second reservation starts");
        press(1); check(!load && dut.schedule_state==0,"cancel OFF");
        check(!dut.stopwatch_running && dut.cs_o==0 && dut.cs_t==0,"clear also resets stopwatch");
        press(0); cycles(1000); check(load,"reservation restarts after cancel");
        @(negedge clk); rst=1; cycles(3);
        check(!load && !dut.mode,"global reset OFF");
        $display("SYSTEM PASS checks=%0d",checks); $finish;
    end
    initial begin #1000000; $fatal(1,"timeout"); end
endmodule
