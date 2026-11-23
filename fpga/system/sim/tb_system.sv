
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
 task automatic send_byte(input byte data);
  rx=0;cycles(10);
  for(integer bit_index=0;bit_index<8;bit_index++)begin
   rx=data[bit_index];cycles(10);
  end
  rx=1;cycles(10);
 endtask
 task automatic send_measurement(input string payload);
  string frame;
  byte checksum;
  checksum=0;
  for(integer i=0;i<payload.len();i++)checksum^=payload[i];
  frame=$sformatf("$%s*%02h\n",payload,checksum);
  for(integer i=0;i<frame.len();i++)begin
   byte data;
   data=frame[i];
   if(data>="a" && data<="f")data=data-8'd32;
   send_byte(data);
  end
  cycles(75); // Allow a complete binary-to-BCD snapshot after reception.
 endtask
 initial begin
  cycles(5);rst=0;cycles(200);check(!gate_en && dut.page==0,"reset OFF clock page");
  press(4);press(2);cycles(2000);check(dut.wr,"watch runs");
  press(4);press(3);check(dut.wr,"reservation clear leaves watch running");
  press(4);press(3);check(dut.wr,"measurement clear leaves watch running");
  press(4);press(3);check(dut.wr,"clock clear leaves watch running");
  press(4);press(3);check(!dut.wr && {dut.mt,dut.mo,dut.ss_t,dut.ss_o,dut.ct,dut.co}==0,"watch clear local");
  press(4);press(2);check(!gate_en && dut.state==5,"no measurement prevents ON");
  press(4);
  send_measurement("M,0001,0000,00000,000000,000000,000000000000,000000000000,0,0");
  check(dut.lcd_line2=="NO RUN DATA     " && dut.digits==32'haaaa_aaaa,
        "invalid first frame cannot display a fabricated 0 V");
  send_measurement("M,0002,0000,04996,015100,075243,000000000000,000000000000,1,0");
  check(dut.lcd_line2=="00004.996 V     " && dut.digits==32'h0000_4996 &&
        dut.state==5 && led[6] && !gate_en,"recovered live value is visible while the fault stays latched");
  send_measurement("M,0003,0000,00000,000000,000000,000000000000,000000000000,0,0");
  check(!dut.mready && dut.show_last_live && dut.digits==32'h0000_4996,
        "invalid measurement does not overwrite the last valid seven-segment value");
  press(5);press(5);press(5);cycles(75);
  check(dut.lcd_line2=="00000.000 mWh   " && dut.digits==0 && dut.mready,
        "pre-run fault shows zero session energy even without a valid live sample");
  send_measurement("M,0004,0000,04876,015100,075243,000000000000,000000000000,1,0");
  press(4);press(4);press(4);
  check(dut.lcd_line1=="RSV 5 FAULT OFF ","reservation page still identifies the fault");
  press(3);press(4);press(5);cycles(75);
  check(dut.state==0 && !led[6] && !gate_en && dut.lcd_line2=="00004.876 V     " &&
        dut.digits==32'h0000_4876,"manual acknowledge returns to IDLE with live measurements");
  press(4);press(4);press(4);press(2);
  check(dut.state==4 && !gate_en,"start enters ARM after sensor recovery");
  press(3);press(4);
  check(dut.state==0 && !gate_en && dut.lcd_line2=="00004.876 V     " &&
        dut.digits==32'h0000_4876,"cancel before RUN returns to a live measurement view");
  rst=1;#1;check(!gate_en,"physical reset suppresses gate");
  $display("INTEGRATED SYSTEM PASS checks=%0d",checks);$finish;
 end
endmodule
