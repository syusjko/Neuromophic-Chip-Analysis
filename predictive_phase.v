// =============================================================================
// Module  : predictive_phase (v4 - L3 error → L2 eta_boost)
// Project : Phase-based Spiking Transformer (PST)
//
// [v4 핵심: 진짜 계층적 학습]
//   eta_boost_in: 상위층(L3)이 보내는 오차 크기
//   → L3 oops가 클 때 L2 STDP 학습률 증폭
//   → "L3가 놀라면 L2도 더 빠르게 학습"
//   이게 Credit Assignment의 핵심
//
// [계층별 동작]
//   L3 (최상위, pred_valid=0):
//     eta_boost_in = 0 (외부 없음)
//     eta_boost_out = error_mag >> 2 (L2에게 전달)
//
//   L2 (중간층):
//     eta_boost_in = L3 error >> 2 (L3가 전달)
//     STDP ETA = 기본 + eta_boost_in
//     → L3 오차 클수록 빠른 학습
// =============================================================================

module predictive_phase #(
    parameter [7:0] W_INIT    = 8'd128,
    parameter [7:0] ETA_LTP   = 8'd4,
    parameter [7:0] ETA_LTD   = 8'd3,
    parameter [7:0] WINDOW    = 8'd128,
    parameter [7:0] PRED_GAIN = 8'd1
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       cycle_start,

    input  wire [7:0] actual_phase,
    input  wire       fired_actual,

    input  wire [7:0] pred_phase_in,   // 상위층 top-down 예측
    input  wire       pred_valid,      // top-down 유효 여부

    // [신규] 상위층 오차 부스트 (L3 → L2)
    input  wire [7:0] eta_boost_in,    // 상위층 오차 크기 (학습률 증폭)

    // [신규] top-down injection (seq2 force)
    input  wire [7:0] force_pred,      // L3가 직접 주입할 pred 값
    input  wire       force_valid,     // 1이면 my_pred = force_pred로 즉시 set

    output reg  [7:0] error_mag,
    output reg        error_sign,
    output reg        error_valid,
    output reg  [7:0] pred_phase_out,
    output wire [7:0] weight,

    // [신규] 이 층의 오차를 하위층에 전달
    output wire [7:0] eta_boost_out    // = error_mag >> 2
);

    reg [7:0] my_pred;

    // -------------------------------------------------------------------------
    // effective_pred: top-down 혼합
    // -------------------------------------------------------------------------
    wire [9:0] eff_wide = ({2'b0, my_pred} + {2'b0, my_pred} +
                           {2'b0, my_pred} + {2'b0, pred_phase_in});
    wire [7:0] effective_pred = pred_valid ? eff_wide[9:2] : my_pred;

    // -------------------------------------------------------------------------
    // 예측 오차
    // -------------------------------------------------------------------------
    wire [7:0] raw_err  = actual_phase - effective_pred;
    wire [7:0] inv_err  = 8'd255 - raw_err + 8'd1;
    wire [7:0] err_abs  = (raw_err <= inv_err) ? raw_err : inv_err;
    wire       act_fast = (raw_err[7] == 1'b1) && (raw_err != 8'd0);

    // -------------------------------------------------------------------------
    // eta_boost_out: 이 층의 오차 1/4 → 하위층 학습률 증폭
    // -------------------------------------------------------------------------
    assign eta_boost_out = err_abs >> 2;   // 최대 63 (err_abs/4)

    // -------------------------------------------------------------------------
    // STDP (eta_boost_in으로 학습률 변조)
    // -------------------------------------------------------------------------
    wire ltp_ev, ltd_ev;
    wire pred_err_valid = (err_abs > 8'd2);

    phase_stdp #(
        .W_INIT(W_INIT),
        .ETA_LTP(ETA_LTP),
        .ETA_LTD(ETA_LTD),
        .WINDOW(WINDOW)
    ) syn (
        .clk(clk), .rst_n(rst_n),
        .cycle_start(cycle_start),
        .phase_pre (act_fast ? actual_phase : effective_pred),
        .phase_post(act_fast ? effective_pred : actual_phase),
        .fired_pre (fired_actual && pred_err_valid),
        .fired_post(fired_actual && pred_err_valid),
        .eta_boost(eta_boost_in),    // 상위층 오차 → 학습률 증폭
        .weight(weight),
        .ltp_event(ltp_ev),
        .ltd_event(ltd_ev)
    );

    // -------------------------------------------------------------------------
    // 예측 업데이트: adapt_step에도 eta_boost 반영
    // L3 오차 클수록 pred도 더 빠르게 이동 (weight만 아니라 pred도)
    // -------------------------------------------------------------------------
    wire [7:0] adapt_base = (err_abs[7:2] > 8'd1) ? err_abs[7:2] : 8'd1;
    wire [8:0] adapt_wide = {1'b0, adapt_base} + {1'b0, eta_boost_in[7:2]};
    wire [7:0] adapt_step = (adapt_wide > 9'd255) ? 8'd255 : adapt_wide[7:0];
    reg  [8:0] pred_next;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            my_pred        <= 8'd128;
            pred_phase_out <= 8'd128;
            error_mag      <= 8'd0;
            error_sign     <= 1'b0;
            error_valid    <= 1'b0;
        end
        else if (cycle_start && fired_actual) begin
            error_mag   <= err_abs;
            error_sign  <= ~act_fast;
            error_valid <= pred_err_valid;

            // [Force Injection] L3가 전환 감지 → my_pred 직접 set
            if (force_valid) begin
                my_pred <= force_pred;
            end else if (pred_err_valid) begin
                if (act_fast) begin
                    if (my_pred >= adapt_step)
                        my_pred <= my_pred - adapt_step;
                    else
                        my_pred <= 8'd0;
                end else begin
                    pred_next = {1'b0, my_pred} + {1'b0, adapt_step};
                    my_pred <= (pred_next > 9'd255) ? 8'd255 : pred_next[7:0];
                end
            end else if (pred_valid) begin
                // dead zone + top-down: 미세 조정
                if (pred_phase_in > my_pred)
                    my_pred <= my_pred + 8'd1;
                else if (pred_phase_in < my_pred && my_pred > 8'd0)
                    my_pred <= my_pred - 8'd1;
            end

            pred_phase_out <= force_valid ? force_pred : my_pred;
        end
        else if (cycle_start) begin
            error_valid <= 1'b0;
        end
    end

endmodule
