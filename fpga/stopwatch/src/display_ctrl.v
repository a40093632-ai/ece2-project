`timescale 1ns/1ps
// 화면 전환, 버튼 분배, 8자리 표시 내용 선택
//   화면 : 0 시계 -> 1 스톱워치 -> 2 예약 -> 3 측정 -> 0 (MODE로 순환)
//   SET  : 시계 화면 날짜/시각 전환, 측정 화면 V->I->P->E 전환, 예약 화면 FAULT 해제 확인
//   START: 스톱워치 화면 시작/일시정지, 예약 화면 예약 시작
//   CLEAR: 현재 화면만 초기화 (스톱워치 초기화, 예약 취소). 시계, 측정 화면은 동작 없음
//          CANCEL_ALL_SCREENS=1이면 어느 화면에서든 예약도 취소
//   digits, dp는 seg_scan8에 연결한다.
//   표시 예외: 수신 전 "--------", 무효 계측은 마지막 값 깜빡임, 에너지 범위 초과 "E-------"
module display_ctrl #(
    parameter CANCEL_ALL_SCREENS = 0,
    parameter EXTERNAL_SELECTION = 0
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_10ms,
    input wire [1:0] external_screen,external_measure_item,
    input wire external_date_selected,
    // 버튼 펄스 (button_onepulse 출력)
    input  wire        mode_pulse,
    input  wire        set_pulse,
    input  wire        start_pulse,
    input  wire        clear_pulse,
    // 시계 (MCU 수신값, 자리별 BCD)
    input  wire        time_valid,
    input  wire [31:0] date_bcd,      // YYYYMMDD
    input  wire [23:0] time_bcd,      // HHMMSS
    input  wire [7:0]  dow_bcd,       // 01~07
    // 스톱워치
    input  wire [23:0] sw_bcd,        // MMSScc
    input  wire        sw_running,
    // 예약 (scheduler)
    input wire [2:0] rsv_state,      // 0 IDLE,1 WAIT,2 RUN,3 DONE,4 ARM,5 FAULT
    input  wire [31:0] rsv_remain_s,  // 남은 초, 이진수 (0~9999)
    input  wire        rsv_wait,
    input  wire        rsv_run,
    input  wire        rsv_fault,
    // 계측 (MCU 수신값, 자리별 BCD 8자리)
    input  wire        meas_rx,       // 정상 계측을 한 번이라도 받았으면 1
    input  wire        meas_valid,    // 최근 계측이 유효하면 1
    input  wire        e_overflow,    // 에너지 99999.999mWh 초과
    input  wire [31:0] meas_v_bcd,    // 단위 1mV
    input  wire [31:0] meas_i_bcd,    // 단위 0.01mA
    input  wire [31:0] meas_p_bcd,    // 단위 0.1mW
    input  wire [31:0] meas_e_bcd,    // 단위 0.001mWh
    // 버튼 분배
    output wire        sw_start_pause,
    output wire        sw_clear,
    output wire        rsv_start,
    output wire        rsv_cancel,
    output wire        fault_ack,
    // 표시
    output reg  [1:0]  screen,
    output reg  [31:0] digits,
    output reg  [7:0]  dp,
    output reg  [6:0]  led            // LED1~LED7, LED8은 system에서 부하 출력 표시
);
    localparam [1:0] SCR_CLOCK = 2'd0;
    localparam [1:0] SCR_SW    = 2'd1;
    localparam [1:0] SCR_RSV   = 2'd2;
    localparam [1:0] SCR_MEAS  = 2'd3;

    localparam [31:0] ALL_DASH  = 32'hAAAA_AAAA;   // --------
    localparam [31:0] ALL_BLANK = 32'hFFFF_FFFF;
    localparam [31:0] OVERFLOW  = 32'hBAAA_AAAA;   // E-------

    reg       clk_sel;     // 시계: 0 날짜, 1 시각+요일
    reg [1:0] meas_sel;    // 측정: 0 V, 1 I, 2 P, 3 E
    reg [5:0] blink_cnt;
    reg       blink_off;   // 0.5초마다 바뀜

    // 화면 상태와 SET 선택 (화면을 바꿔도 선택값은 기억)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            screen   <= SCR_CLOCK;
            clk_sel  <= 1'b0;
            meas_sel <= 2'd0;
        end else if (EXTERNAL_SELECTION) begin
            screen <= external_screen;
            clk_sel <= !external_date_selected;
            meas_sel <= external_measure_item;
        end else begin
            if (mode_pulse)
                screen <= screen + 2'd1;
            if (set_pulse && screen == SCR_CLOCK)
                clk_sel <= ~clk_sel;
            if (set_pulse && screen == SCR_MEAS)
                meas_sel <= meas_sel + 2'd1;
        end
    end

    // 무효 표시용 깜빡임 (0.01초 x 50 = 0.5초)
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            blink_cnt <= 6'd0;
            blink_off <= 1'b0;
        end else if (tick_10ms) begin
            if (blink_cnt == 6'd49) begin
                blink_cnt <= 6'd0;
                blink_off <= ~blink_off;
            end else begin
                blink_cnt <= blink_cnt + 1'b1;
            end
        end
    end

    // 버튼 분배: 현재 화면에만 전달
    assign sw_start_pause = start_pulse && !clear_pulse && !mode_pulse && !set_pulse && (screen == SCR_SW);
    assign sw_clear       = clear_pulse && (screen == SCR_SW);
    assign rsv_start      = start_pulse && !clear_pulse && !mode_pulse && !set_pulse && (screen == SCR_RSV);
    assign rsv_cancel     = clear_pulse && ((screen == SCR_RSV) || (CANCEL_ALL_SCREENS != 0));
    assign fault_ack      = clear_pulse && (screen == SCR_RSV) && rsv_fault;

    // 남은 초(이진수) -> 8자리 BCD
    wire [31:0] reservation_bcd;
    remaining_seconds_bcd convert_remaining(.clk(clk),.rst(rst),.value(rsv_remain_s),.result(reservation_bcd));


    // 측정 항목 선택과 DP 위치
    reg [31:0] meas_val;
    reg [7:0]  meas_dp;
    always @* begin
        case (meas_sel)
            2'd0:    begin meas_val = meas_v_bcd; meas_dp = 8'b0000_0000; end // 00005000 (mV)
            2'd1:    begin meas_val = meas_i_bcd; meas_dp = 8'b0000_0100; end // 000100.80 (mA)
            2'd2:    begin meas_val = meas_p_bcd; meas_dp = 8'b0000_0010; end // 0000477.5 (mW)
            default: begin meas_val = meas_e_bcd; meas_dp = 8'b0000_1000; end // 00000.694 (mWh)
        endcase
    end

    // 화면별 표시 내용
    always @* begin
        digits = ALL_BLANK;
        dp     = 8'd0;
        led    = 7'd0;
        case (screen)
            SCR_CLOCK: begin
                led[0] = ~clk_sel;               // LED1 날짜
                led[1] =  clk_sel;               // LED2 시각
                if (!time_valid) begin
                    digits = ALL_DASH;
                end else if (!clk_sel) begin
                    digits = date_bcd;           // 2026.11.16
                    dp     = 8'b0001_0100;
                end else begin
                    digits = {time_bcd, dow_bcd}; // 18.30.45.01
                    dp     = 8'b0101_0100;
                end
            end
            SCR_SW: begin
                digits = {8'h00, sw_bcd};        // 0001.23.45
                dp     = 8'b0001_0100;
                led[0] = sw_running;             // LED1 스톱워치 실행 중
            end
            SCR_RSV: begin
                digits = {1'b0,rsv_state,reservation_bcd[27:0]}; // state + seven remaining-second digits
            end
            default: begin                       // 측정
                led[meas_sel] = 1'b1;            // LED1~4 = V, I, P, E
                if (!meas_rx)
                    digits = ALL_DASH;
                else if (meas_sel == 2'd3 && e_overflow)
                    digits = OVERFLOW;
                else if (!meas_valid && blink_off)
                    digits = ALL_BLANK;
                else begin
                    digits = meas_val;
                    dp     = meas_dp;
                end
            end
        endcase
        led[4] = rsv_wait;                       // LED5 WAIT (모든 화면)
        led[5] = rsv_run;                        // LED6 RUN
        led[6] = rsv_fault;                      // LED7 FAULT
    end
endmodule
// Snapshot binary seconds and convert with one add-three stage per clock.
module remaining_seconds_bcd(input wire clk,rst,input wire [31:0] value,output reg [31:0] result);
 reg [31:0] bits_left,bcd;
 reg [5:0] count;
 reg [31:0] adjusted;
 integer j;
 always @* begin
  adjusted=bcd;
  for(j=0;j<8;j=j+1)if(bcd[j*4+:4]>=5)adjusted[j*4+:4]=bcd[j*4+:4]+4'd3;
 end
 always @(posedge clk)begin
  if(rst)begin bits_left<=0;bcd<=0;result<=0;count<=0;end
  else if(count==0)begin bits_left<=value;bcd<=0;count<=1;end
  else begin
   bcd<={adjusted[30:0],bits_left[31]};bits_left<=bits_left<<1;
   if(count==32)begin result<={adjusted[30:0],bits_left[31]};count<=0;end
   else count<=count+1'b1;
  end
 end
endmodule
