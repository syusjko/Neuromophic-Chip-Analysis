// =============================================================================
// Module  : seq2_predictor (v3 - top-down injection)
//
// [근본 전환: Prediction → Injection]
//   기존 top-down: effective_pred에 혼합 (25% 영향) → 항상 방해
//   신규 top-down: 전환 감지 순간 force_pred로 직접 주입
//
// [동작]
//   평상시: force_valid=0 (L2가 자율 학습)
//   winner 전환 감지 순간: force_valid=1, force_pred=이겼을 슬롯 값
//     L2.my_pred = force_pred로 직접 set (한 사이클만)
//     다음 사이클부터 L2가 fine-tuning
//
// [효과]
//   B: pred=3에서 40까지 8~12사이클 소요
//   A: 전환 순간 pred=42(≈40), 즉시 fine-tuning → 1~2사이클
//
// [뇌 대응]
//   이건 "top-down priming" 또는 "cue-triggered activation"
//   CA3 → CA1에서 패턴 완성(pattern completion) 원리
//   "이미 알고 있는 패턴이니까 즉시 복원"
// =============================================================================

module seq2_predictor #(
    parameter [7:0] SLOT_A_INIT = 8'd5,
    parameter [7:0] SLOT_B_INIT = 8'd50,
    parameter [7:0] ETA         = 8'd8
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       cycle_start,
    input  wire [7:0] actual_phase,
    input  wire       fired,

    // top-down injection
    output reg  [7:0] force_pred,   // 즉시 주입할 예측값
    output reg        force_valid,  // 1이면 L2.my_pred를 force_pred로 set

    // 디버그
    output reg  [7:0] slot_A,
    output reg  [7:0] slot_B,
    output reg        last_winner,
    output reg  [7:0] error_out
);

    // WTA
    wire [7:0] rawA = actual_phase - slot_A;
    wire [7:0] invA = 8'd255 - rawA + 8'd1;
    wire [7:0] dA   = (rawA <= invA) ? rawA : invA;

    wire [7:0] rawB = actual_phase - slot_B;
    wire [7:0] invB = 8'd255 - rawB + 8'd1;
    wire [7:0] dB   = (rawB <= invB) ? rawB : invB;

    wire is_A = (dA <= dB);
    wire winner_changed = fired && (last_winner != (is_A ? 1'b0 : 1'b1));

    wire [7:0] winner_dist = is_A ? dA : dB;
    wire [7:0] curr_slot   = is_A ? slot_A : slot_B;
    wire [7:0] raw_dir     = actual_phase - curr_slot;
    wire       dn_dir      = (raw_dir[7] == 1'b1) && (raw_dir != 8'd0);
    wire       up_dir      = (raw_dir[7] == 1'b0) && (raw_dir != 8'd0);
    wire [7:0] step        = (winner_dist[7:2] > 8'd1) ? winner_dist[7:2] : 8'd1;

    reg [8:0]  slot_up;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            slot_A      <= SLOT_A_INIT;
            slot_B      <= SLOT_B_INIT;
            last_winner <= 1'b0;
            force_pred  <= SLOT_B_INIT;
            force_valid <= 1'b0;
            error_out   <= 8'd0;
        end
        else if (cycle_start && fired) begin

            // ── 슬롯 업데이트 ─────────────────────────────────────────
            if (winner_dist > 8'd2) begin
                if (is_A) begin
                    if (dn_dir)
                        slot_A <= (slot_A >= step) ? slot_A - step : 8'd0;
                    else if (up_dir) begin
                        slot_up = {1'b0, slot_A} + {1'b0, step};
                        slot_A <= (slot_up > 9'd255) ? 8'd255 : slot_up[7:0];
                    end
                end else begin
                    if (dn_dir)
                        slot_B <= (slot_B >= step) ? slot_B - step : 8'd0;
                    else if (up_dir) begin
                        slot_up = {1'b0, slot_B} + {1'b0, step};
                        slot_B <= (slot_up > 9'd255) ? 8'd255 : slot_up[7:0];
                    end
                end
            end

            // ── Top-down Injection ────────────────────────────────────
            // 전환 감지 순간: L2에 "이 패턴의 정확한 값" 직접 주입
            if (winner_changed) begin
                // is_A: 이번에 A가 이김 = ph≈sA가 도착
                // → L2 pred를 sA로 즉시 set
                force_pred  <= is_A ? slot_A : slot_B;
                force_valid <= 1'b1;
            end else begin
                force_valid <= 1'b0;
            end

            error_out   <= winner_dist;
            last_winner <= is_A ? 1'b0 : 1'b1;
        end
        else if (cycle_start) begin
            force_valid <= 1'b0;
        end
    end

endmodule
