// =============================================================================
// Module  : competitive_seq_pred
// Project : Phase-based Spiking Transformer (PST)
//
// [뇌의 어느 구조에서 왔는가]
//   Cortical Columns + WTA (Lateral Inhibition) + STDP Sequence
//
//   1. Cortical Column WTA (Self-Organizing Map 원리)
//      - N개 슬롯이 각각 다른 패턴을 전문화
//      - 입력이 올 때 가장 가까운 슬롯이 "승자"
//      - 승자만 업데이트 (패자는 억제)
//      - 결과: slot[0]≈40, slot[1]≈1 자연 분리
//
//   2. STDP Sequence Memory
//      - 승자 슬롯 간 STDP 연결
//      - slot[0] 승리 → slot[1] 승리 → ...
//      - w_seq[i][j]: "슬롯 i 다음에 슬롯 j" 확률
//      - 결과: "40 다음에 1이 온다" 학습
//
//   3. Predictive Activation
//      - 현재 승자 슬롯에서 다음 슬롯 예측
//      - pred_next = slot[argmax(w_seq[winner])]
//      - "지금 40이면 다음은 1일 것"
//
// [왜 theta_seq_predictor가 실패했는가]
//   theta 슬롯: 외부 카운터로 할당 → 입력이 어떤 theta에 오는지 무작위
//   WTA 슬롯: 입력 값으로 할당 → 항상 같은 슬롯이 같은 패턴 처리
//
// [포트]
//   actual_phase: 현재 관측값
//   pred_next:    다음으로 올 패턴 예측
//   winner:       현재 승자 슬롯 번호 (디버그)
// =============================================================================

module competitive_seq_pred #(
    parameter N_SLOTS = 4,          // 슬롯 수 (2의 거듭제곱)
    parameter [7:0] W_INIT = 8'd128,
    parameter [7:0] ETA_SLOT = 8'd8,  // 슬롯 학습률 (빠르게)
    parameter [7:0] ETA_SEQ  = 8'd4   // 시퀀스 STDP 학습률
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       cycle_start,
    input  wire [7:0] actual_phase,
    input  wire       fired,

    output reg  [7:0] pred_next,      // 다음 패턴 예측
    output reg  [7:0] error_out,      // 현재 슬롯 오차
    output reg        error_valid,
    output reg  [1:0] winner_out,     // 현재 승자 슬롯 (디버그)
    output wire [7:0] slot0_out,
    output wire [7:0] slot1_out,
    output wire [7:0] slot2_out,
    output wire [7:0] slot3_out
);

    // -------------------------------------------------------------------------
    // Slot 메모리 (N_SLOTS=4)
    // -------------------------------------------------------------------------
    reg [7:0] slot [0:3];
    assign slot0_out = slot[0];
    assign slot1_out = slot[1];
    assign slot2_out = slot[2];
    assign slot3_out = slot[3];

    // -------------------------------------------------------------------------
    // 시퀀스 가중치: w_seq[i][j] = "슬롯 i 다음에 슬롯 j" 강도
    // 4×4 = 16개 가중치
    // -------------------------------------------------------------------------
    reg [7:0] w_seq [0:3][0:3];

    integer i, j;

    // -------------------------------------------------------------------------
    // WTA: 현재 입력에 가장 가까운 슬롯 찾기 (조합 논리)
    // -------------------------------------------------------------------------
    wire [7:0] d0, d1, d2, d3;  // 각 슬롯과 입력의 거리

    // circular distance
    function [7:0] circ_dist;
        input [7:0] a, b;
        reg [7:0] raw, inv;
        begin
            raw = a - b;
            inv = 8'd255 - raw + 8'd1;
            circ_dist = (raw <= inv) ? raw : inv;
        end
    endfunction

    assign d0 = circ_dist(actual_phase, slot[0]);
    assign d1 = circ_dist(actual_phase, slot[1]);
    assign d2 = circ_dist(actual_phase, slot[2]);
    assign d3 = circ_dist(actual_phase, slot[3]);

    // 승자 선택 (가장 작은 거리)
    reg [1:0] winner;
    always @(*) begin
        winner = 2'd0;
        if (d1 < d0) winner = 2'd1;
        if (d2 < d0 && d2 < d1) winner = 2'd2;
        if (d3 < d0 && d3 < d1 && d3 < d2) winner = 2'd3;
    end

    // -------------------------------------------------------------------------
    // 이전 승자 저장 (시퀀스 학습용)
    // -------------------------------------------------------------------------
    reg [1:0] prev_winner;
    reg       prev_valid;

    // -------------------------------------------------------------------------
    // 예측: 현재 승자 슬롯에서 시퀀스 가중치가 가장 큰 슬롯
    // -------------------------------------------------------------------------
    wire [7:0] w0 = w_seq[winner][0];
    wire [7:0] w1 = w_seq[winner][1];
    wire [7:0] w2 = w_seq[winner][2];
    wire [7:0] w3 = w_seq[winner][3];

    reg  [1:0] next_winner_pred;
    always @(*) begin
        next_winner_pred = 2'd0;
        if (w1 > w0) next_winner_pred = 2'd1;
        if (w2 > w0 && w2 > w1) next_winner_pred = 2'd2;
        if (w3 > w0 && w3 > w1 && w3 > w2) next_winner_pred = 2'd3;
    end

    // -------------------------------------------------------------------------
    // 학습 + 예측 출력
    // -------------------------------------------------------------------------
    reg [8:0] slot_up;
    reg [8:0] w_up;
    wire [7:0] winner_dist = (winner==2'd0)?d0:(winner==2'd1)?d1:
                             (winner==2'd2)?d2:d3;
    wire [7:0] step = (winner_dist[7:2] > 8'd1) ? winner_dist[7:2] : 8'd1;
    wire       act_dn = (actual_phase < slot[winner]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 슬롯 분산 초기화 (0, 85, 170, 255) = 균등 분포
            slot[0] <= 8'd0;
            slot[1] <= 8'd85;
            slot[2] <= 8'd170;
            slot[3] <= 8'd255;
            for (j=0; j<4; j=j+1) begin
                w_seq[0][j] <= (j==1) ? 8'd2 : 8'd1;  // 0 다음에는 1이 올 것으로 초기화
                w_seq[1][j] <= (j==2) ? 8'd2 : 8'd1;
                w_seq[2][j] <= (j==3) ? 8'd2 : 8'd1;
                w_seq[3][j] <= (j==0) ? 8'd2 : 8'd1;  // 자기 자신 포함 (non-zero)
            end
            // 자기→자기는 0으로
            w_seq[0][0] <= 8'd0;
            w_seq[1][1] <= 8'd0;
            w_seq[2][2] <= 8'd0;
            w_seq[3][3] <= 8'd0;
            pred_next   <= W_INIT;
            error_out   <= 8'd0;
            error_valid <= 1'b0;
            winner_out  <= 2'd0;
            prev_winner <= 2'd0;
            prev_valid  <= 1'b0;
        end
        else if (cycle_start && fired) begin

            // ── 1. WTA 슬롯 업데이트 ──────────────────────────────────────
            // 승자 슬롯만 actual_phase 방향으로 이동
            if (winner_dist > 8'd2) begin
                if (act_dn) begin
                    slot[winner] <= (slot[winner] >= step) ?
                                    slot[winner] - step : 8'd0;
                end else begin
                    slot_up = {1'b0, slot[winner]} + {1'b0, step};
                    slot[winner] <= (slot_up > 9'd255) ? 8'd255 : slot_up[7:0];
                end
            end

            // ── 2. 시퀀스 STDP ────────────────────────────────────────────
            // prev_winner → winner 연결 강화 (LTP)
            // winner → prev_winner 연결 약화 (LTD, 방향성)
            if (prev_valid && prev_winner != winner) begin
                // LTP: prev→curr
                w_up = {1'b0, w_seq[prev_winner][winner]} + {1'b0, ETA_SEQ};
                w_seq[prev_winner][winner] <= (w_up > 9'd255) ? 8'd255 : w_up[7:0];

                // LTD: curr→prev (반대 방향은 약화)
                if (w_seq[winner][prev_winner] > ETA_SEQ)
                    w_seq[winner][prev_winner] <= w_seq[winner][prev_winner] - ETA_SEQ;
                else
                    w_seq[winner][prev_winner] <= 8'd0;
            end

            // ── 3. 예측 출력 ──────────────────────────────────────────────
            pred_next   <= slot[next_winner_pred];
            error_out   <= winner_dist;
            error_valid <= (winner_dist > 8'd2);
            winner_out  <= winner;

            // 이전 승자 저장
            prev_winner <= winner;
            prev_valid  <= 1'b1;
        end
        else if (cycle_start) begin
            // 발화 없어도 예측은 출력
            pred_next   <= slot[next_winner_pred];
            error_valid <= 1'b0;
        end
    end

endmodule
