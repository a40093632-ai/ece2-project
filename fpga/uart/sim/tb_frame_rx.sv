`timescale 1ns/1ps
module tb_frame_rx;
    reg clk=0,rst=1,byte_valid=0,byte_error=0;
    reg [7:0] byte_data=0;
    wire time_event,measure_event,frame_error,time_ok,measure_ok,session_ack;
    wire [15:0] time_seq,measure_seq,measure_session;
    wire [31:0] date_ymd,time_hms,bus_mv,current_ua,power_uw;
    wire [2:0] weekday;
    wire [63:0] total_uwh,session_uwh;
    integer checks=0,times=0,measures=0,errors=0,i;
    always #5 clk=~clk;
    project_frame_rx #(.CLK_HZ(1000)) dut(.*);
    always @(posedge clk)begin
        #1;
        if(time_event)times++;
        if(measure_event)measures++;
        if(frame_error)errors++;
    end
    task automatic check(input bit c,input string msg);
        checks++;if(!c)$fatal(1,"FAIL %s",msg);
    endtask
    task automatic send_byte(input [7:0] b);
        @(negedge clk);byte_data=b;byte_valid=1;
        @(negedge clk);byte_valid=0;
    endtask
    task automatic send_frame(input string payload,input bit bad_crc,input bit crlf);
        byte sum;
        string text;
        sum=0;for(integer n=0;n<payload.len();n++)sum^=payload[n];
        if(bad_crc)sum^=8'h01;
        text=$sformatf("$%s*%02X",payload,sum);
        for(integer n=0;n<text.len();n++)send_byte(text[n]);
        if(crlf)send_byte(13);
        send_byte(10);repeat(2)@(negedge clk);
    endtask
    initial begin
        repeat(3)@(negedge clk);rst=0;
        send_frame("T,0001,20261116,235959,1,1",0,0);
        check(times==1 && date_ymd==20261116 && time_hms==235959 && weekday==1 && time_ok,"valid time frame");
        send_frame("T,0002,20240229,000000,4,1",0,1);
        check(times==2 && date_ymd==20240229,"leap date and CRLF accepted");
        send_frame("T,0003,20260229,000000,7,1",0,0);
        check(times==2 && date_ymd==20240229,"invalid nonleap date rejected atomically");
        send_frame("T,0003,20261116,240000,1,1",0,0);check(times==2,"24 hours rejected");
        send_frame("T,0003,20261116,125960,1,1",0,0);check(times==2,"seconds 60 rejected");
        send_frame("T,0003,20261116,120000,2,1",0,0);check(times==2,"weekday mismatch rejected");
        send_frame("T,0003,20261116,120000,1,1",1,0);check(times==2,"bad checksum rejected");
        send_frame("T,0003,20261116,120000,1,1",0,0);check(times==3,"valid data after errors");
        send_frame("M,FFFF,0001,05000,100000,500000,000000000694,000000000123,1,1",0,0);
        check(measures==1 && measure_seq==16'hffff && measure_session==1 && bus_mv==5000 &&
            current_ua==100000 && power_uw==500000 && total_uwh==694 && session_uwh==123 &&
            measure_ok && session_ack,"fixed units and fields parsed");
        send_frame("M,0000,0001,05000,100000,500000,000001300000,000001300000,1,1",0,0);
        check(total_uwh==1300000 && session_uwh==1300000,"1300 mWh preserved as 1300000 uWh");
        send_frame("M,0001,0001,26001,100000,500000,000000000694,000000000123,1,1",0,0);
        check(measures==2 && bus_mv==5000,"INA bus range rejected");
        send_frame("M,0001,0001,05000,100000,500000,000000000694,000000000123,2,1",0,0);
        check(measures==2,"invalid validity flag rejected");
        send_frame("M,0001,0001,00000,000000,000000,000001300000,000001300000,0,0",0,0);
        check(measures==3 && !measure_ok,"validly encoded invalid sensor emits event");
        send_frame("M,0002,0001,5000,000000,000000,000001300000,000001300000,1,0",0,0);
        check(measures==3,"wrong field width rejected");
        send_byte("$");send_byte("T");send_byte(",");send_byte("0");
        repeat(105)@(negedge clk);
        send_frame("T,0004,20261116,120001,1,1",0,0);check(times==4,"truncated-frame timeout recovers");
        send_byte("$");send_byte("T");send_byte(",");
        @(negedge clk);byte_error=1;@(negedge clk);byte_error=0;
        send_frame("T,0005,20261116,120002,1,1",0,0);check(times==5,"UART framing error aborts partial frame");
        send_byte("$");send_byte("T");send_byte(",");
        send_frame("T,0006,20261116,120003,1,1",0,0);check(times==6,"new dollar resynchronizes");
        send_frame("T,0007,00000000,000000,0,0",0,0);check(times==7 && !time_ok,"unsynchronized time invalid flag");
        check(errors>=10,"malformed cases reported");
        $display("FRAME RX PASS checks=%0d",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"frame test timeout");end
endmodule
