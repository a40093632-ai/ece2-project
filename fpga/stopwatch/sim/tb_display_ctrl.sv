`timescale 1ns/1ps
// display_ctrl 단독 테스트벤치 (버튼은 1클록 펄스로 직접 입력)
module tb_display_ctrl;
    reg clk = 1'b0;
    always #10 clk = ~clk;

    reg rst = 1'b1;
    reg tick_10ms = 1'b0;
    reg mode_p = 1'b0, set_p = 1'b0, start_p = 1'b0, clear_p = 1'b0;

    reg        time_valid = 1'b0;
    reg [31:0] date_bcd = 32'h2026_1116;
    reg [23:0] time_bcd = 24'h18_30_45;
    reg [7:0]  dow_bcd  = 8'h01;
    reg [23:0] sw_bcd   = 24'h01_23_45;
    reg        sw_running = 1'b0;
    reg [2:0] rsv_state = 0;
    reg [31:0] rsv_remain_s = 14'd5;
    reg        rsv_wait = 1'b0, rsv_run = 1'b0, rsv_fault = 1'b0;
    reg        meas_rx = 1'b0, meas_valid = 1'b0, e_overflow = 1'b0;
    reg [31:0] v_bcd = 32'h0000_5000;
    reg [31:0] i_bcd = 32'h0001_0080;
    reg [31:0] p_bcd = 32'h0000_4775;
    reg [31:0] e_bcd = 32'h0000_0694;

    wire sw_sp, sw_clr, r_start, r_cancel, f_ack, r_cancel_all;
    wire [1:0]  screen;
    wire [31:0] digits;
    wire [7:0]  dp;
    wire [6:0]  led;

    display_ctrl #(.CANCEL_ALL_SCREENS(0)) dut (
        .clk(clk), .rst(rst), .tick_10ms(tick_10ms),
        .mode_pulse(mode_p), .set_pulse(set_p), .start_pulse(start_p), .clear_pulse(clear_p),
        .time_valid(time_valid), .date_bcd(date_bcd), .time_bcd(time_bcd), .dow_bcd(dow_bcd),
        .sw_bcd(sw_bcd), .sw_running(sw_running),
        .rsv_state(rsv_state),.rsv_remain_s(rsv_remain_s), .rsv_wait(rsv_wait), .rsv_run(rsv_run), .rsv_fault(rsv_fault),
        .meas_rx(meas_rx), .meas_valid(meas_valid), .e_overflow(e_overflow),
        .meas_v_bcd(v_bcd), .meas_i_bcd(i_bcd), .meas_p_bcd(p_bcd), .meas_e_bcd(e_bcd),
        .sw_start_pause(sw_sp), .sw_clear(sw_clr), .rsv_start(r_start),
        .rsv_cancel(r_cancel), .fault_ack(f_ack),
        .screen(screen), .digits(digits), .dp(dp), .led(led));

    // CANCEL_ALL_SCREENS=1 설정 비교용 (rsv_cancel만 확인)
    display_ctrl #(.CANCEL_ALL_SCREENS(1)) dut_all (
        .clk(clk), .rst(rst), .tick_10ms(tick_10ms),
        .mode_pulse(mode_p), .set_pulse(set_p), .start_pulse(start_p), .clear_pulse(clear_p),
        .time_valid(time_valid), .date_bcd(date_bcd), .time_bcd(time_bcd), .dow_bcd(dow_bcd),
        .sw_bcd(sw_bcd), .sw_running(sw_running),
        .rsv_state(rsv_state),.rsv_remain_s(rsv_remain_s), .rsv_wait(rsv_wait), .rsv_run(rsv_run), .rsv_fault(rsv_fault),
        .meas_rx(meas_rx), .meas_valid(meas_valid), .e_overflow(e_overflow),
        .meas_v_bcd(v_bcd), .meas_i_bcd(i_bcd), .meas_p_bcd(p_bcd), .meas_e_bcd(e_bcd),
        .sw_start_pause(), .sw_clear(), .rsv_start(),
        .rsv_cancel(r_cancel_all), .fault_ack(),
        .screen(), .digits(), .dp(), .led());

    integer errors = 0;
    reg g_sw_sp, g_sw_clr, g_r_start, g_r_cancel, g_f_ack, g_r_cancel_all;

    task check(input ok, input [8*48-1:0] name);
        begin
            if (ok) $display("PASS  %0s", name);
            else begin
                errors = errors + 1;
                $display("FAIL  %0s  screen=%0d digits=%h dp=%b led=%b (t=%0t)",
                         name, screen, digits, dp, led, $time);
            end
        end
    endtask

    // 0 MODE, 1 SET, 2 START, 3 CLEAR : 1클록 펄스, 펄스 중 분배 출력을 기록
    task pulse(input integer which);
        begin
            @(negedge clk);
            case (which)
                0: mode_p  = 1'b1;
                1: set_p   = 1'b1;
                2: start_p = 1'b1;
                default: clear_p = 1'b1;
            endcase
            #1;
            g_sw_sp = sw_sp;   g_sw_clr = sw_clr;  g_r_start = r_start;
            g_r_cancel = r_cancel; g_f_ack = f_ack; g_r_cancel_all = r_cancel_all;
            @(negedge clk);
            mode_p = 1'b0; set_p = 1'b0; start_p = 1'b0; clear_p = 1'b0;
            #1;
        end
    endtask

    task ticks(input integer n);
        begin
            repeat (n) begin
                @(negedge clk); tick_10ms = 1'b1;
                @(negedge clk); tick_10ms = 1'b0;
            end
            #1;
        end
    endtask

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_display_ctrl);

        repeat (3) @(posedge clk);
        rst = 1'b0;
        #1;

        $display("--- 1. clock screen");
        check(screen == 0 && digits == 32'hAAAA_AAAA, "time invalid -> --------");
        time_valid = 1'b1; #1;
        check(digits == 32'h2026_1116 && dp == 8'b0001_0100 && led[1:0] == 2'b01,
              "date 2026.11.16, LED1");
        pulse(1);
        check(digits == 32'h1830_4501 && dp == 8'b0101_0100 && led[1:0] == 2'b10,
              "SET -> time 18.30.45.01, LED2");
        pulse(2);
        check(!g_sw_sp && !g_r_start, "START on clock -> nothing");
        pulse(3);
        check(!g_sw_clr && !g_r_cancel, "CLEAR on clock -> nothing");
        check(g_r_cancel_all, "CANCEL_ALL=1 -> cancel on clock");

        $display("--- 2. stopwatch screen");
        pulse(0);
        sw_running = 1'b1; #1;
        check(screen == 1 && digits == 32'h0001_2345 && dp == 8'b0001_0100,
              "MODE -> 0001.23.45");
        check(led[0] == 1'b1, "LED1 = stopwatch running");
        pulse(2);
        check(g_sw_sp && !g_r_start, "START -> stopwatch only");
        pulse(3);
        check(g_sw_clr && !g_r_cancel, "CLEAR -> stopwatch only");
        check(g_r_cancel_all, "CANCEL_ALL=1 -> also cancel rsv");
        pulse(1);
        check(screen == 1 && !g_f_ack, "SET on stopwatch -> nothing");

        $display("--- 3. reservation screen");
        pulse(0);
        rsv_wait = 1'b1; rsv_state=1; repeat(70)@(negedge clk); #1;
        check(screen == 2 && digits == 32'h1000_0005 && dp == 8'd0, "MODE -> 00000005");
        check(led[4] && !led[5], "LED5 WAIT");
        rsv_remain_s = 14'd1234; rsv_wait = 1'b0; rsv_run = 1'b1; rsv_state=2; repeat(70)@(negedge clk); #1;
        check(digits == 32'h2000_1234 && led[5] && !led[4], "1234 s, LED6 RUN");
        pulse(2);
        check(g_r_start && !g_sw_sp, "START -> reservation only");
        pulse(3);
        check(g_r_cancel && !g_sw_clr, "CLEAR -> cancel only");
        pulse(1);
        check(!g_f_ack, "SET does not acknowledge fault");

        rsv_remain_s=0;rsv_state=3;repeat(70)@(negedge clk);#1;check(digits==32'h30000000,"DONE state prefix");
        rsv_state=4;#1;check(digits==32'h40000000,"ARM state prefix");
        rsv_state=5;#1;check(digits==32'h50000000,"FAULT state prefix");
        $display("--- 4. measure screen");
        pulse(0);
        check(screen == 3 && digits == 32'hAAAA_AAAA && led[3:0] == 4'b0001,
              "MODE -> not received --------, LED1");
        meas_rx = 1'b1; meas_valid = 1'b1; #1;
        check(digits == 32'h0000_5000 && dp == 8'b0000_1000, "V 00005.000 V");
        pulse(1);
        check(digits == 32'h0001_0080 && dp == 8'b0000_0100 && led[3:0] == 4'b0010,
              "I 000100.80 mA, LED2");
        pulse(1);
        check(digits == 32'h0000_4775 && dp == 8'b0000_0010 && led[3:0] == 4'b0100,
              "P 0000477.5 mW, LED3");
        pulse(1);
        check(digits == 32'h0000_0694 && dp == 8'b0000_1000 && led[3:0] == 4'b1000,
              "E 00000.694 mWh, LED4");
        e_overflow = 1'b1; #1;
        check(digits == 32'hBAAA_AAAA, "E overflow -> E-------");
        e_overflow = 1'b0;
        meas_valid = 1'b0; #1;
        check(digits == 32'h0000_0694, "invalid: blink phase on");
        ticks(50);
        check(digits == 32'hFFFF_FFFF, "invalid: blink phase off (0.5 s)");
        ticks(50);
        check(digits == 32'h0000_0694, "invalid: blink phase on again");
        pulse(3);
        check(!g_r_cancel && !g_sw_clr, "CLEAR on measure -> nothing");

        $display("--- 5. wrap and remembered selection");
        pulse(0);
        check(screen == 0 && digits == 32'h1830_4501, "MODE -> clock, time kept");
        pulse(0); pulse(0); pulse(0);
        meas_valid = 1'b1; #1;
        check(screen == 3 && digits == 32'h0000_0694, "back to measure, E kept");

        $display("--- result");
        if (errors == 0) $display("RESULT: PASS (0 errors)");
        else             $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
