// =============================================================================
// Module  : pst_2layer_cseq (v3)
//
// [v2 → v3 핵심 수정]
//   v2: L3 actual = pred_L2 (순환 의존성 → 불안정)
//   v3: L3 actual = phase_L1 (독립 입력 직접 관측)
//
//   L3가 phase_L1을 직접 학습:
//     slot[X] ← ph=1 전문화
//     slot[Y] ← ph=40 전문화
//     w_seq: 1→40, 40→1 시퀀스
//   L2가 L3 pred 수신:
//     "다음에 40이 올 것" → L2 미리 준비
//
//   정보 흐름 명확히 분리:
//     L1 → L3 (실제 입력 학습)
//     L3 → L2 (미래 예측, top-down)
//     L1 → L2 (실제 오차 학습, bottom-up)
// =============================================================================

module pst_2layer_cseq #(
    parameter [7:0] THRESHOLD = 8'd200,
    parameter [7:0] W_INIT    = 8'd128,
    parameter [7:0] ETA_LTP   = 8'd4,
    parameter [7:0] ETA_LTD   = 8'd3,
    parameter [7:0] WINDOW    = 8'd128,
    parameter [7:0] ETA_SLOT  = 8'd8,
    parameter [7:0] ETA_SEQ   = 8'd4
)(
    input  wire       clk, rst_n, cycle_start,
    input  wire [7:0] global_phase,
    input  wire [7:0] input_current,
    input  wire       l3_freeze,

    output wire [7:0] phase_L1,
    output wire       fired_L1,
    output wire [7:0] pred_L2,
    output wire [7:0] error_L2,
    output wire [7:0] weight_L2,

    output wire [7:0] pred_L3_next,
    output wire [7:0] error_L3,
    output wire [1:0] winner_L3,
    output wire [7:0] slot0_L3, slot1_L3, slot2_L3, slot3_L3
);

    // L1
    wire spk_L1;
    phase_neuron #(.THRESHOLD(THRESHOLD),.LEAK(8'd0)) L1 (
        .clk(clk),.rst_n(rst_n),
        .global_phase(global_phase),.cycle_start(cycle_start),
        .input_current(input_current),
        .spike_out(spk_L1),.phase_lock(phase_L1),.fired_this_cycle(fired_L1)
    );

    // L3: phase_L1을 직접 관측 (순환 의존성 제거)
    wire [7:0] cseq_pred, cseq_err;
    wire       cseq_err_valid;
    wire [1:0] cseq_winner;
    wire [7:0] s0,s1,s2,s3;

    competitive_seq_pred #(
        .N_SLOTS(4),.W_INIT(W_INIT),
        .ETA_SLOT(ETA_SLOT),.ETA_SEQ(ETA_SEQ)
    ) L3_cseq (
        .clk(clk),.rst_n(rst_n),.cycle_start(cycle_start),
        .actual_phase(phase_L1),   // ← v3 핵심: pred_L2가 아닌 phase_L1
        .fired(fired_L1),
        .pred_next(cseq_pred),
        .error_out(cseq_err),
        .error_valid(cseq_err_valid),
        .winner_out(cseq_winner),
        .slot0_out(s0),.slot1_out(s1),
        .slot2_out(s2),.slot3_out(s3)
    );

    // l3_freeze OR 학습 미완료면 top-down 비활성화
    wire [7:0] l3_to_l2 = l3_freeze ? 8'd0  : cseq_pred;
    wire       l3_valid  = l3_freeze ? 1'b0  : cseq_err_valid;
    wire [7:0] l3_boost  = l3_freeze ? 8'd0  : (cseq_err >> 2);

    // L2
    wire err_sign_L2, err_valid_L2;
    wire [7:0] eta_boost_unused;

    predictive_phase #(
        .W_INIT(W_INIT),.ETA_LTP(ETA_LTP),
        .ETA_LTD(ETA_LTD),.WINDOW(WINDOW)
    ) L2 (
        .clk(clk),.rst_n(rst_n),.cycle_start(cycle_start),
        .actual_phase(phase_L1),.fired_actual(fired_L1),
        .pred_phase_in(l3_to_l2),.pred_valid(l3_valid),
        .eta_boost_in(l3_boost),
        .error_mag(error_L2),.error_sign(err_sign_L2),
        .error_valid(err_valid_L2),
        .pred_phase_out(pred_L2),.weight(weight_L2),
        .eta_boost_out(eta_boost_unused)
    );

    assign pred_L3_next = cseq_pred;
    assign error_L3     = cseq_err;
    assign winner_L3    = cseq_winner;
    assign slot0_L3=s0; assign slot1_L3=s1;
    assign slot2_L3=s2; assign slot3_L3=s3;

endmodule
