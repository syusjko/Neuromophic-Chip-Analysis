// =============================================================================
// Module  : pst_brain_v1
// Project : Phase-based Spiking Transformer - Closed Loop Brain v1
//
// [폐루프 구조 - "보면서 학습하는 최소 뇌"]
//
//   입력 전류 → phase_neuron (위상 코딩)
//        ↓
//   coincidence_detector (어텐션: 어느 쌍이 가장 관련있나)
//        ↓
//   winner 선택 (가장 유사한 쌍)
//        ↓
//   winner 쌍만 STDP 업데이트 (sparse learning)
//   - winner_rel이 낮으면 (놀라운 상황) 학습률 높임
//   - winner_rel이 높으면 (알던 패턴) 학습률 낮춤
//        ↓
//   seq2_predictor: winner 쌍의 phase 패턴 학습
//        ↓
//   패턴 전환 감지 → force_pred 주입 → 다음 사이클 빠른 수렴
//
// [뇌 대응]
//   phase_neuron:          감각 피질 (입력 인코딩)
//   coincidence_detector:  연합 영역 (관련성 계산)
//   winner selection:      주의 (attention spotlight)
//   STDP (sparse):         시냅스 가소성 (경험 → 연결 강화)
//   seq2_predictor:        해마 (패턴 완성 + 시퀀스 기억)
//   force injection:       Top-down priming (CA3→CA1)
//
// [v1 한계 / 다음 버전에서 추가할 것]
//   - 작업기억: 없음 (v2에서 추가)
//   - 보상 신호: 없음 (v2에서 추가)
//   - 패턴: 2개 교번만 (v2에서 N개로 확장)
// =============================================================================

module pst_brain_v1 #(
    parameter [7:0] THRESHOLD  = 8'd200,
    parameter [7:0] PHASE_TOL  = 8'd15,
    parameter [7:0] ETA_LTP    = 8'd4,
    parameter [7:0] ETA_LTD    = 8'd3,

    // seq2 슬롯 초기값 (두 패턴 근처로 설정)
    parameter [7:0] SLOT_A_INIT = 8'd0,    // AB 패턴 (winner_idx=0)
    parameter [7:0] SLOT_B_INIT = 8'd213   // CD 패턴 (winner_idx=213)
)(
    input  wire        clk,
    input  wire        rst_n,

    // 4채널 입력 전류
    input  wire [7:0]  cur0, cur1, cur2, cur3,

    // === 모니터링 출력 ===
    output wire [7:0]  phase0, phase1, phase2, phase3,

    // Attention 결과
    output wire [2:0]  winner,        // 0=AB 1=AC 2=AD 3=BC 4=BD 5=CD
    output wire [7:0]  winner_rel,    // winner 관련성

    // STDP 학습 결과
    output wire [7:0]  w_winner,      // winner 쌍 시냅스 가중치

    // Seq2 상태
    output wire [7:0]  seq_slot_A,
    output wire [7:0]  seq_slot_B,
    output wire        seq_force_valid,
    output wire [7:0]  seq_force_pred,

    // predictive_phase 출력
    output wire [7:0]  pred_out,      // 현재 예측값
    output wire [7:0]  pred_err       // 현재 오차
);

    // =========================================================================
    // 내부 신호
    // =========================================================================
    wire [7:0] gphase;
    wire       cyc_start;

    gamma_oscillator #(.CYCLE_LEN(9'd256)) osc (
        .clk(clk), .rst_n(rst_n),
        .phase_out(gphase), .cycle_start(cyc_start)
    );

    // =========================================================================
    // Layer 1: Phase Neurons (4채널)
    // =========================================================================
    wire fired0, fired1, fired2, fired3;

    phase_neuron #(.THRESHOLD(THRESHOLD),.LEAK(8'd0)) n0 (
        .clk(clk),.rst_n(rst_n),.global_phase(gphase),.cycle_start(cyc_start),
        .input_current(cur0),.spike_out(),.phase_lock(phase0),.fired_this_cycle(fired0));

    phase_neuron #(.THRESHOLD(THRESHOLD),.LEAK(8'd0)) n1 (
        .clk(clk),.rst_n(rst_n),.global_phase(gphase),.cycle_start(cyc_start),
        .input_current(cur1),.spike_out(),.phase_lock(phase1),.fired_this_cycle(fired1));

    phase_neuron #(.THRESHOLD(THRESHOLD),.LEAK(8'd0)) n2 (
        .clk(clk),.rst_n(rst_n),.global_phase(gphase),.cycle_start(cyc_start),
        .input_current(cur2),.spike_out(),.phase_lock(phase2),.fired_this_cycle(fired2));

    phase_neuron #(.THRESHOLD(THRESHOLD),.LEAK(8'd0)) n3 (
        .clk(clk),.rst_n(rst_n),.global_phase(gphase),.cycle_start(cyc_start),
        .input_current(cur3),.spike_out(),.phase_lock(phase3),.fired_this_cycle(fired3));

    // =========================================================================
    // Layer 2: Coincidence Detectors (6쌍 = 4C2)
    // =========================================================================
    wire [7:0] rel_ab, rel_ac, rel_ad, rel_bc, rel_bd, rel_cd;
    wire       coin_ab, coin_ac, coin_ad, coin_bc, coin_bd, coin_cd;

    coincidence_detector #(.PHASE_TOL(PHASE_TOL)) cd_ab (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),
        .fired_a(fired0),.fired_b(fired1),.phase_a(phase0),.phase_b(phase1),
        .relevance(rel_ab),.coincident(coin_ab));

    coincidence_detector #(.PHASE_TOL(PHASE_TOL)) cd_ac (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),
        .fired_a(fired0),.fired_b(fired2),.phase_a(phase0),.phase_b(phase2),
        .relevance(rel_ac),.coincident(coin_ac));

    coincidence_detector #(.PHASE_TOL(PHASE_TOL)) cd_ad (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),
        .fired_a(fired0),.fired_b(fired3),.phase_a(phase0),.phase_b(phase3),
        .relevance(rel_ad),.coincident(coin_ad));

    coincidence_detector #(.PHASE_TOL(PHASE_TOL)) cd_bc (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),
        .fired_a(fired1),.fired_b(fired2),.phase_a(phase1),.phase_b(phase2),
        .relevance(rel_bc),.coincident(coin_bc));

    coincidence_detector #(.PHASE_TOL(PHASE_TOL)) cd_bd (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),
        .fired_a(fired1),.fired_b(fired3),.phase_a(phase1),.phase_b(phase3),
        .relevance(rel_bd),.coincident(coin_bd));

    coincidence_detector #(.PHASE_TOL(PHASE_TOL)) cd_cd (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),
        .fired_a(fired2),.fired_b(fired3),.phase_a(phase2),.phase_b(phase3),
        .relevance(rel_cd),.coincident(coin_cd));

    // =========================================================================
    // Layer 3: Winner Selection (Argmax)
    // =========================================================================
    reg [2:0] w_comb;
    reg [7:0] wr_comb;

    always @(*) begin
        w_comb=3'd0; wr_comb=rel_ab;
        if (rel_ac>wr_comb) begin w_comb=3'd1; wr_comb=rel_ac; end
        if (rel_ad>wr_comb) begin w_comb=3'd2; wr_comb=rel_ad; end
        if (rel_bc>wr_comb) begin w_comb=3'd3; wr_comb=rel_bc; end
        if (rel_bd>wr_comb) begin w_comb=3'd4; wr_comb=rel_bd; end
        if (rel_cd>wr_comb) begin w_comb=3'd5; wr_comb=rel_cd; end
    end

    reg [2:0] winner_r;
    reg [7:0] winner_rel_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin winner_r<=0; winner_rel_r<=0; end
        else if (cyc_start) begin
            winner_r     <= w_comb;
            winner_rel_r <= wr_comb;
        end
    end

    assign winner     = winner_r;
    assign winner_rel = winner_rel_r;

    // =========================================================================
    // Layer 4: Sparse STDP (winner 쌍만 학습)
    //
    // winner=0(AB): phase0-phase1 쌍의 STDP 업데이트
    // 나머지 쌍: 동결
    //
    // "주의가 향한 곳만 학습" = Hebbian + Attention Gate
    // =========================================================================

    // winner 쌍의 두 뉴런 phase 선택
    reg [7:0] win_phase_a, win_phase_b;
    reg       win_fired_a, win_fired_b;

    always @(*) begin
        case (winner_r)
            3'd0: begin win_phase_a=phase0; win_phase_b=phase1;
                        win_fired_a=fired0; win_fired_b=fired1; end
            3'd1: begin win_phase_a=phase0; win_phase_b=phase2;
                        win_fired_a=fired0; win_fired_b=fired2; end
            3'd2: begin win_phase_a=phase0; win_phase_b=phase3;
                        win_fired_a=fired0; win_fired_b=fired3; end
            3'd3: begin win_phase_a=phase1; win_phase_b=phase2;
                        win_fired_a=fired1; win_fired_b=fired2; end
            3'd4: begin win_phase_a=phase1; win_phase_b=phase3;
                        win_fired_a=fired1; win_fired_b=fired3; end
            3'd5: begin win_phase_a=phase2; win_phase_b=phase3;
                        win_fired_a=fired2; win_fired_b=fired3; end
            default: begin win_phase_a=8'd0; win_phase_b=8'd0;
                           win_fired_a=1'b0; win_fired_b=1'b0; end
        endcase
    end

    // winner_index → 8비트 균등 공간 매핑
    // AB=0, AC=43, AD=85, BC=128, BD=170, CD=213
    // 이걸 seq2에 넣으면 6가지 attention 패턴이 위상 공간에 분리됨
    reg [7:0] win_idx_mapped;
    always @(*) begin
        case (winner_r)
            3'd0: win_idx_mapped = 8'd0;    // AB
            3'd1: win_idx_mapped = 8'd43;   // AC
            3'd2: win_idx_mapped = 8'd85;   // AD
            3'd3: win_idx_mapped = 8'd128;  // BC
            3'd4: win_idx_mapped = 8'd170;  // BD
            3'd5: win_idx_mapped = 8'd213;  // CD
            default: win_idx_mapped = 8'd0;
        endcase
    end

    // win_fired: 두 뉴런 중 하나라도 (이번 사이클 winner 쌍이 활성)
    wire win_fired = win_fired_a | win_fired_b;

    // STDP: winner 쌍 시냅스 가중치 학습
    wire [7:0] stdp_w_out;
    wire       stdp_ltp, stdp_ltd;

    phase_stdp #(
        .W_INIT(8'd128),
        .ETA_LTP(ETA_LTP),
        .ETA_LTD(ETA_LTD),
        .WINDOW(8'd128)
    ) stdp_winner (
        .clk(clk), .rst_n(rst_n), .cycle_start(cyc_start),
        .phase_pre(win_phase_a), .fired_pre(win_fired_a),
        .phase_post(win_phase_b), .fired_post(win_fired_b),
        .eta_boost(8'd0),
        .weight(stdp_w_out),
        .ltp_event(stdp_ltp), .ltd_event(stdp_ltd)
    );

    assign w_winner = stdp_w_out;

    // =========================================================================
    // Layer 5: seq2_predictor (winner 위상 패턴 학습 + injection)
    //
    // 입력: winner 쌍의 평균 위상
    // 학습: 어느 패턴(A or B)인지 WTA로 분리
    // 출력: 패턴 전환 시 force injection
    // =========================================================================
    wire [7:0] force_pred_w, seq_err_w;
    wire       force_valid_w, seq_lw_w;

    seq2_predictor #(
        .SLOT_A_INIT(SLOT_A_INIT),
        .SLOT_B_INIT(SLOT_B_INIT),
        .ETA(8'd8)
    ) seq2 (
        .clk(clk), .rst_n(rst_n), .cycle_start(cyc_start),
        .actual_phase(win_idx_mapped),
        .fired(win_fired),
        .force_pred(force_pred_w),
        .force_valid(force_valid_w),
        .slot_A(seq_slot_A),
        .slot_B(seq_slot_B),
        .last_winner(seq_lw_w),
        .error_out(seq_err_w)
    );

    assign seq_force_valid = force_valid_w;
    assign seq_force_pred  = force_pred_w;

    // =========================================================================
    // Layer 6: predictive_phase (winner 쌍의 위상 예측 + 계층 가속)
    //
    // - winner 쌍 위상을 예측
    // - seq2의 force injection으로 패턴 전환 시 즉시 수렴
    // =========================================================================
    wire       pred_err_sign, pred_err_valid;
    wire [7:0] pred_boost_out;

    predictive_phase #(
        .W_INIT(8'd128),
        .ETA_LTP(ETA_LTP),
        .ETA_LTD(ETA_LTD),
        .WINDOW(8'd128)
    ) pred (
        .clk(clk), .rst_n(rst_n), .cycle_start(cyc_start),
        .actual_phase(win_idx_mapped),
        .fired_actual(win_fired),
        .pred_phase_in(8'd0),
        .pred_valid(1'b0),
        .eta_boost_in(8'd0),
        .force_pred(force_pred_w),
        .force_valid(force_valid_w),
        .error_mag(pred_err),
        .error_sign(pred_err_sign),
        .error_valid(pred_err_valid),
        .pred_phase_out(pred_out),
        .weight(),
        .eta_boost_out(pred_boost_out)
    );

endmodule
