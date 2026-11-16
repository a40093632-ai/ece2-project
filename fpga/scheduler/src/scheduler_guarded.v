`timescale 1ns/1ps
// 0 IDLE,1 WAIT,2 RUN,3 DONE preserve first-stage numbers;4 ARM,5 FAULT added.
// Fresh measurement sequence uses a 16-bit half-range ordering rule.
module scheduler_guarded #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer MEASURE_TIMEOUT_MS=1000,
    parameter integer ARM_TIMEOUT_MS=1000
)(
    input wire clk,rst,start,cancel,
    input wire [31:0] delay_seconds,duration_seconds,
    input wire measure_event,measure_ok,session_ack,
    input wire [15:0] measure_seq,measure_session,
    output wire load_en,measure_healthy,
    output reg [2:0] state,
    output reg [3:0] reason,
    output reg [31:0] remaining_seconds,
    output reg [15:0] session_id,
    output wire fresh_measure
);
    localparam [2:0] IDLE=0,WAIT=1,RUN=2,DONE=3,ARM=4,FAULT=5;
    // reasons:0 none,1 finished,2 cancelled,3 invalid sensor,4 measurement timeout,
    // 5 ARM timeout,6 invalid configuration,7 session lost.
    localparam integer MT=(CLK_HZ/1000)*MEASURE_TIMEOUT_MS;
    localparam integer AT=(CLK_HZ/1000)*ARM_TIMEOUT_MS;
    reg have_measure,good;
    reg [15:0] last_seq;
    reg [31:0] age,arm_age,seconds_count,latched_delay,latched_duration;
    reg ack_low_seen;
    wire [15:0] delta=measure_seq-last_seq;
    wire seq_new=!have_measure || (delta!=0 && !delta[15]);
    assign fresh_measure=measure_event && measure_ok && seq_new;
    wire bad_sensor=measure_event && !measure_ok;
    wire stale=(!good || age>=MT) && !fresh_measure;
    wire active=state==ARM || state==WAIT || state==RUN;
    wire wrong_session=(state==WAIT || state==RUN) && fresh_measure &&
        (measure_session!=session_id || !session_ack);
    assign measure_healthy=good && age<MT && !bad_sensor;
    assign load_en=(state==RUN) && !rst && !cancel && !bad_sensor && !stale && !wrong_session;
    always @(posedge clk) begin
        if(rst) begin
            state<=IDLE;reason<=0;remaining_seconds<=0;session_id<=0;
            have_measure<=0;good<=0;last_seq<=0;age<=MT;
            arm_age<=0;seconds_count<=0;latched_delay<=0;latched_duration<=0;ack_low_seen<=0;
        end else begin
            if(fresh_measure)begin have_measure<=1;last_seq<=measure_seq;age<=0;good<=1; end
            else if(age<MT)age<=age+1'b1;
            if(bad_sensor)good<=0;
            if(!fresh_measure && age>=MT)have_measure<=0; // New MCU sequence after timeout; FAULT stays latched.
            if(active && (bad_sensor || stale || wrong_session)) begin
                state<=FAULT;remaining_seconds<=0;seconds_count<=0;
                reason<=bad_sensor?3:wrong_session?7:4;
            end else if(cancel) begin
                // Acknowledge FAULT only while fresh valid measurements are available.
                if(state!=FAULT || ((measure_healthy || fresh_measure) && !bad_sensor)) begin
                    state<=IDLE;remaining_seconds<=0;seconds_count<=0;reason<=2;
                end
            end else case(state)
                IDLE,DONE: begin
                    seconds_count<=0;arm_age<=0;
                    if(start) begin
                        if(duration_seconds==0 || duration_seconds>99999 || delay_seconds>99999) begin
                            state<=FAULT;reason<=6;remaining_seconds<=0;
                        end else if(bad_sensor || stale) begin
                            state<=FAULT;reason<=bad_sensor?3:4;remaining_seconds<=0;
                        end else begin
                            state<=ARM;reason<=0;ack_low_seen<=0;
                            session_id<=session_id+1'b1;
                            latched_delay<=delay_seconds;latched_duration<=duration_seconds;
                            remaining_seconds<=0;
                        end
                    end
                end
                ARM: begin
                    if(fresh_measure && measure_session==session_id && !session_ack)
                        ack_low_seen<=1;
                    if(fresh_measure && measure_session==session_id && session_ack && ack_low_seen) begin
                        seconds_count<=0;
                        if(latched_delay==0)begin state<=RUN;remaining_seconds<=latched_duration; end
                        else begin state<=WAIT;remaining_seconds<=latched_delay; end
                    end else if(arm_age==AT-1)begin state<=FAULT;reason<=5;remaining_seconds<=0; end
                    else arm_age<=arm_age+1'b1;
                end
                WAIT,RUN: if(seconds_count==CLK_HZ-1)begin
                    seconds_count<=0;
                    if(remaining_seconds==1)begin
                        if(state==WAIT)begin state<=RUN;remaining_seconds<=latched_duration; end
                        else begin state<=DONE;reason<=1;remaining_seconds<=0; end
                    end else remaining_seconds<=remaining_seconds-1'b1;
                end else seconds_count<=seconds_count+1'b1;
                FAULT: ; // Recovery and START alone never restart a faulted reservation.
                default:begin state<=FAULT;reason<=6;remaining_seconds<=0; end
            endcase
        end
    end
endmodule
