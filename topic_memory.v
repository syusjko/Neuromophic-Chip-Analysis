// =============================================================================
// Module: topic_memory
// Project: Phase-based Spiking Transformer - V3.4 Topic (주제 기억)
//
// [역할]
//   delta 에피소드(5 theta) 동안 ep_winner를 투표로 요약
//   delta_tick에서 "이 대화 주제를 지배한 패턴"을 저장
//   = 전두엽의 "현재 대화 주제/의도" 유지 회로
//
// [동작]
//   theta 0~4: ep_winner를 topic_vote[pair] 누적
//   delta_tick: argmax(topic_vote) → topic_winner, topic_strength
//   topic_valid: 최소 1회 delta 완료 후 유효
//
// [계층 구조]
//   episode_memory: 8 gamma → 에피소드 요약 (문장)
//   topic_memory:   5 theta → 주제 요약 (단락/대화)
//   둘 다 동일한 투표 구조, 단지 시간 스케일만 다름
//
// [뇌 비유]
//   episode_memory: 해마 CA1 (단기 에피소드)
//   topic_memory:   전전두엽 (working memory, 주제 추적)
//   delta_tick에서 "지금 무슨 주제로 대화 중인가" 업데이트
//
// [활용 계획]
//   V3.5: topic_winner → score에 long-term bias 추가
//         "이 주제에서 자주 본 패턴 → 더 빠르게 인식"
//         = 대화 맥락 유지 (인간의 주의 지속)
// =============================================================================

module topic_memory #(
    parameter [2:0] TOPIC_STAB_THR = 3'd3  // 5 theta 중 3개 이상 일치해야 업데이트
                                            // "떠들썩한 소수의 의견은 무시"
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       theta_tick,
    input  wire       delta_tick,
    input  wire [2:0] ep_winner,

    output reg  [2:0] topic_winner,
    output reg  [2:0] topic_strength,
    output reg        topic_valid
);
    reg [2:0] tvote_0, tvote_1, tvote_2, tvote_3, tvote_4, tvote_5;

    reg [2:0] tmax_idx;
    reg [2:0] tmax_val;
    always @(*) begin
        tmax_idx = 3'd0; tmax_val = tvote_0;
        if (tvote_1 > tmax_val) begin tmax_val = tvote_1; tmax_idx = 3'd1; end
        if (tvote_2 > tmax_val) begin tmax_val = tvote_2; tmax_idx = 3'd2; end
        if (tvote_3 > tmax_val) begin tmax_val = tvote_3; tmax_idx = 3'd3; end
        if (tvote_4 > tmax_val) begin tmax_val = tvote_4; tmax_idx = 3'd4; end
        if (tvote_5 > tmax_val) begin tmax_val = tvote_5; tmax_idx = 3'd5; end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tvote_0 <= 3'd0; tvote_1 <= 3'd0; tvote_2 <= 3'd0;
            tvote_3 <= 3'd0; tvote_4 <= 3'd0; tvote_5 <= 3'd0;
            topic_winner   <= 3'd0;
            topic_strength <= 3'd0;
            topic_valid    <= 1'b0;
        end
        else if (delta_tick) begin
            // 안정성 조건: 과반수(≥3/5) 이상일 때만 topic 갱신
            // 미만이면 이전 topic_winner 유지 ("소수 의견은 무시")
            if (tmax_val >= TOPIC_STAB_THR) begin
                topic_winner   <= tmax_idx;
                topic_strength <= tmax_val;
            end
            // tmax_val < THR이면 topic_winner 유지, strength만 업데이트
            topic_strength <= tmax_val;
            topic_valid    <= 1'b1;
            // vote 리셋
            tvote_0 <= 3'd0; tvote_1 <= 3'd0; tvote_2 <= 3'd0;
            tvote_3 <= 3'd0; tvote_4 <= 3'd0; tvote_5 <= 3'd0;
        end
        else if (theta_tick) begin
            case (ep_winner)
                3'd0: if (tvote_0 < 3'd7) tvote_0 <= tvote_0 + 3'd1;
                3'd1: if (tvote_1 < 3'd7) tvote_1 <= tvote_1 + 3'd1;
                3'd2: if (tvote_2 < 3'd7) tvote_2 <= tvote_2 + 3'd1;
                3'd3: if (tvote_3 < 3'd7) tvote_3 <= tvote_3 + 3'd1;
                3'd4: if (tvote_4 < 3'd7) tvote_4 <= tvote_4 + 3'd1;
                3'd5: if (tvote_5 < 3'd7) tvote_5 <= tvote_5 + 3'd1;
                default: ;
            endcase
        end
    end
endmodule
