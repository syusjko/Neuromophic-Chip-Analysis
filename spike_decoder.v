// =============================================================================
// Module  : spike_decoder (v5 - 그룹별 독립 판단)
// Project : HNSN - Phase 6
//
// [v5 변경]
//   WTA 의존 제거 → 디코더 내부에서 그룹별 독립 판단
//
//   [그룹 정의]
//   Group A: N0(bit0) + N1(bit1) → 'E' (둘 다 충분히 발화 시)
//            N0만                 → 'A'
//            N1만                 → 'B'
//   Group B: N2(bit2) + N3(bit3) → 'F' (둘 다 충분히 발화 시)
//            N2만                 → 'C'
//            N3만                 → 'D'
//
//   [우선순위]
//   두 그룹 모두 발화 → 더 많이 발화한 그룹 선택
//   동점 → 이전 출력 유지
//
//   [동작]
//   WINDOW_SIZE 클럭 동안 각 뉴런 발화 횟수 카운트
//   → 그룹별 총 발화 수 비교
//   → 우세 그룹의 패턴 결정
//   → CONFIRM_CNT 윈도우 연속 같은 패턴 → 출력 확정
// =============================================================================

module spike_decoder #(
    parameter [4:0] WINDOW_SIZE  = 5'd16,
    parameter [3:0] FIRE_THRESH  = 4'd4,   // 개별 뉴런 발화 인정 임계값
    parameter [2:0] CONFIRM_CNT  = 3'd2
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] spike_pattern,   // rec_spike 직접 입력 (WTA 불필요)

    output reg  [7:0] char_out,
    output reg        char_valid,
    output reg        char_changed
);

    // -------------------------------------------------------------------------
    // 내부 레지스터
    // -------------------------------------------------------------------------
    reg [4:0] cnt0, cnt1, cnt2, cnt3;
    reg [4:0] win_cnt;
    reg [3:0] decided_latch;
    reg [3:0] win_pattern;
    reg [2:0] confirm_cnt;
    reg [7:0] prev_char;
    reg       do_compare;

    // -------------------------------------------------------------------------
    // 그룹별 발화 수 (조합 논리)
    // -------------------------------------------------------------------------
    wire [5:0] sum_a = {1'b0, cnt0} + {1'b0, cnt1};  // Group A 총 발화
    wire [5:0] sum_b = {1'b0, cnt2} + {1'b0, cnt3};  // Group B 총 발화

    // 개별 뉴런 임계값 초과 여부
    wire fire0 = (cnt0 >= FIRE_THRESH);
    wire fire1 = (cnt1 >= FIRE_THRESH);
    wire fire2 = (cnt2 >= FIRE_THRESH);
    wire fire3 = (cnt3 >= FIRE_THRESH);

    // 그룹별 패턴 결정
    wire [3:0] pat_a = {2'b00, fire1, fire0};  // Group A 패턴
    wire [3:0] pat_b = {fire3, fire2, 2'b00};  // Group B 패턴

    // 우세 그룹 선택
    wire [3:0] decided_now =
        (sum_a > sum_b) ? pat_a :   // Group A 우세
        (sum_b > sum_a) ? pat_b :   // Group B 우세
        4'b0000;                     // 동점 → 미결정

    // -------------------------------------------------------------------------
    // 룩업 테이블
    // -------------------------------------------------------------------------
    function [7:0] pattern_to_char;
        input [3:0] pattern;
        begin
            case (pattern)
                4'b0001: pattern_to_char = 8'h41; // 'A' (N0만)
                4'b0010: pattern_to_char = 8'h42; // 'B' (N1만)
                4'b0100: pattern_to_char = 8'h43; // 'C' (N2만)
                4'b1000: pattern_to_char = 8'h44; // 'D' (N3만)
                4'b0011: pattern_to_char = 8'h45; // 'E' (N0+N1) ← 패턴 A
                4'b1100: pattern_to_char = 8'h46; // 'F' (N2+N3) ← 패턴 B
                4'b0101: pattern_to_char = 8'h47; // 'G'
                4'b1010: pattern_to_char = 8'h48; // 'H'
                4'b0000: pattern_to_char = 8'h20; // ' '
                default: pattern_to_char = 8'h3F; // '?'
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // 순차 논리
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt0 <= 0; cnt1 <= 0; cnt2 <= 0; cnt3 <= 0;
            win_cnt      <= 0;
            decided_latch<= 0;
            win_pattern  <= 0;
            confirm_cnt  <= 0;
            prev_char    <= 8'h20;
            char_out     <= 8'h20;
            char_valid   <= 0;
            char_changed <= 0;
            do_compare   <= 0;
        end
        else begin
            char_valid   <= 0;
            char_changed <= 0;

            if (do_compare) begin
                // COMPARE 단계
                do_compare <= 0;

                if (decided_latch != 4'b0000) begin
                    if (decided_latch == win_pattern) begin
                        if (confirm_cnt < CONFIRM_CNT)
                            confirm_cnt <= confirm_cnt + 1;
                        else begin
                            char_out   <= pattern_to_char(decided_latch);
                            char_valid <= 1;
                            if (pattern_to_char(decided_latch) != prev_char) begin
                                char_changed <= 1;
                                prev_char    <= pattern_to_char(decided_latch);
                            end
                        end
                    end
                    else begin
                        win_pattern <= decided_latch;
                        confirm_cnt <= 0;
                    end
                end
                // 동점(0000)이면 아무것도 안 함 → 이전 상태 유지
            end
            else begin
                // COUNT 단계: 발화 카운팅
                if (spike_pattern[0]) cnt0 <= (cnt0<31) ? cnt0+1 : cnt0;
                if (spike_pattern[1]) cnt1 <= (cnt1<31) ? cnt1+1 : cnt1;
                if (spike_pattern[2]) cnt2 <= (cnt2<31) ? cnt2+1 : cnt2;
                if (spike_pattern[3]) cnt3 <= (cnt3<31) ? cnt3+1 : cnt3;

                win_cnt <= win_cnt + 1;

                if (win_cnt >= WINDOW_SIZE - 1) begin
                    decided_latch <= decided_now;  // 래치
                    cnt0 <= 0; cnt1 <= 0; cnt2 <= 0; cnt3 <= 0;
                    win_cnt    <= 0;
                    do_compare <= 1;
                end
            end
        end
    end

endmodule
// =============================================================================
// End of spike_decoder.v (v5)
// =============================================================================
