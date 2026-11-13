`timescale 1ns/1ps
// 스톱워치 테스트벤치 (자기검사)
// 시뮬레이션을 빠르게 하려고 CLK_HZ=1000으로 축소: 0.01초=10클록, 디바운스=20클록
module tb_stopwatch;
    localparam integer CLK_HZ  = 1000;
    localparam integer SCAN_HZ = 250;
    localparam integer CC_CYC  = CLK_HZ / 100;
    localparam integer DB_CYC  = CLK_HZ / 1000 * 20;

    reg  clk = 1'b0;
    reg  rst_p = 1'b1;
    reg  btn_start = 1'b0;
    reg  btn_clear = 1'b0;
    wire [7:0] seg_data, seg_com;
    wire led_run;

    stopwatch_top #(.CLK_HZ(CLK_HZ), .SCAN_HZ(SCAN_HZ), .DEBOUNCE_MS(20)) dut (
        .clk_50mhz(clk), .rst_p(rst_p),
        .btn_start(btn_start), .btn_clear(btn_clear),
        .seg_data(seg_data), .seg_com(seg_com), .led_run(led_run));

    always #10 clk = ~clk;

    wire [3:0] min_t = dut.min_t;
    wire [3:0] min_o = dut.min_o;
    wire [3:0] sec_t = dut.sec_t;
    wire [3:0] sec_o = dut.sec_o;
    wire [3:0] cs_t  = dut.cs_t;
    wire [3:0] cs_o  = dut.cs_o;
    wire [31:0] total_cs = (min_t * 10 + min_o) * 6000
                         + (sec_t * 10 + sec_o) * 100
                         + cs_t * 10 + cs_o;
    wire [31:0] digits = {4'd0, 4'd0, min_t, min_o, sec_t, sec_o, cs_t, cs_o};
    localparam [7:0] DP_MASK = 8'b0001_0100;

    integer errors = 0;
    integer v1, v2, v3;
    reg monitor_on = 1'b0;
    reg seen_sec_carry = 1'b0;
    reg seen_min_carry = 1'b0;
    reg [31:0] prev_cs = 0;

    function [7:0] seg7(input [3:0] d);
        case (d)
            4'd0: seg7 = 8'b1111_1100;
            4'd1: seg7 = 8'b0110_0000;
            4'd2: seg7 = 8'b1101_1010;
            4'd3: seg7 = 8'b1111_0010;
            4'd4: seg7 = 8'b0110_0110;
            4'd5: seg7 = 8'b1011_0110;
            4'd6: seg7 = 8'b1011_1110;
            4'd7: seg7 = 8'b1110_0000;
            4'd8: seg7 = 8'b1111_1110;
            4'd9: seg7 = 8'b1111_0110;
            default: seg7 = 8'b0000_0000;
        endcase
    endfunction

    task check(input ok, input [8*48-1:0] name);
        begin
            if (ok) begin
                $display("PASS  %0s", name);
            end else begin
                errors = errors + 1;
                $display("FAIL  %0s (t=%0t)", name, $time);
            end
        end
    endtask

    // 0: START/PAUSE, 1: RESET
    task press(input integer which);
        begin
            if (which == 0) btn_start = 1'b1; else btn_clear = 1'b1;
            repeat (DB_CYC * 2) @(posedge clk);
            btn_start = 1'b0;
            btn_clear = 1'b0;
            repeat (DB_CYC * 2) @(posedge clk);
        end
    endtask

    task wait_cs(input integer n);
        begin
            repeat (n * CC_CYC) @(posedge clk);
        end
    endtask

    task show(input [8*16-1:0] tag);
        begin
            $display("      %0s : %0d%0d:%0d%0d.%0d%0d  running=%0d  (total %0d cs)",
                     tag, min_t, min_o, sec_t, sec_o, cs_t, cs_o, led_run, total_cs);
        end
    endtask

    // 감시 1: 값이 바뀌면 0(초기화)이거나 정확히 +0.01초
    always @(negedge clk) begin
        if (monitor_on && total_cs != prev_cs) begin
            if (total_cs != 0 && total_cs != prev_cs + 1) begin
                errors = errors + 1;
                $display("FAIL  step %0d -> %0d cs (t=%0t)", prev_cs, total_cs, $time);
            end
            if (prev_cs % 100 == 99 && total_cs == prev_cs + 1) seen_sec_carry = 1'b1;
            if (prev_cs == 5999 && total_cs == 6000)            seen_min_carry = 1'b1;
        end
        if (monitor_on && (sec_t > 5 || sec_o > 9 || cs_t > 9 || cs_o > 9 ||
                           min_t > 9 || min_o > 9)) begin
            errors = errors + 1;
            $display("FAIL  invalid BCD digit (t=%0t)", $time);
        end
        prev_cs <= total_cs;
    end

    // 감시 2: 선택된 자리 하나, 세그먼트 패턴과 DP 일치
    integer i, k, nlow;
    always @(negedge clk) begin
        if (monitor_on) begin
            nlow = 0;
            k = 0;
            for (i = 0; i < 8; i = i + 1)
                if (seg_com[i] == 1'b0) begin nlow = nlow + 1; k = i; end
            if (nlow != 1) begin
                errors = errors + 1;
                $display("FAIL  seg_com=%b (t=%0t)", seg_com, $time);
            end else if (seg_data !== (seg7(digits[k*4 +: 4]) | {7'b0, DP_MASK[k]})) begin
                errors = errors + 1;
                $display("FAIL  digit %0d seg_data=%b (t=%0t)", k, seg_data, $time);
            end
        end
    end

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(1, tb_stopwatch);
        $dumpvars(1, tb_stopwatch.dut);

        repeat (10) @(posedge clk);
        rst_p = 1'b0;
        repeat (5) @(posedge clk);
        monitor_on = 1'b1;

        $display("--- 1. reset");
        show("after reset");
        check(total_cs == 0 && led_run == 0, "reset -> 00:00.00, stopped");

        $display("--- 2. start, pause, hold");
        press(0);
        check(led_run == 1, "START -> running");
        wait_cs(150);
        press(0);
        v1 = total_cs;
        show("paused");
        check(led_run == 0, "PAUSE -> stopped");
        check(v1 >= 156 && v1 <= 160, "elapsed about 1.58 s");
        wait_cs(100);
        show("after 1 s pause");
        check(total_cs == v1, "value held while paused");

        $display("--- 3. resume from held value");
        press(0);
        check(led_run == 1, "RESUME -> running");
        wait_cs(50);
        press(0);
        v2 = total_cs;
        show("paused again");
        check(v2 - v1 >= 56 && v2 - v1 <= 60, "resumed from held value (+0.58 s)");

        $display("--- 4. reset button");
        press(1);
        show("after RESET");
        check(total_cs == 0 && led_run == 0, "RESET while paused -> 0, stopped");
        press(0);
        wait_cs(30);
        press(1);
        show("RESET while run");
        check(total_cs == 0 && led_run == 0, "RESET while running -> 0, stopped");
        wait_cs(20);
        check(total_cs == 0, "stays 0 after RESET");

        $display("--- 5. carry to seconds and minutes");
        press(0);
        wait_cs(6100);
        press(0);
        v3 = total_cs;
        show("after ~61 s");
        check(min_o == 1 && min_t == 0, "minute = 01");
        check(seen_sec_carry, "cc 99 -> 00 increments seconds");
        check(seen_min_carry, "00:59.99 -> 01:00.00");

        $display("--- result");
        if (errors == 0) $display("RESULT: PASS (0 errors)");
        else             $display("RESULT: FAIL (%0d errors)", errors);
        $finish;
    end

    initial begin
        #5_000_000;
        $display("RESULT: FAIL (timeout)");
        $finish;
    end
endmodule