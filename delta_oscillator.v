// =============================================================================
// Module: delta_oscillator
// Project: Phase-based Spiking Transformer - V3.4 Delta (주제 유지 회로)
//
// [역할]
//   여러 theta 에피소드를 하나의 "대화 의도 단위(delta)"로 묶음
//   뇌의 델타파(0.5-4Hz)가 수면 중 기억 통합, 의식적 주제 유지 담당
//   → delta_tick: 5 theta = 1 delta (주제 경계)
//
// [시간 스케일 계층]
//   BASE_CLK (50MHz)
//   → gamma  (256 clk  ≈ 200kHz): 순간 패턴 (단어 수준)
//   → theta  (8 gamma  ≈  24kHz): 에피소드  (문장 수준)
//   → delta  (5 theta  ≈ 4.9kHz): 대화 주제 (단락 수준)
//
//   비율: gamma:theta:delta = 40:5:1 → 뇌와 동일 (절대값 5000배 압축)
//
// [뇌 비유]
//   gamma → 단어 하나 처리 (버스트 스파이크)
//   theta → 문장 하나 에피소드 (해마 theta 묶음)
//   delta → 대화 주제 유지 (전두엽 델타, "나는 지금 무슨 얘기 중")
//
// [포트]
//   theta_tick: theta_oscillator의 출력
//   theta_cnt:  현재 delta 내 theta 위치 (0 ~ THETA_PER_DELTA-1)
//   delta_tick: 매 THETA_PER_DELTA theta마다 1클럭 펄스 (주제 경계)
//   topic_last: theta_cnt==THETA_PER_DELTA-1 (마지막 theta)
// =============================================================================

module delta_oscillator #(
    parameter [2:0] THETA_PER_DELTA = 3'd4  // 5 theta per delta (0~4)
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       theta_tick,    // theta 에피소드 경계 펄스

    output reg  [2:0] theta_cnt,     // delta 내 theta 위치 (0~4)
    output reg        delta_tick,    // 주제 경계 (5 theta마다 1클럭)
    output wire       topic_last     // theta_cnt==4: 주제 마지막 theta
);
    assign topic_last = (theta_cnt == THETA_PER_DELTA);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            theta_cnt  <= 3'd0;
            delta_tick <= 1'b0;
        end
        else begin
            delta_tick <= 1'b0;
            if (theta_tick) begin
                if (theta_cnt >= THETA_PER_DELTA) begin
                    theta_cnt  <= 3'd0;
                    delta_tick <= 1'b1;  // 주제 경계 펄스
                end
                else begin
                    theta_cnt <= theta_cnt + 3'd1;
                end
            end
        end
    end
endmodule
