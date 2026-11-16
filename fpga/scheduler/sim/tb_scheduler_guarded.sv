`timescale 1ns/1ps
module tb_scheduler_guarded;
    localparam integer HZ=1000;
    reg clk=0,rst=1,start=0,cancel=0,event_m=0,ok=1,ack=1;
    reg [15:0] seq=0,sid=0;
    reg [31:0] delay_s=5,duration_s=10;
    wire load,healthy,fresh;
    wire [2:0] state;
    wire [3:0] reason;
    wire [31:0] remaining;
    wire [15:0] session;
    integer checks=0,seq_counter=0;
    integer clock_cycle=0,wait_at=0,run_at=0,done_at=0;
    reg [2:0] previous_state=7;
    always #5 clk=~clk;
    always @(posedge clk)begin
        clock_cycle++;
        #2;
        if(state!=previous_state)begin
            if(state==1)wait_at=clock_cycle;
            if(state==2)run_at=clock_cycle;
            if(state==3)done_at=clock_cycle;
        end
        previous_state=state;
    end
    scheduler_guarded #(.CLK_HZ(HZ)) dut(
        .clk(clk),.rst(rst),.start(start),.cancel(cancel),.delay_seconds(delay_s),
        .duration_seconds(duration_s),.measure_event(event_m),.measure_ok(ok),
        .session_ack(ack),.measure_seq(seq),.measure_session(sid),.load_en(load),
        .measure_healthy(healthy),.state(state),.reason(reason),
        .remaining_seconds(remaining),.session_id(session),.fresh_measure(fresh));
    task automatic check(input bit c,input string msg);
        checks++; if(!c)$fatal(1,"FAIL %s state=%0d reason=%0d",msg,state,reason);
    endtask
    task automatic cycles(input integer n);
        repeat(n)begin @(posedge clk);#1;end
    endtask
    task automatic measurement(input bit valid_m,input bit ack_m,input [15:0] sid_m);
        @(negedge clk); seq_counter++;seq=seq_counter;ok=valid_m;ack=ack_m;sid=sid_m;event_m=1;
        cycles(1);@(negedge clk);event_m=0;
    endtask
    task automatic press_start;
        @(negedge clk);start=1;cycles(1);@(negedge clk);start=0;
    endtask
    task automatic press_cancel;
        @(negedge clk);cancel=1;cycles(1);@(negedge clk);cancel=0;
    endtask
    task automatic reset;
        @(negedge clk);rst=1;cycles(3);@(negedge clk);rst=0;cycles(2);
    endtask
    task automatic arm;
        measurement(1,0,0);press_start();check(state==4 && !load,"ARM requires handshake");
        measurement(1,1,session);check(state==4,"old ACK high cannot authorize ARM");
        measurement(1,0,session);measurement(1,1,session);
        check(state==(delay_s==0?2:1),"ACK low then high starts reservation");
    endtask
    integer i,wait_cycles,run_cycles;
    initial begin
        $dumpfile("scheduler_guarded.vcd");$dumpvars(0,tb_scheduler_guarded);
        reset();check(!load && state==0,"reset OFF");
        press_start();check(state==5 && reason==4 && !load,"no sensor cannot start");
        measurement(1,0,0);press_start();check(state==5,"fresh data cannot auto-clear fault");
        press_cancel();check(state==0,"manual acknowledge clears healthy fault");
        arm();
        wait_cycles=0;
        while(state==1)begin
            // Fresh heartbeat without changing the tested exact second counter.
            @(negedge clk);event_m=0;
            if(wait_cycles%100==0)begin seq_counter++;seq=seq_counter;sid=session;ack=1;ok=1;event_m=1;end
            start=(wait_cycles==200); // ignored while waiting
            cycles(1);wait_cycles++;
        end
        @(negedge clk);event_m=0;start=0;
        check(run_at-wait_at==5*HZ && state==2 && load,"WAIT is exactly five seconds");
        run_cycles=0;
        while(state==2)begin
            @(negedge clk);event_m=0;
            if(run_cycles%100==0)begin seq_counter++;seq=seq_counter;sid=session;ack=1;ok=1;event_m=1;end
            start=(run_cycles==200);
            cycles(1);run_cycles++;
        end
        @(negedge clk);event_m=0;start=0;
        check(done_at-run_at==10*HZ && state==3 && reason==1 && !load,"RUN exactly ten seconds; DONE retained");
        press_start();check(state==4,"DONE starts a new execution");press_cancel();check(state==0,"cancel ARM");
        arm();press_cancel();check(state==0 && !load,"cancel WAIT");
        delay_s=0;arm();check(load,"zero delay goes directly RUN after handshake");
        press_cancel();check(state==0 && !load,"cancel RUN");
        duration_s=0;measurement(1,0,session);press_start();check(state==5 && reason==6,"zero duration rejected");
        duration_s=10;measurement(1,0,session);press_cancel();
        arm();measurement(0,1,session);check(state==5 && reason==3 && !load,"invalid sensor OFF");
        measurement(1,1,session);cycles(20);check(state==5 && !load,"recovery never restarts");
        press_cancel();arm();
        // Repeated sequence does not refresh the watchdog.
        for(i=0;i<11;i++)begin
            @(negedge clk);event_m=1;cycles(1);@(negedge clk);event_m=0;cycles(99);
        end
        check(state==5 && reason==4 && !load,"duplicate measurements time out");
        measurement(1,1,session);press_cancel();arm();
        measurement(1,1,session+1);check(state==5 && reason==7 && !load,"wrong session OFF");
        measurement(1,0,session);press_cancel();measurement(1,0,session);press_start();
        for(i=0;i<11;i++)begin measurement(1,1,session+1);cycles(100);end
        check(state==5 && reason==5,"fresh wrong-session heartbeats do not complete ARM");
        reset();delay_s=0;duration_s=10;
        // Wrap 16-bit sequence FFFF -> 0000 is fresh; an old frame is not.
        seq_counter=65534;measurement(1,0,0);measurement(1,0,0);check(healthy,"sequence wrap accepted");
        @(negedge clk);seq=16'hffff;event_m=1;cycles(1);check(!fresh,"old sequence rejected");
        @(negedge clk);event_m=0;
        reset();arm();check(load,"running before reset");reset();check(!load && state==0,"reset while RUN OFF");
        $display("GUARDED PASS checks=%0d",checks);$finish;
    end
    initial begin #1000000;$fatal(1,"scheduler timeout");end
endmodule
