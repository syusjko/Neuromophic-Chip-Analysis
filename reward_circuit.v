// =============================================================================
// Module  : reward_circuit (v2 - 소거 버그 수정)
// Project : HNSN - Phase 5: Neuromodulation
//
// [v2 수정 사항]
//   - reward_count 감소를 매 클럭이 아닌 DECAY_RATE 클럭마다 1씩 감소
//     → predict_state가 너무 빨리 해제되는 버그 수정
//   - predict_state 해제 조건: reward_count가 완전히 0이 될 때만
//
// [보상 예측 오류 (RPE) 로직]
//   reward=1, prediction=0 → 예상 밖 보상 → dopamine=11 (최대)
//   reward=1, prediction=1 → 예상된 보상  → dopamine=01 (기본)
//   reward=0, prediction=0 → 보상 없음    → dopamine=01 (기본)
//   reward=0, prediction=1 → 예상 보상 없음→ dopamine=00 (억제)
// =============================================================================

module reward_circuit #(
    parameter [3:0] PREDICT_THRESH = 4'd5, // 연속 보상 횟수 → 예측 상태 전환
    parameter [3:0] DECAY_RATE     = 4'd8  // 카운터 감소 속도 (클럭/1감소)
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       reward,

    output reg  [1:0] dopamine_level,
    output wire       prediction
);

    reg [3:0] reward_count;   // 연속 보상 카운터
    reg [3:0] decay_counter;  // 감소 속도 조절용 카운터
    reg       predict_state;

    assign prediction = predict_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reward_count   <= 4'd0;
            decay_counter  <= 4'd0;
            predict_state  <= 1'b0;
            dopamine_level <= 2'b01;
        end
        else begin
            // -----------------------------------------------------------------
            // 예측 상태 업데이트
            // -----------------------------------------------------------------
            if (reward) begin
                // 보상 있음: 카운터 빠르게 증가
                decay_counter <= 4'd0;  // 감소 타이머 리셋
                if (reward_count < PREDICT_THRESH)
                    reward_count <= reward_count + 4'd1;
                else
                    predict_state <= 1'b1;
            end
            else begin
                // 보상 없음: DECAY_RATE 클럭마다 카운터 1 감소
                if (decay_counter < DECAY_RATE) begin
                    decay_counter <= decay_counter + 4'd1;
                end
                else begin
                    decay_counter <= 4'd0;
                    if (reward_count > 4'd0)
                        reward_count <= reward_count - 4'd1;
                end
                // 카운터가 완전히 소진되면 예측 상태 해제
                if (reward_count == 4'd0)
                    predict_state <= 1'b0;
            end

            // -----------------------------------------------------------------
            // 도파민 레벨 결정
            // -----------------------------------------------------------------
            case ({reward, predict_state})
                2'b10: dopamine_level <= 2'b11; // 예상 밖 보상 → 최대
                2'b11: dopamine_level <= 2'b01; // 예상된 보상  → 기본
                2'b00: dopamine_level <= 2'b01; // 보상 없음    → 기본
                2'b01: dopamine_level <= 2'b00; // 예상 배반    → 억제
            endcase
        end
    end

endmodule
// =============================================================================
// End of reward_circuit.v (v2)
// =============================================================================
