
`timescale 1ns/1ps
module tb_system;
 reg clk=0,rst=1,start=0,clear=0,mode=0,set_b=0,rx=1;
 wire [7:0] led,seg_data,seg_com;wire gate_en,tx;
 integer checks=0;
 always #5 clk=~clk;
 top #(.CLK_HZ(100000),.BAUD(10000),.SCAN_HZ(1000),.DEBOUNCE_MS(1)) dut(
  .clk_50mhz(clk),.rst_p(rst),.btn_start(start),.btn_clear(clear),.btn_mode(mode),.btn_set(set_b),
  .uart_rx(rx),.uart_tx(tx),.gate_en(gate_en),.led(led),.seg_data(seg_data),.seg_com(seg_com));
 task automatic cycles(input integer n);repeat(n)@(negedge clk);endtask
 task automatic check(input bit c,input string msg);checks++;if(!c)$fatal(1,"FAIL %s",msg);endtask
 task automatic press(input integer b);
  case(b)2:start=1;3:clear=1;4:mode=1;5:set_b=1;endcase
  cycles(120);start=0;clear=0;mode=0;set_b=0;cycles(120);
 endtask
 initial begin
  cycles(5);rst=0;cycles(200);check(!gate_en && dut.page==0,"reset OFF clock page");
  press(4);press(2);cycles(2000);check(dut.wr,"watch runs");
  press(4);press(3);check(dut.wr,"reservation clear leaves watch running");
  press(4);press(3);check(dut.wr,"measurement clear leaves watch running");
  press(4);press(3);check(dut.wr,"clock clear leaves watch running");
  press(4);press(3);check(!dut.wr && {dut.mt,dut.mo,dut.ss_t,dut.ss_o,dut.ct,dut.co}==0,"watch clear local");
  press(4);press(2);check(!gate_en && dut.state==5,"no measurement prevents ON");
  rst=1;#1;check(!gate_en,"physical reset suppresses gate");
  $display("INTEGRATED SYSTEM PASS checks=%0d",checks);$finish;
 end
endmodule
