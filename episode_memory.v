// =============================================================================
// Module: episode_memory
// Project: Phase-based Spiking Transformer - V3.2
//
// [역할]
//   Theta 에피소드(8 gamma) 동안 winner 패턴을 투표로 요약
//   theta_tick에서 "이 에피소드를 지배한 쌍"을 저장
//   다음 에피소드에서 top-down prior로 사용 가능
//
// [동작]
//   gamma 0~7: 현재 winner를 vote[pair] 카운터에 누적
//   theta_tick: argmax(vote) → episode_winner 저장, vote 리셋
//   ep_valid: episode_winner가 유효 (최소 1번 이상 theta 완료)
//
// [뇌 비유]
//   해마-피질 상호작용:
//   해마가 theta 에피소드 동안 패턴을 누적하고
//   theta_tick에서 압축된 표현을 피질에 전달 (replay)
//
// [활용 계획]
//   V3.3: episode_winner → score bias 추가
//         "이 에피소드와 같은 패턴이 자주 왔으므로 다음도 그럴 것"
//         context-aware priming
// =============================================================================

module episode_memory (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       gamma_tick,       // gamma 사이클 시작
    input  wire       theta_tick,       // 에피소드 경계 (8 gamma마다)
    input  wire [2:0] current_winner,   // 현재 gamma의 winner (0~5)

    output reg  [2:0] episode_winner,   // 직전 에피소드 지배 패턴
    output reg  [3:0] episode_strength, // 지배 패턴의 득표 수 (최대 8)
    output reg        ep_valid          // episode_winner 유효
);
    // 6쌍 각각의 vote 카운터 (3비트, 최대 8)
    reg [3:0] vote_0, vote_1, vote_2, vote_3, vote_4, vote_5;

    // argmax (combinational)
    reg  [2:0] max_idx;
    reg  [3:0] max_val;
    always @(*) begin
        max_idx = 3'd0; max_val = vote_0;
        if (vote_1 > max_val) begin max_val = vote_1; max_idx = 3'd1; end
        if (vote_2 > max_val) begin max_val = vote_2; max_idx = 3'd2; end
        if (vote_3 > max_val) begin max_val = vote_3; max_idx = 3'd3; end
        if (vote_4 > max_val) begin max_val = vote_4; max_idx = 3'd4; end
        if (vote_5 > max_val) begin max_val = vote_5; max_idx = 3'd5; end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vote_0 <= 4'd0; vote_1 <= 4'd0; vote_2 <= 4'd0;
            vote_3 <= 4'd0; vote_4 <= 4'd0; vote_5 <= 4'd0;
            episode_winner   <= 3'd0;
            episode_strength <= 4'd0;
            ep_valid         <= 1'b0;
        end
        else if (theta_tick) begin
            // 에피소드 종료: argmax → 저장 → vote 리셋
            episode_winner   <= max_idx;
            episode_strength <= max_val;
            ep_valid         <= 1'b1;
            vote_0 <= 4'd0; vote_1 <= 4'd0; vote_2 <= 4'd0;
            vote_3 <= 4'd0; vote_4 <= 4'd0; vote_5 <= 4'd0;
        end
        else if (gamma_tick) begin
            // gamma마다 winner에 투표 (최대 8, 포화 방지)
            case (current_winner)
                3'd0: if (vote_0 < 4'd15) vote_0 <= vote_0 + 4'd1;
                3'd1: if (vote_1 < 4'd15) vote_1 <= vote_1 + 4'd1;
                3'd2: if (vote_2 < 4'd15) vote_2 <= vote_2 + 4'd1;
                3'd3: if (vote_3 < 4'd15) vote_3 <= vote_3 + 4'd1;
                3'd4: if (vote_4 < 4'd15) vote_4 <= vote_4 + 4'd1;
                3'd5: if (vote_5 < 4'd15) vote_5 <= vote_5 + 4'd1;
                default: ;
            endcase
        end
    end
endmodule
