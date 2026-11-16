`timescale 1ns/1ps
module tb_gpio_voltage_test;
    reg clk_50mhz=0,rst_p=1,btn_high=0,btn_low=0;
    wire test_pin,led_run;
    integer checks=0;
    always #5 clk_50mhz=~clk_50mhz;
    gpio_voltage_test #(.CLK_HZ(1000),.DEBOUNCE_MS(2)) dut(.*);
    task automatic check(input bit c,input string msg);
        checks++;if(!c)$fatal(1,"FAIL %s",msg);
    endtask
    task automatic cycles(input integer n);repeat(n)@(negedge clk_50mhz);endtask
    initial begin
        cycles(5);rst_p=0;cycles(10);check(!test_pin && !led_run,"reset LOW");
        btn_high=1;cycles(12);btn_high=0;cycles(12);check(test_pin && led_run,"button2 latched HIGH");
        cycles(20);check(test_pin,"HIGH held after release");
        btn_low=1;cycles(12);btn_low=0;cycles(12);check(!test_pin,"button3 LOW");
        btn_high=1;cycles(12);btn_high=0;cycles(12);rst_p=1;#1;
        check(!test_pin,"physical reset immediate LOW");
        cycles(5);rst_p=0;cycles(12);check(!test_pin,"reset release stays LOW");
        $display("GPIO VOLTAGE TEST PASS checks=%0d",checks);$finish;
    end
endmodule
