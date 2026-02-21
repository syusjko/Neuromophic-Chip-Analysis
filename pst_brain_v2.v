// =============================================================================
// Module  : pst_brain_v2
// Project : Phase-based Spiking Transformer - Brain v2.3 / V3.0 R-STDP
//
// [V3.0 추가]
// - internal_reward: pred_err=0 연속 N사이클 → 자동 도파민 생성
// - R-STDP: reward=1이면 LTP × 2 (성공 경험 빠른 각인)
// - reward_out 포트: 외부 tb에서 확인 가능
//
// [뇌 대응]
//   internal_reward  ← 도파민 (예측 성공 시 보상)
//   R-STDP           ← 강화학습형 시냅스 가소성
//   pred_err=0       ← VTA 예측 오차 신호
// =============================================================================

module pst_brain_v2 #(
    parameter [7:0] THRESHOLD    = 8'd200,
    parameter [7:0] PHASE_TOL    = 8'd15,
    parameter [7:0] ETA_LTP      = 8'd4,
    parameter [7:0] ETA_LTD      = 8'd2,
    parameter [2:0] W_SHIFT      = 3'd2,
    parameter [7:0] DECAY_PERIOD = 8'd2,
    parameter [7:0] ERR_WIN      = 8'd3,   // 연속 N사이클 err<THR → reward
    parameter [7:0] ERR_THR      = 8'd5,   // 예측 오차 허용치 (8비트 기준 5=해없음)

    parameter [7:0] SLOT_A_INIT  = 8'd0,
    parameter [7:0] SLOT_B_INIT  = 8'd213
)(
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  cur0, cur1, cur2, cur3,

    // 위상 출력
    output wire [7:0]  phase0, phase1, phase2, phase3,

    // Attention
    output wire [2:0]  winner,
    output wire [7:0]  winner_score,
    output wire [7:0]  winner_rel,

    // 6쌍 STDP weight
    output wire [7:0]  w_ab, w_ac, w_ad, w_bc, w_bd, w_cd,

    // Seq2
    output wire [7:0]  seq_slot_A, seq_slot_B,
    output wire        seq_force_valid,
    output wire [7:0]  seq_force_pred,

    // Predictive
    output wire [7:0]  pred_out,
    output wire [7:0]  pred_err,

    // V3.0: 내적 도파민 신호 출력
    output wire        reward_out,  // 1: 보상 중

    // V3.1: Theta oscillator (에피소드 경계)
    output wire [2:0]  gamma_cnt,   // 에피소드 내 gamma 위치 (0~7)
    output wire        theta_tick,  // 에피소드 경계 (8γ마다 펄스)
    output wire        episode_last,// gamma_cnt==7: 에피소드 마지막

    // V3.2: 에피소드 기억
    output wire [2:0]  ep_winner,
    output wire [3:0]  ep_strength,
    output wire        ep_valid,

    // V3.3: 메타인지 (자신의 인지 상태 모니터링)
    output wire        exploit_mode,    // 1: 확신(안정) → 빠른 학습
    output wire        explore_mode,    // 1: 탐색(불안정) → 선입견 제거
    output wire [1:0]  confidence_level // 0:초기 1:탐색 2:전환중 3:확신
);

    // =========================================================================
    // L0: Gamma + Theta Oscillators
    // =========================================================================
    wire [7:0] gphase;
    wire       cyc_start;

    gamma_oscillator #(.CYCLE_LEN(9'd256)) osc (
        .clk(clk), .rst_n(rst_n),
        .phase_out(gphase), .cycle_start(cyc_start)
    );

    // V3.1: Theta (8 gamma = 1 에피소드)
    theta_oscillator #(.GAMMA_PER_THETA(3'd7)) theta (
        .clk(clk), .rst_n(rst_n),
        .gamma_tick(cyc_start),
        .gamma_cnt(gamma_cnt),
        .theta_tick(theta_tick),
        .episode_last(episode_last)
    );

    // V3.2: Episode Memory
    episode_memory ep_mem (
        .clk(clk), .rst_n(rst_n),
        .gamma_tick(cyc_start),
        .theta_tick(theta_tick),
        .current_winner(winner_w),
        .episode_winner(ep_winner),
        .episode_strength(ep_strength),
        .ep_valid(ep_valid)
    );

    // V3.3: Metacognition
    metacognition #(.EXPLOIT_THR(4'd6), .EXPLORE_THR(4'd5), .CONF_EXP_THR(2'd2)) meta (
        .clk(clk), .rst_n(rst_n),
        .theta_tick(theta_tick),
        .ep_strength(ep_strength),
        .ep_valid(ep_valid),
        .exploit_mode(exploit_mode),
        .explore_mode(explore_mode),
        .confidence_level(confidence_level)
    );

    // =========================================================================
    // L1: Phase Neurons
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
    // L2: Coincidence Detectors → rel[6]
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
    // L3: 6쌍 STDP weight (각 독립)
    // =========================================================================
    wire [7:0] stdp_ab, stdp_ac, stdp_ad, stdp_bc, stdp_bd, stdp_cd;

    // winner 선택용 내부 신호 (아래 argmax에서 결정)
    wire [2:0] winner_w;

    // STDP enable: winner 쌍만 업데이트
    // v2: 각 STDP 인스턴스에 "나 winner야?" enable 신호 전달
    wire en_ab = (winner_w == 3'd0);
    wire en_ac = (winner_w == 3'd1);
    wire en_ad = (winner_w == 3'd2);
    wire en_bc = (winner_w == 3'd3);
    wire en_bd = (winner_w == 3'd4);
    wire en_cd = (winner_w == 3'd5);

    // STDP 인스턴스 (V3.0: reward 포트 추가)
    stdp_gated #(.W_INIT(8'd128),.ETA_LTP(ETA_LTP),.ETA_LTD(ETA_LTD),.DECAY_PERIOD(DECAY_PERIOD)) s_ab (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.enable(en_ab),.reward(internal_reward),
        .phase_pre(phase0),.fired_pre(fired0),
        .phase_post(phase1),.fired_post(fired1),
        .weight(stdp_ab));
    stdp_gated #(.W_INIT(8'd128),.ETA_LTP(ETA_LTP),.ETA_LTD(ETA_LTD),.DECAY_PERIOD(DECAY_PERIOD)) s_ac (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.enable(en_ac),.reward(internal_reward),
        .phase_pre(phase0),.fired_pre(fired0),
        .phase_post(phase2),.fired_post(fired2),
        .weight(stdp_ac));
    stdp_gated #(.W_INIT(8'd128),.ETA_LTP(ETA_LTP),.ETA_LTD(ETA_LTD),.DECAY_PERIOD(DECAY_PERIOD)) s_ad (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.enable(en_ad),.reward(internal_reward),
        .phase_pre(phase0),.fired_pre(fired0),
        .phase_post(phase3),.fired_post(fired3),
        .weight(stdp_ad));
    stdp_gated #(.W_INIT(8'd128),.ETA_LTP(ETA_LTP),.ETA_LTD(ETA_LTD),.DECAY_PERIOD(DECAY_PERIOD)) s_bc (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.enable(en_bc),.reward(internal_reward),
        .phase_pre(phase1),.fired_pre(fired1),
        .phase_post(phase2),.fired_post(fired2),
        .weight(stdp_bc));
    stdp_gated #(.W_INIT(8'd128),.ETA_LTP(ETA_LTP),.ETA_LTD(ETA_LTD),.DECAY_PERIOD(DECAY_PERIOD)) s_bd (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.enable(en_bd),.reward(internal_reward),
        .phase_pre(phase1),.fired_pre(fired1),
        .phase_post(phase3),.fired_post(fired3),
        .weight(stdp_bd));
    stdp_gated #(.W_INIT(8'd128),.ETA_LTP(ETA_LTP),.ETA_LTD(ETA_LTD),.DECAY_PERIOD(DECAY_PERIOD)) s_cd (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.enable(en_cd),.reward(internal_reward),
        .phase_pre(phase2),.fired_pre(fired2),
        .phase_post(phase3),.fired_post(fired3),
        .weight(stdp_cd));

    assign w_ab = stdp_ab; assign w_ac = stdp_ac; assign w_ad = stdp_ad;
    assign w_bc = stdp_bc; assign w_bd = stdp_bd; assign w_cd = stdp_cd;

    // =========================================================================
    // L4: Score = rel + (w >> W_SHIFT) → Argmax → Winner
    // "경험(w)이 지각(winner)을 바꾼다"
    // =========================================================================
    // Context Gating: force_valid=1 또는 explore_mode=1 시 w 비중 제거
    // - 평소:        score = rel/2 + w/4 (경험이 지각 강화)
    // - 전換/탐색:   score = rel/2       (현실만이 지배, 선입견 제거)
    // V3.3: explore_mode=1 (에피소드 불안정) → 자동으로 선입견 내려놓음
    wire ctx_gate = force_valid_w | explore_mode;

    wire [7:0] score_ab = rel_ab[7:1] + (ctx_gate ? 8'd0 : stdp_ab[7:2]);
    wire [7:0] score_ac = rel_ac[7:1] + (ctx_gate ? 8'd0 : stdp_ac[7:2]);
    wire [7:0] score_ad = rel_ad[7:1] + (ctx_gate ? 8'd0 : stdp_ad[7:2]);
    wire [7:0] score_bc = rel_bc[7:1] + (ctx_gate ? 8'd0 : stdp_bc[7:2]);
    wire [7:0] score_bd = rel_bd[7:1] + (ctx_gate ? 8'd0 : stdp_bd[7:2]);
    wire [7:0] score_cd = rel_cd[7:1] + (ctx_gate ? 8'd0 : stdp_cd[7:2]);

    reg [2:0] w_comb;
    reg [7:0] ws_comb;  // winner score
    reg [7:0] wr_comb;  // winner raw rel

    always @(*) begin
        w_comb=3'd0; ws_comb=score_ab; wr_comb=rel_ab;
        if (score_ac>ws_comb) begin w_comb=3'd1; ws_comb=score_ac; wr_comb=rel_ac; end
        if (score_ad>ws_comb) begin w_comb=3'd2; ws_comb=score_ad; wr_comb=rel_ad; end
        if (score_bc>ws_comb) begin w_comb=3'd3; ws_comb=score_bc; wr_comb=rel_bc; end
        if (score_bd>ws_comb) begin w_comb=3'd4; ws_comb=score_bd; wr_comb=rel_bd; end
        if (score_cd>ws_comb) begin w_comb=3'd5; ws_comb=score_cd; wr_comb=rel_cd; end
    end

    reg [2:0] winner_r;
    reg [7:0] winner_score_r, winner_rel_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin winner_r<=0; winner_score_r<=0; winner_rel_r<=0; end
        else if (cyc_start) begin
            winner_r       <= w_comb;
            winner_score_r <= ws_comb;
            winner_rel_r   <= wr_comb;
        end
    end

    assign winner_w     = winner_r;
    assign winner       = winner_r;
    assign winner_score = winner_score_r;
    assign winner_rel   = winner_rel_r;

    // =========================================================================
    // L5: Homeostasis decay
    // 매 DECAY_PERIOD gamma마다 모든 w -= 1 (포화/독점 방지)
    // =========================================================================
    // → stdp_gated 내부 decay 파라미터로 처리 (아래 모듈 참조)

    // =========================================================================
    // L6: seq2_predictor (winner_idx → 패턴 기억 + injection)
    // =========================================================================
    reg [7:0] win_idx_mapped;
    always @(*) begin
        case (winner_r)
            3'd0: win_idx_mapped = 8'd0;
            3'd1: win_idx_mapped = 8'd43;
            3'd2: win_idx_mapped = 8'd85;
            3'd3: win_idx_mapped = 8'd128;
            3'd4: win_idx_mapped = 8'd170;
            3'd5: win_idx_mapped = 8'd213;
            default: win_idx_mapped = 8'd0;
        endcase
    end

    wire [7:0] force_pred_w, seq_err_w;
    wire       force_valid_w, seq_lw_w;

    // winner 쌍 fired (seq2 트리거)
    reg win_fired_a_r, win_fired_b_r;
    always @(*) begin
        case (winner_r)
            3'd0: begin win_fired_a_r=fired0; win_fired_b_r=fired1; end
            3'd1: begin win_fired_a_r=fired0; win_fired_b_r=fired2; end
            3'd2: begin win_fired_a_r=fired0; win_fired_b_r=fired3; end
            3'd3: begin win_fired_a_r=fired1; win_fired_b_r=fired2; end
            3'd4: begin win_fired_a_r=fired1; win_fired_b_r=fired3; end
            3'd5: begin win_fired_a_r=fired2; win_fired_b_r=fired3; end
            default: begin win_fired_a_r=1'b0; win_fired_b_r=1'b0; end
        endcase
    end
    wire win_fired = win_fired_a_r | win_fired_b_r;

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
        .slot_A(seq_slot_A), .slot_B(seq_slot_B),
        .last_winner(seq_lw_w), .error_out(seq_err_w)
    );

    assign seq_force_valid = force_valid_w;
    assign seq_force_pred  = force_pred_w;

    // =========================================================================
    // L7: predictive_phase (예측 + injection)
    // =========================================================================
    wire pred_err_sign, pred_err_valid;
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

    // =========================================================================
    // V3.0: Internal Reward Generator (Dopamine Circuit)
    // pred_err=0이 ERR_WIN 사이클 연속되면 internal_reward=1
    // 뇌 비유: VTA 도파민 뉴런 (예측 성공 시 보상)
    // =========================================================================
    wire        pred_err_internal;
    wire [7:0]  pred_err_w;
    assign pred_err_internal = pred_err;
    assign pred_err_w        = pred_err;

    reg [7:0] err_zero_cnt;   // pred_err=0 연속 횟수
    reg       internal_reward;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            err_zero_cnt   <= 8'd0;
            internal_reward <= 1'b0;
        end
        else if (cyc_start) begin
            if (pred_err_w < ERR_THR) begin
                // err < ERR_THR: 여유 있는 수렴 상태
                err_zero_cnt <= (err_zero_cnt < ERR_WIN) ? err_zero_cnt + 8'd1 : ERR_WIN;
                internal_reward <= (err_zero_cnt >= ERR_WIN - 8'd1) ? 1'b1 : 1'b0;
            end
            else begin
                // 오류 발생: 카운터 리셋, reward 해제
                err_zero_cnt   <= 8'd0;
                internal_reward <= 1'b0;
            end
        end
    end

    assign reward_out = internal_reward;

endmodule

// =============================================================================
// Module: stdp_gated v3.0 (R-STDP)
// - reward=1: LTP × 2 (예측 성공 시 각인 2배 강화)
// - reward=0: 교로 LTP (기본)
// =============================================================================
module stdp_gated #(
    parameter [7:0] W_INIT       = 8'd128,
    parameter [7:0] W_MAX        = 8'd190,
    parameter [7:0] W_MIN        = 8'd80,
    parameter [7:0] ETA_LTP      = 8'd4,
    parameter [7:0] ETA_LTD      = 8'd2,
    parameter [7:0] WINDOW       = 8'd30,
    parameter [7:0] DECAY_PERIOD = 8'd2
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       cycle_start,
    input  wire       enable,
    input  wire       reward,      // V3.0: 1=도파민 분비, LTP ×2

    input  wire [7:0] phase_pre,
    input  wire       fired_pre,
    input  wire [7:0] phase_post,
    input  wire       fired_post,

    output reg  [7:0] weight
);
    wire [7:0] raw_diff = phase_pre - phase_post;
    wire [7:0] inv_diff = 8'd255 - raw_diff + 8'd1;
    wire [7:0] diff_abs = (raw_diff <= inv_diff) ? raw_diff : inv_diff;
    wire pre_first  = (raw_diff[7] == 1'b1) && (raw_diff != 8'd0);
    wire post_first = (raw_diff[7] == 1'b0) && (raw_diff != 8'd0);

    // R-STDP: reward=1이면 LTP step 2배
    wire [7:0] eff_ltp = reward ? ((ETA_LTP << 1 > 8'd255) ? 8'd255 : ETA_LTP << 1)
                                : ETA_LTP;

    reg [7:0] decay_cnt;
    reg [8:0] w_next;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight    <= W_INIT;
            decay_cnt <= 8'd0;
        end
        else if (cycle_start) begin
            if (decay_cnt >= DECAY_PERIOD - 1) begin
                decay_cnt <= 8'd0;
                if (weight > W_MIN) weight <= weight - 8'd1;
            end
            else begin
                decay_cnt <= decay_cnt + 8'd1;
                if (enable && fired_pre && fired_post && (diff_abs <= WINDOW)) begin
                    if (pre_first) begin
                        w_next = {1'b0, weight} + {1'b0, eff_ltp};
                        weight <= (w_next > {1'b0, W_MAX}) ? W_MAX : w_next[7:0];
                    end
                    else if (post_first) begin
                        if (weight > ETA_LTD + W_MIN)
                            weight <= weight - ETA_LTD;
                        else
                            weight <= W_MIN;
                    end
                end
            end
        end
    end
endmodule
