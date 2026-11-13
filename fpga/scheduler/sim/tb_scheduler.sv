`timescale 1ns/1ps
module tb_scheduler;
    localparam integer HZ=10;
    reg clk=0, rst=1, start=0, cancel=0;
    reg [31:0] delay_seconds=5, duration_seconds=10;
    wire load_en, config_error;
    wire [1:0] state;
    wire [31:0] remaining_seconds;
    integer checks=0;
    scheduler #(.CLK_HZ(HZ)) dut (.*);
    always #5 clk=~clk;
    task step;
        begin @(posedge clk); #1; end
    endtask
    task verify(input condition, input [8*100-1:0] message);
        begin
            checks=checks+1;
            if (condition !== 1'b1) $fatal(1,"FAIL %0s state=%0d remaining=%0d",message,state,remaining_seconds);
        end
    endtask
    task arm;
        begin @(negedge clk); start=1; step; start=0; end
    endtask
    task abort_run;
        begin @(negedge clk); cancel=1; step; @(negedge clk); cancel=0;
            verify(state==0 && !load_en && remaining_seconds==0,"cancel returns OFF/IDLE"); end
    endtask
    integer i;
    initial begin
        $dumpfile("wave.vcd"); $dumpvars(0,tb_scheduler);
        step; @(negedge clk); rst=0;
        verify(!load_en && state==0,"reset OFF");
        arm;
        verify(state==1 && remaining_seconds==5 && !load_en,"arm 5-second wait");
        // Exact cycle count, including duplicate starts and configuration edits.
        for(i=1;i<=50;i=i+1) begin
            @(negedge clk); start=(i==10 || i==30); duration_seconds=99; delay_seconds=99;
            step;
            if(i<50) verify(state==1 && !load_en,"no early ON");
        end
        verify(state==2 && load_en && remaining_seconds==10,"ON exactly after five seconds, latched duration");
        for(i=1;i<=100;i=i+1) begin
            @(negedge clk); start=(i==20 || i==70); step;
            if(i<100) verify(state==2 && load_en,"remain ON for full ten seconds");
        end
        verify(state==3 && !load_en && remaining_seconds==0,"OFF exactly after ten seconds");
        @(negedge clk); start=0;
        repeat(25) step;
        verify(state==3 && !load_en,"no automatic restart");
        delay_seconds=5; duration_seconds=10; arm; abort_run;
        delay_seconds=0; duration_seconds=1; arm;
        verify(state==2 && load_en,"zero delay starts immediately");
        abort_run;
        duration_seconds=0; arm;
        verify(state==0 && !load_en && config_error,"zero duration rejected");
        @(negedge clk); start=1; cancel=1; step;
        verify(state==0 && !load_en,"cancel wins over start");
        @(negedge clk); start=0; cancel=0; duration_seconds=1; arm;
        repeat(HZ-1) step;
        @(negedge clk); cancel=1; step;
        verify(state==0 && !load_en,"cancel wins over expiry");
        @(negedge clk); cancel=0; duration_seconds=10; arm;
        @(negedge clk); rst=1; #1;
        verify(!load_en && state==0,"reset during RUN turns OFF");
        $display("SCHEDULER PASS checks=%0d",checks); $finish;
    end
    initial begin #100000; $fatal(1,"TIMEOUT"); end
endmodule
