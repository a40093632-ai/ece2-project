`timescale 1ns/1ps
// Fixed-width ASCII protocol described in docs/stage2_interfaces.md.
// A complete checksummed frame commits atomically. No live partial data outputs.
module project_frame_rx #(
    parameter integer CLK_HZ=50_000_000
)(
    input wire clk,rst,
    input wire [7:0] byte_data,
    input wire byte_valid, byte_error,
    output reg time_event, measure_event, result_event, frame_error,
    output reg [15:0] time_seq, measure_seq, measure_session,
    output reg [31:0] date_ymd, time_hms,
    output reg [2:0] weekday,
    output reg time_ok, measure_ok, session_ack,
    output reg [31:0] bus_mv, current_ua, power_uw,
    output reg [63:0] total_uwh, session_uwh
);
    localparam [3:0] SEEK=0, TYPE=1, COMMA=2, FIELD=3, HEX_HI=4,
        HEX_LO=5, ENDING=6, LF=7;
    localparam integer GAP=(CLK_HZ/10<1)?1:CLK_HZ/10;
    reg [3:0] state;
    reg is_measure,is_result;
    reg [3:0] field_no, digit_count;
    reg [39:0] accum, fields[0:8];
    reg [7:0] checksum, received_checksum;
    reg [31:0] gap_count;
    integer k;
    function integer width_for;
        input m; input [3:0] f;
        begin
            if(!m) case(f)
                0:width_for=4; 1:width_for=8; 2:width_for=6;
                3,4:width_for=1; default:width_for=0;
            endcase
            else case(f)
                0,1:width_for=4; 2:width_for=5; 3,4:width_for=6;
                5,6:width_for=12; 7,8:width_for=1; default:width_for=0;
            endcase
        end
    endfunction
    function hex_char;
        input [7:0] c;
        begin hex_char=(c>=8'h30 && c<=8'h39)||(c>=8'h41 && c<=8'h46); end
    endfunction
    function [3:0] hex_value;
        input [7:0] c;
        begin hex_value=(c<=8'h39)?c-8'h30:c-8'h41+10; end
    endfunction
    // Decimal components are collected directly from ASCII; no binary division.
    reg [13:0] cal_year;
    reg [6:0] cal_month,cal_day,cal_hour,cal_minute,cal_second;
    reg [6:0] year_offset;
    reg leap,cal_good;
    reg [5:0] month_days;
    reg [2:0] month_offset;
    reg [7:0] week_sum;
    localparam [3:0] CAL0=8,CAL1=9,CAL2=10,CAL3=11;
    wire [3:0] dec_digit=byte_data[3:0];
    wire field_hex = field_no==0 || (is_measure && field_no==1);
    wire digit_ok = field_hex?hex_char(byte_data):(byte_data>=8'h30 && byte_data<=8'h39);
    wire [39:0] next_accum = field_hex ? ((accum<<4)|hex_value(byte_data)) :
        accum*10+(byte_data-8'h30);
    wire measure_range_ok=fields[2]<=26000 && fields[7]<=1 && fields[8]<=1;
    task commit_time;
      input valid_time;
      begin
        time_seq<=fields[0][15:0];date_ymd<=fields[1][31:0];
        time_hms<=fields[2][31:0];weekday<=fields[3][2:0];
        time_ok<=valid_time;time_event<=1;state<=SEEK;
      end
    endtask
    always @(posedge clk) begin
        if(rst) begin
            state<=SEEK;is_measure<=0;is_result<=0;field_no<=0;digit_count<=0;accum<=0;
            checksum<=0;received_checksum<=0;gap_count<=0;
            time_event<=0;measure_event<=0;result_event<=0;frame_error<=0;
            time_seq<=0;measure_seq<=0;measure_session<=0;date_ymd<=0;
            time_hms<=0;weekday<=0;time_ok<=0;measure_ok<=0;session_ack<=0;
            bus_mv<=0;current_ua<=0;power_uw<=0;total_uwh<=0;session_uwh<=0;
            for(k=0;k<9;k=k+1)fields[k]<=0;
            cal_year<=0;cal_month<=0;cal_day<=0;cal_hour<=0;cal_minute<=0;cal_second<=0;
            year_offset<=0;leap<=0;cal_good<=0;month_days<=0;month_offset<=0;week_sum<=0;
        end else begin
            time_event<=0;measure_event<=0;result_event<=0;frame_error<=0;
            if(byte_error) begin state<=SEEK;frame_error<=1;gap_count<=0; end
            else if(byte_valid) begin
                gap_count<=0;
                if(byte_data==8'h24) begin // '$' resynchronizes even within a broken frame.
                    if(state!=SEEK)frame_error<=1;
                    state<=TYPE;checksum<=0;accum<=0;field_no<=0;digit_count<=0;
                    cal_year<=0;cal_month<=0;cal_day<=0;cal_hour<=0;cal_minute<=0;cal_second<=0;
                end else case(state)
                    SEEK: ;
                    TYPE: if(byte_data=="T" || byte_data=="M" || byte_data=="F") begin
                        is_measure<=byte_data!="T";is_result<=byte_data=="F";
                        checksum<=byte_data;state<=COMMA;
                    end else begin state<=SEEK;frame_error<=1; end
                    COMMA: if(byte_data==",") begin checksum<=checksum^byte_data;state<=FIELD; end
                        else begin state<=SEEK;frame_error<=1; end
                    FIELD: if(digit_ok && digit_count<width_for(is_measure,field_no)) begin
                        accum<=next_accum;digit_count<=digit_count+1'b1;checksum<=checksum^byte_data;
                        if(!is_measure && field_no==1)begin
                            if(digit_count<4)cal_year<=cal_year*10+dec_digit;
                            else if(digit_count<6)cal_month<=cal_month*10+dec_digit;
                            else cal_day<=cal_day*10+dec_digit;
                        end
                        if(!is_measure && field_no==2)begin
                            if(digit_count<2)cal_hour<=cal_hour*10+dec_digit;
                            else if(digit_count<4)cal_minute<=cal_minute*10+dec_digit;
                            else cal_second<=cal_second*10+dec_digit;
                        end
                    end else if(digit_count==width_for(is_measure,field_no) &&
                        ((byte_data=="," && field_no<(is_measure?8:4)) ||
                         (byte_data=="*" && field_no==(is_measure?8:4)))) begin
                        fields[field_no]<=accum;accum<=0;digit_count<=0;
                        if(byte_data=="*")state<=HEX_HI;
                        else begin field_no<=field_no+1'b1;checksum<=checksum^byte_data; end
                    end else begin state<=SEEK;frame_error<=1; end
                    HEX_HI: if(hex_char(byte_data)) begin
                        received_checksum[7:4]<=hex_value(byte_data);state<=HEX_LO;
                    end else begin state<=SEEK;frame_error<=1; end
                    HEX_LO: if(hex_char(byte_data)) begin
                        received_checksum[3:0]<=hex_value(byte_data);state<=ENDING;
                    end else begin state<=SEEK;frame_error<=1; end
                    ENDING,LF: if(byte_data==10) begin
                        state<=SEEK;
                        if(checksum==received_checksum && (is_measure?measure_range_ok:fields[4]<=1)) begin
                            if(is_measure) begin
                                measure_seq<=fields[0][15:0];measure_session<=fields[1][15:0];
                                bus_mv<=fields[2][31:0];current_ua<=fields[3][31:0];power_uw<=fields[4][31:0];
                                total_uwh<=fields[5];session_uwh<=fields[6];
                                measure_ok<=fields[7][0];session_ack<=fields[8][0];
                                // For F, the final flag means complete, not an ARM acknowledgement.
                                measure_event<=!is_result;result_event<=is_result;
                            end else begin
                                if(fields[4]==0)commit_time(1'b0);
                                else state<=CAL0;
                            end
                        end else frame_error<=1;
                    end else if(state==ENDING && byte_data==13)state<=LF;
                    else begin state<=SEEK;frame_error<=1; end
                    default:state<=SEEK;
                endcase
            end else if(state==CAL0)begin
                year_offset<=cal_year-14'd2000;leap<=cal_year[1:0]==0;
                cal_good<=cal_year>=2000 && cal_year<=2099 && cal_month>=1 && cal_month<=12 &&
                    cal_day>=1 && cal_hour<24 && cal_minute<60 && cal_second<60 && fields[3]>=1 && fields[3]<=7;
                state<=CAL1;
            end else if(state==CAL1)begin
                case(cal_month)
                    4,6,9,11:month_days<=30;
                    2:month_days<=leap?29:28;
                    default:month_days<=31;
                endcase
                // Cumulative non-leap month days, modulo seven.
                case(cal_month)
                    1:month_offset<=0;2,3:month_offset<=3;4:month_offset<=6;
                    5:month_offset<=1;6:month_offset<=4;7:month_offset<=6;
                    8:month_offset<=2;9:month_offset<=5;10:month_offset<=0;
                    11:month_offset<=3;default:month_offset<=5;
                endcase
                week_sum<=8'd4+{1'b0,year_offset}+(({1'b0,year_offset}+8'd3)>>2);
                state<=CAL2;
            end else if(state==CAL2)begin
                week_sum<=week_sum+{5'b0,month_offset}+{1'b0,cal_day}+((leap && cal_month>2)?8'd1:8'd0);
                state<=CAL3;
            end else if(state==CAL3)begin
                if(week_sum>=7)week_sum<=week_sum-8'd7;
                else begin
                    state<=SEEK;
                    if(cal_good && cal_day<=month_days && fields[3]==week_sum+8'd1)commit_time(1'b1);
                    else frame_error<=1;
                end
            end else if(state!=SEEK) begin
                if(gap_count==GAP-1) begin state<=SEEK;gap_count<=0;frame_error<=1; end
                else gap_count<=gap_count+1'b1;
            end else gap_count<=0;
        end
    end
endmodule
