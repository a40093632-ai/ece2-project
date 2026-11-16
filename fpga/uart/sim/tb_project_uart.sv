`timescale 1ns/1ps
module tb_project_uart;
    // Accelerated simulation: 100 clocks/bit. DUT defaults remain 50 MHz/9600.
    localparam integer DIV=100;
    reg clk=0, rst=1, rx=1, valid=0;
    reg [7:0] tx_data=0;
    wire [7:0] rx_data;
    wire rx_valid, rx_error, tx, ready;
    integer checks=0, received=0, errors=0, i, before_rx, before_err;
    reg [7:0] expected[0:1023];
    reg was_valid=0, was_error=0;
    always #10 clk=~clk;
    project_uart_rx #(.CLK_HZ(960000),.BAUD(9600)) receiver (
        .clk(clk),.rst(rst),.rx(rx),.data(rx_data),
        .data_valid(rx_valid),.framing_error(rx_error));
    project_uart_tx #(.CLK_HZ(960000),.BAUD(9600)) transmitter (
        .clk(clk),.rst(rst),.valid(valid),.data(tx_data),.ready(ready),.tx(tx));
    task automatic check(input bit ok, input string message);
        begin checks=checks+1; if (!ok) $fatal(1,"FAIL: %s",message); end
    endtask
    always @(posedge clk) begin
        #1;
        if (rst) begin was_valid=0; was_error=0; end
        else begin
            if (rx_valid) begin
                check(!was_valid,"RX valid must pulse for one clock");
                check(rx_data === expected[received],"RX byte mismatch or unexpected byte");
                received=received+1;
            end
            if (rx_error) begin
                check(!was_error,"RX framing_error must pulse for one clock");
                errors=errors+1;
            end
            was_valid=rx_valid; was_error=rx_error;
        end
    end
    task automatic cycles(input integer n);
        repeat(n) @(negedge clk);
    endtask
    task automatic send_rx(input [7:0] value, input integer bit_cycles, input bit stop_ok);
        integer b;
        begin
            rx=0; cycles(bit_cycles);
            for(b=0;b<8;b=b+1) begin rx=value[b]; cycles(bit_cycles); end
            rx=stop_ok; cycles(bit_cycles);
        end
    endtask
    // Inspect TX pin independently at bit centers, rather than using only loopback.
    task automatic check_tx(input [7:0] value);
        integer b;
        begin
            @(negedge tx); cycles(DIV/2);
            check(tx===0,"TX start bit");
            for(b=0;b<8;b=b+1) begin cycles(DIV); check(tx===value[b],"TX data bit"); end
            cycles(DIV); check(tx===1,"TX stop bit");
            check(ready===0,"TX busy through stop-bit center");
            cycles(DIV/2-2);
        end
    endtask
    task automatic send_tx(input [7:0] value);
        begin
            while(!ready) @(negedge clk);
            tx_data=value; valid=1; cycles(1); valid=0;
            // Change input after acceptance: transmitted byte must remain latched.
            tx_data=~value;
        end
    endtask
    initial begin
        $dumpfile("uart.vcd"); $dumpvars(0,tb_project_uart);
        for(i=0;i<1024;i=i+1) expected[i]=8'hxx;
        cycles(5); rst=0; cycles(5);
        check(tx===1 && ready===1,"TX idle high and ready");
        cycles(2*DIV); check(received==0 && errors==0,"RX idle has no events");
        // Every possible byte, no extra idle gap between stop and next start.
        for(i=0;i<256;i=i+1) expected[i]=i;
        for(i=0;i<256;i=i+1) send_rx(i,DIV,1);
        rx=1; cycles(DIV); check(received==256,"all 256 RX bytes received");
        expected[256]=8'ha5; send_rx(8'ha5,98,1); rx=1; cycles(DIV);
        expected[257]=8'h55; send_rx(8'h55,102,1); rx=1; cycles(DIV);
        check(received==258,"RX at plus/minus 2 percent bit period");
        before_rx=received; before_err=errors;
        rx=0; cycles(10); rx=1; cycles(2*DIV);
        check(received==before_rx && errors==before_err,"short start glitch rejected");
        send_rx(8'h33,DIV,0); rx=1; cycles(2*DIV);
        check(received==before_rx && errors==before_err+1,"bad stop rejected");
        before_err=errors; rx=0; cycles(30*DIV);
        check(received==before_rx && errors==before_err+1,"continuous low produces one error");
        rx=1; cycles(2*DIV); expected[258]=8'hc3; send_rx(8'hc3,DIV,1);
        rx=1; cycles(DIV); check(received==259,"RX recovers after break");
        // Reset partway through a received frame: no partially received byte.
        rx=0; cycles(3*DIV); rst=1; rx=1; cycles(5); rst=0; cycles(12*DIV);
        check(received==259,"reset discards incomplete RX frame");
        expected[259]=8'h7e; send_rx(8'h7e,DIV,1); rx=1; cycles(DIV);
        check(received==260,"RX works after reset");
        for(i=0;i<256;i=i+1) begin
            fork
                send_tx(i);
                check_tx(i);
            join
        end
        // Held valid while busy waits for ready, then sends the next byte.
        fork
            begin
                send_tx(8'h12); tx_data=8'h34; valid=1;
                while(!ready) @(negedge clk);
                cycles(1); valid=0;
            end
            begin check_tx(8'h12); check_tx(8'h34); end
        join
        fork
            send_tx(8'hff);
            begin
                @(negedge tx); cycles(3*DIV); rst=1; cycles(3);
                check(tx===1 && ready===0,"reset aborts TX and masks ready");
                rst=0; cycles(3); check(tx===1 && ready===1,"TX returns to idle");
            end
        join
        fork send_tx(8'h5a); check_tx(8'h5a); join
        check(errors==2,"only expected framing errors occurred");
        $display("UART PASS checks=%0d RX_bytes=%0d framing_errors=%0d",checks,received,errors);
        $finish;
    end
    initial begin #20000000; $fatal(1,"UART test timeout"); end
endmodule
