`timescale 1ns/1ps
module tb_status_tx;
    reg clk=0,rst=1,load_en=0,byte_ready=1;
    reg [2:0] state=0;
    reg [3:0] reason=0;
    reg [15:0] session_id=0;
    reg [31:0] remaining_seconds=0;
    wire byte_valid;
    wire [7:0] byte_data;
    integer checks=0,frames=0,n=0,count=0,i;
    byte captured[0:27],sum;
    reg stall=0;
    byte stalled_data;
    always #5 clk=~clk;
    project_status_tx #(.CLK_HZ(1000)) dut(.*);
    task automatic check(input bit c,input string msg);
        checks++;if(!c)$fatal(1,"FAIL %s",msg);
    endtask
    function automatic byte hex_value(input byte c);
        return c<="9"?c-"0":c-"A"+10;
    endfunction
    always @(negedge clk)begin
        count++;
        if(!rst)byte_ready=(count%4)!=0;
    end
    always @(posedge clk)if(!rst)begin
        if(stall)check(byte_valid && byte_data===stalled_data,"valid/data stable under backpressure");
        stall=byte_valid && !byte_ready;stalled_data=byte_data;
        if(byte_valid && byte_ready)begin
            captured[n]=byte_data;
            if(n==27)begin
                check(captured[0]=="$" && captured[1]=="S" && captured[27]==10,"S delimiters and LF");
                check(captured[2]=="," && captured[7]=="," && captured[12]=="," &&
                    captured[14]=="," && captured[20]=="," && captured[22]=="," && captured[24]=="*","S field widths");
                sum=0;for(i=1;i<=23;i++)sum^=captured[i];
                check(sum==((hex_value(captured[25])<<4)|hex_value(captured[26])),"S checksum");
                check(captured[13]!="2" || captured[21]=="1","RUN snapshot carries ON");
                frames++;n=0;
            end else n++;
        end
    end
    initial begin
        repeat(3)@(negedge clk);rst=0;
        wait(frames>=1);@(negedge clk);state=4;session_id=16'h12ab;
        wait(frames>=2);@(negedge clk);state=2;load_en=1;remaining_seconds=12345;
        wait(frames>=3);@(negedge clk);state=5;load_en=0;reason=4;remaining_seconds=0;
        wait(frames>=5);@(negedge clk);
        check(frames>=5,"periodic and state-change status frames transmitted");
        $display("STATUS TX PASS checks=%0d",checks);$finish;
    end
    initial begin #100000;$fatal(1,"status test timeout");end
endmodule
