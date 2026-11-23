`timescale 1ns/1ps
module tb_reservation_control;
    // 10 clocks/bit, accelerated CLK_HZ. Runtime defaults in RTL stay 50MHz/9600.
    localparam integer HZ=100000, BAUD=10000, DIV=10;
    reg clk=0,rst=1,uart_rx=1,start_pulse=0,clear_pulse=0,mode_pulse=0,set_pulse=0;
    wire uart_tx,gate_en,led_run,date_selected,watch_start,watch_clear,time_valid,measure_valid,measure_received;
    wire display_valid,display_energy_valid;
    wire [2:0] result_status;
    wire [1:0] page,measure_item;
    wire [2:0] reservation_state,weekday;
    wire [3:0] reservation_reason;
    wire [31:0] remaining_seconds,date_ymd,time_hms,bus_mv,current_ua,power_uw,frame_errors;
    wire [15:0] session_id;
    wire [63:0] total_uwh,session_uwh;
    integer checks=0,mseq=0,status_frames=0,last_status_state=-1,last_status_session=0;
    integer sv_seq,sv_state,sv_sid,sv_remaining,sv_gate,sv_reason,sv_crc,fields;
    byte c,sum;
    string status_line="";
    always #5 clk=~clk;
    reservation_control #(.CLK_HZ(HZ),.BAUD(BAUD),.DELAY_SECONDS(1),.DURATION_SECONDS(2)) dut(.*);
    task automatic check(input bit condition,input string message);
        checks++;if(!condition)$fatal(1,"FAIL %s state=%0d reason=%0d",message,reservation_state,reservation_reason);
    endtask
    task automatic cycles(input integer n);repeat(n)@(negedge clk);endtask
    task automatic send_byte(input byte b);
        uart_rx=0;cycles(DIV);
        for(integer k=0;k<8;k++)begin uart_rx=b[k];cycles(DIV);end
        uart_rx=1;cycles(DIV);
    endtask
    task automatic send_frame(input string payload,input bit bad_crc);
        string text,normalized;
        byte checksum;
        // %X case differs across simulators; the wire contract requires uppercase HEX.
        normalized=payload;
        for(integer k=0;k<normalized.len();k++)
            if(normalized[k]>=8'h61 && normalized[k]<=8'h7a)normalized[k]=normalized[k]-8'd32;
        checksum=0;for(integer k=0;k<normalized.len();k++)checksum^=normalized[k];
        if(bad_crc)checksum^=1;
        text=$sformatf("$%s*%02h\n",normalized,checksum);
        for(integer k=0;k<text.len();k++)
            if(text[k]>=8'h61 && text[k]<=8'h7a)text[k]=text[k]-8'd32;
        for(integer k=0;k<text.len();k++)send_byte(text[k]);
        cycles(20);
    endtask
    task automatic measurement(input bit valid_m,input bit ack_m,input integer sid_m);
        mseq++;
        send_frame($sformatf("M,%04h,%04h,05000,100000,500000,000000000694,000000000000,%01d,%01d",
            16'(mseq),16'(sid_m),valid_m,ack_m),0);
    endtask
    task automatic press(input integer button);
        @(negedge clk);
        case(button)2:start_pulse=1;3:clear_pulse=1;4:mode_pulse=1;5:set_pulse=1;endcase
        @(negedge clk);start_pulse=0;clear_pulse=0;mode_pulse=0;set_pulse=0;cycles(3);
    endtask
    // Decode actual TX serial pin independently and validate S frames.
    initial forever begin
        @(negedge uart_tx);cycles(DIV/2);
        check(uart_tx===0,"status UART start bit");
        for(integer k=0;k<8;k++)begin cycles(DIV);c[k]=uart_tx;end
        cycles(DIV);check(uart_tx===1,"status UART stop bit");
        status_line={status_line,c};
        if(c==10)begin
            fields=$sscanf(status_line,"$S,%h,%h,%d,%d,%d,%d*%h",
                sv_seq,sv_sid,sv_state,sv_remaining,sv_gate,sv_reason,sv_crc);
            check(fields==7 && status_line.len()==28,"status format and width");
            sum=0;for(integer k=1;k<=23;k++)sum^=status_line[k];
            check(sum==sv_crc,"status checksum from physical TX pin");
            check(!sv_gate || sv_state==2,"status ON only in RUN");
            status_frames++;last_status_state=sv_state;last_status_session=sv_sid;
            status_line="";
        end
    end
    task automatic arm_session;
        press(2);check(reservation_state==4 && !gate_en,"START enters ARM with gate OFF");
        wait(last_status_state==4 && last_status_session==session_id);
        measurement(1,0,session_id);measurement(1,1,session_id);
        check(reservation_state==1 && !gate_en && display_energy_valid && display_valid && bus_mv==5000 &&
              session_uwh==0,"WAIT has zero session energy and Gate OFF");
        while(reservation_state==1)begin measurement(1,1,session_id);cycles(1000);end
        check(reservation_state==2 && gate_en && led_run,"valid UART session handshake enables RUN");
    endtask
    initial begin
        $dumpfile("reservation_control.vcd");$dumpvars(0,tb_reservation_control);
        cycles(5);rst=0;cycles(5);
        check(page==0 && !gate_en,"reset CLOCK and OFF");
        send_frame("T,0001,20261116,123456,1,1",0);
        check(time_valid && date_ymd==20261116 && time_hms==123456,"time received through RX pin");
        send_frame("T,0002,20261116,235959,1,1",1);
        check(time_hms==123456 && frame_errors==1,"corrupt frame does not change clock");
        measurement(1,0,0);check(display_valid && measure_valid && bus_mv==5000 && current_ua==100000,"measurement through RX pin");
        press(4);check(page==1,"stopwatch page");press(2);press(4);check(page==2,"reservation page");
        press(2);check(display_valid && bus_mv==5000 && session_uwh==0,"ARM retains live sample");
        press(3);check(result_status==4 && session_uwh==0,"ARM cancel before acknowledgement");
        press(2);measurement(1,0,session_id);measurement(1,1,session_id);
        check(reservation_state==1,"WAIT before invalid input");
        mseq++;
        send_frame($sformatf("M,%04h,%04h,04876,000100,000003,000000000694,000000000001,1,1",
                             16'(mseq),session_id),0);
        check(display_valid && bus_mv==4876 && current_ua==100 && power_uw==3 && session_uwh==0,
              "new WAIT sample updates live fields only");
        measurement(0,1,session_id);check(reservation_state==5 && result_status==4,"WAIT fault before RUN");
        measurement(1,0,session_id);press(3);
        arm_session();
        press(4);press(4);press(4); // 2 -> 3 -> 0 -> 1 (watch page)
        check(page==1,"watch page during RUN");press(3);
        check(gate_en && reservation_state==2,"watch clear never cancels active reservation");
        // Keep measurements fresh until the two-second run finishes in another page.
        while(reservation_state==2)begin measurement(1,1,session_id);cycles(1000);end
        check(reservation_state==3 && !gate_en && !led_run,"automatic OFF in other page");
        check(!display_valid && result_status==1,"DONE waits for final sample");
        send_frame($sformatf("F,0001,%04h,04996,015100,075243,000000000815,000000000209,1,1",16'(session_id-1)),0);
        check(!display_valid,"old session final frame rejected");
        send_frame($sformatf("F,0002,%04h,04996,015100,075243,000000000815,000000000209,1,1",session_id),1);
        check(!display_valid,"corrupt final frame rejected");
        send_frame($sformatf("F,0002,%04h,04996,015100,075243,000000000815,000000000209,1,1",session_id),0);
        check(display_valid && result_status==0 && bus_mv==4996 && current_ua==15100 &&
              power_uw==75243 && session_uwh==209,"final measurements commit together");
        measurement(1,0,session_id);
        check(display_valid && bus_mv==4996 && session_uwh==209,"live measurements cannot replace final result");
        send_frame($sformatf("F,0003,%04h,05000,000000,000000,000000000815,000000000000,1,1",session_id),0);
        check(display_valid && bus_mv==4996 && session_uwh==209,"duplicate final cannot replace result");
        press(4);check(page==2,"return reservation page");measurement(1,1,session_id);
        arm_session();check(session_uwh==0 && bus_mv!=4996,"new reservation clears finished result");
        press(3);check(reservation_state==0 && !gate_en,"reservation page cancel OFF");
        send_frame($sformatf("F,0004,%04h,04996,015100,075243,000000000816,000000000001,1,0",session_id),0);
        check(display_valid && result_status==2 && session_uwh==1,"cancelled reservation keeps partial result");
        measurement(1,1,session_id);arm_session();
        measurement(0,1,session_id);check(reservation_state==5 && !gate_en && reservation_reason==3,"sensor invalid OFF");
        send_frame($sformatf("F,0005,%04h,04980,010200,123456,000000000815,000000000015,1,0",session_id),0);
        check(result_status==2 && display_valid && bus_mv==4980 && session_uwh==15,
              "RUN fault preserves qualified partial result");
        measurement(1,1,session_id);press(2);check(reservation_state==5,"recovery plus START cannot restart");
        press(3);check(reservation_state==0,"manual acknowledge");
        arm_session();
        // Time frames continue, but no measurement frames: must still time out.
        for(integer k=3;k<40 && reservation_state!=5;k++)begin
            send_frame($sformatf("T,%04h,20261116,123456,1,1",16'(k)),0);cycles(1000);
        end
        check(reservation_state==5 && reservation_reason==4 && !gate_en,"T traffic cannot refresh M watchdog");
        cycles(HZ+5);check(result_status==3 && !display_valid,"missing final result is explicit");
        measurement(1,1,session_id);press(3);arm_session();
        rst=1;cycles(3);check(!gate_en,"global reset during RUN OFF");
        rst=0;cycles(5);
        send_frame("T,7000,20261116,235959,1,1",0);
        check(time_valid,"time before MCU reboot");
        cycles(3*HZ+5);check(!time_valid,"time expires after link loss");
        send_frame("T,0001,20261117,000000,2,1",0);
        check(time_valid && date_ymd==20261117 && time_hms==0 && weekday==2,"midnight date and restarted T sequence");
        mseq=16'h7000;measurement(1,0,0);check(measure_valid,"measurement before MCU reboot");
        cycles(HZ+5);check(!measure_valid,"measurement timeout");
        mseq=0;measurement(1,0,0);check(measure_valid,"M sequence re-acquired after timeout");
        check(status_frames>5,"status frames observed");
        $display("RESERVATION CONTROL PASS checks=%0d status_frames=%0d",checks,status_frames);$finish;
    end
    initial begin #50000000;$fatal(1,"integration test timeout");end
endmodule
