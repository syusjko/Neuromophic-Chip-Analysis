// =============================================================================
// Module  : pst_2layer_theta (v2)
// =============================================================================

module pst_2layer_theta #(
    parameter [7:0] THRESHOLD = 8'd200,
    parameter [7:0] W_INIT    = 8'd128,
    parameter [7:0] ETA_LTP   = 8'd4,
    parameter [7:0] ETA_LTD   = 8'd3,
    parameter [7:0] WINDOW    = 8'd128,
    parameter [7:0] SEQ_ETA   = 8'd8
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       cycle_start,
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
    output wire [7:0] eta_boost_L2,

    // 디버그
    output wire [2:0] theta_dbg,
    output wire [7:0] slot0_dbg,
    output wire [7:0] slot4_dbg
);

    wire spk_L1;
    phase_neuron #(.THRESHOLD(THRESHOLD), .LEAK(8'd0)) L1 (
        .clk(clk), .rst_n(rst_n),
        .global_phase(global_phase), .cycle_start(cycle_start),
        .input_current(input_current),
        .spike_out(spk_L1), .phase_lock(phase_L1), .fired_this_cycle(fired_L1)
    );

    wire [7:0] theta_pred_next;
    wire [7:0] theta_err;
    wire       theta_err_valid;

    wire [7:0] l3_pred_to_l2 = l3_freeze ? 8'd0   : theta_pred_next;
    wire       l3_valid       = l3_freeze ? 1'b0   : theta_err_valid;
    wire [7:0] l3_boost       = l3_freeze ? 8'd0   : (theta_err >> 2);

    theta_seq_predictor #(.W_INIT(W_INIT), .ETA(SEQ_ETA)) L3_theta (
        .clk(clk), .rst_n(rst_n),
        .cycle_start(cycle_start),
        .global_phase(global_phase),
        .actual_phase(pred_L2),
        .fired(fired_L1),
        .pred_next(theta_pred_next),
        .error_out(theta_err),
        .error_valid(theta_err_valid),
        .theta_out(theta_dbg),
        .slot0_out(slot0_dbg),
        .slot4_out(slot4_dbg)
    );

    wire err_sign_L2, err_valid_L2;
    wire [7:0] eta_boost_unused;

    predictive_phase #(
        .W_INIT(W_INIT), .ETA_LTP(ETA_LTP), .ETA_LTD(ETA_LTD), .WINDOW(WINDOW)
    ) L2 (
        .clk(clk), .rst_n(rst_n), .cycle_start(cycle_start),
        .actual_phase(phase_L1), .fired_actual(fired_L1),
        .pred_phase_in(l3_pred_to_l2),
        .pred_valid(l3_valid),
        .eta_boost_in(l3_boost),
        .error_mag(error_L2), .error_sign(err_sign_L2),
        .error_valid(err_valid_L2),
        .pred_phase_out(pred_L2),
        .weight(weight_L2),
        .eta_boost_out(eta_boost_unused)
    );

    assign pred_L3_next = theta_pred_next;
    assign error_L3     = theta_err;
    assign eta_boost_L2 = l3_boost;

endmodule
