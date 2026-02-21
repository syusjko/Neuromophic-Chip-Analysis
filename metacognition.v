// =============================================================================
// Module: metacognition
// Project: Phase-based Spiking Transformer - V3.3
//
// [역할]
//   에피소드 기억의 안정성(ep_strength)을 모니터링하여
//   현재 인지 상태가 "확신(exploit)"인지 "탐색(explore)"인지 판단
//
// [동작]
//   theta_tick마다 ep_strength 체크:
//   - ep_strength >= EXPLOIT_THR: exploit_mode=1 (현재 패턴 신뢰)
//   - ep_strength <= EXPLORE_THR: explore_mode=1 (새 패턴 탐색 필요)
//   - 중간 구간: 둘 다 0 (전환 중, 대기 상태)
//
// [활용]
//   exploit_mode=1:
//     → W_MAX까지 학습 허용, 빠른 강화
//     → "잘 알고 있는 것은 더 빠르게 익힌다"
//   explore_mode=1:
//     → context_gate 강화 (rel이 지배)
//     → "모르는 것이 들어오면 선입견을 내려놓는다"
//
// [뇌 비유]
//   exploit: 전두엽 톱다운 (기존 패턴 강화)
//   explore: ACC/노르에피네프린 (불확실성 신호 → 새 자극 주의)
// =============================================================================

module metacognition #(
    parameter [3:0] EXPLOIT_THR    = 4'd6,
    parameter [3:0] EXPLORE_THR    = 4'd5,
    parameter [1:0] CONF_EXP_THR   = 2'd2,
    // V3.7: err 기반 explore 강제
    parameter [7:0] ERR_HIGH_THR   = 8'd50,  // 이 이상이면 "예측 실패"
    parameter [7:0] ERR_FORCE_WIN  = 8'd5    // 연속 N gamma → explore 강제
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       theta_tick,
    input  wire [3:0] ep_strength,
    input  wire       ep_valid,
    input  wire [7:0] pred_err,
    input  wire       cyc_start,
    input  wire       input_mismatch,  // V3.7b: 입력 패턴 불일치 (조기 감지)

    output reg        exploit_mode,
    output wire       explore_mode,
    output reg [1:0]  confidence_level,
    output wire       err_explore    // V3.7: err 기반 탐색 신호 (별도 관찰용)
);
    // -------------------------------------------------------------------------
    // V3.7: pred_err 기반 explore 강제 카운터
    // "예측이 N 사이클 연속으로 크게 틀리면 현재 문맥을 의심하라"
    // -------------------------------------------------------------------------
    reg [7:0] err_high_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            err_high_cnt <= 8'd0;
        end
        else if (cyc_start) begin
            if (pred_err > ERR_HIGH_THR) begin
                if (err_high_cnt < ERR_FORCE_WIN)
                    err_high_cnt <= err_high_cnt + 8'd1;
            end
            else begin
                err_high_cnt <= 8'd0;  // 오차 낮아지면 카운터 리셋
            end
        end
    end

    wire err_forced = (err_high_cnt >= ERR_FORCE_WIN);

    // explore_mode: 에피소드 불안정 OR 예측 오류 OR 입력 불일치
    assign err_explore  = err_forced;
    assign explore_mode = err_forced ||
                          input_mismatch ||           // V3.7b: 즉시 감지
                          (ep_valid &&
                           (ep_strength   <= EXPLORE_THR) &&
                           (confidence_level <= CONF_EXP_THR));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            exploit_mode     <= 1'b0;
            confidence_level <= 2'd0;
        end
        else if (theta_tick && ep_valid) begin
            if (ep_strength >= EXPLOIT_THR) begin
                confidence_level <= 2'd3;
                exploit_mode     <= 1'b1;
            end
            else if (ep_strength <= EXPLORE_THR) begin
                if (confidence_level == 2'd3)
                    confidence_level <= 2'd2;
                else
                    confidence_level <= 2'd1;
                exploit_mode <= 1'b0;
            end
            else begin
                confidence_level <= 2'd2;
                exploit_mode     <= 1'b0;
            end
        end
    end
endmodule
