// =============================================================================
// Module  : pst_2layer (v2 - 진짜 계층적 학습)
//
// [핵심 변경]
//   L3 error → L2 eta_boost_in (학습률 변조)
//   "L3가 놀라면 L2도 더 빠르게 학습"
//
// [연결]
//   L3 eta_boost_out (= L3_err/4) → L2 eta_boost_in
//   L3 pred_phase_out → L2 pred_phase_in (top-down)
// =============================================================================

module pst_2layer #(
    parameter [7:0] THRESHOLD = 8'd200,
    parameter [7:0] W_INIT    = 8'd128,
    parameter [7:0] ETA_LTP   = 8'd4,
    parameter [7:0] ETA_LTD   = 8'd3,
    parameter [7:0] WINDOW    = 8'd128
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       cycle_start,
    input  wire [7:0] global_phase,

    input  wire [7:0] input_current,

    // L3 동결 제어: l3_freeze=1이면 L3 eta_boost_out=0 (L2에 영향 안 줌)
    input  wire       l3_freeze,

    output wire [7:0] phase_L1,
    output wire       fired_L1,

    output wire [7:0] pred_L2,
    output wire [7:0] error_L2,
    output wire       err_sign_L2,
    output wire [7:0] weight_L2,

    output wire [7:0] pred_L3,
    output wire [7:0] error_L3,
    output wire       err_sign_L3,
    output wire [7:0] weight_L3,

    // 모니터링
    output wire [7:0] eta_boost_L2  // L2가 받는 학습률 증폭량
);

    // L1
    wire spk_L1;
    phase_neuron #(.THRESHOLD(THRESHOLD), .LEAK(8'd0)) L1 (
        .clk(clk), .rst_n(rst_n),
        .global_phase(global_phase), .cycle_start(cycle_start),
        .input_current(input_current),
        .spike_out(spk_L1), .phase_lock(phase_L1), .fired_this_cycle(fired_L1)
    );

    // L3 → L2 연결선
    wire [7:0] pred_L3_to_L2;
    wire       err_valid_L3;
    wire [7:0] eta_from_L3;     // L3 eta_boost_out

    // l3_freeze=1이면 boost=0 (L3 비활성화와 동일 효과)
    assign eta_boost_L2 = l3_freeze ? 8'd0 : eta_from_L3;

    // ── L2 ──────────────────────────────────────────────────────
    wire err_valid_L2;
    wire [7:0] eta_boost_L2_unused;  // L2의 boost_out (사용 안 함)

    predictive_phase #(
        .W_INIT(W_INIT), .ETA_LTP(ETA_LTP), .ETA_LTD(ETA_LTD), .WINDOW(WINDOW)
    ) L2 (
        .clk(clk), .rst_n(rst_n), .cycle_start(cycle_start),
        .actual_phase(phase_L1), .fired_actual(fired_L1),
        .pred_phase_in(pred_L3_to_L2),
        .pred_valid(err_valid_L3),
        .eta_boost_in(eta_boost_L2),   // L3 오차 → L2 학습률 증폭
        .error_mag(error_L2), .error_sign(err_sign_L2),
        .error_valid(err_valid_L2),
        .pred_phase_out(pred_L2),
        .weight(weight_L2),
        .eta_boost_out(eta_boost_L2_unused)
    );

    // ── L3 ──────────────────────────────────────────────────────
    predictive_phase #(
        .W_INIT(W_INIT), .ETA_LTP(ETA_LTP), .ETA_LTD(ETA_LTD), .WINDOW(WINDOW)
    ) L3 (
        .clk(clk), .rst_n(rst_n), .cycle_start(cycle_start),
        .actual_phase(pred_L2), .fired_actual(fired_L1),
        .pred_phase_in(8'd128), .pred_valid(1'b0),
        .eta_boost_in(8'd0),   // 최상위: 외부 boost 없음
        .error_mag(error_L3), .error_sign(err_sign_L3),
        .error_valid(err_valid_L3),
        .pred_phase_out(pred_L3_to_L2),
        .weight(weight_L3),
        .eta_boost_out(eta_from_L3)
    );

    assign pred_L3 = pred_L3_to_L2;

endmodule
