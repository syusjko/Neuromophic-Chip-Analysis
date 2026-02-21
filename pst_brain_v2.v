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
    parameter [7:0] ERR_WIN      = 8'd3,
    parameter [7:0] ERR_THR      = 8'd5,

    // V3.5: 문맥 bias (단기 + 장기)
    parameter [3:0] EP_BIAS      = 4'd4,   // ep_winner 일치 시 +4 (theta 단기)
    parameter [3:0] TOPIC_BIAS   = 4'd2,   // topic_winner 일치 시 +2 (delta 장기)

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
    output wire [2:0]  gamma_cnt,
    output wire        theta_tick,
    output wire        episode_last,

    // V3.2: 에피소드 기억
    output wire [2:0]  ep_winner,
    output wire [3:0]  ep_strength,
    output wire        ep_valid,

    // V3.3: 메타인지
    output wire        exploit_mode,
    output wire        explore_mode,
    output wire [1:0]  confidence_level,

    // V3.4: Delta (주제 유지 회로)
    output wire [2:0]  theta_cnt,      // delta 내 theta 위치 (0~4)
    output wire        delta_tick,     // 주제 경계 (5 theta마다)
    output wire [2:0]  topic_winner,
    output wire [2:0]  topic_strength,
    output wire        topic_valid,
    output wire        err_explore     // V3.7: err 기반 explore 신호
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
    metacognition #(.EXPLOIT_THR(4'd6), .EXPLORE_THR(4'd5), .CONF_EXP_THR(2'd2),
                    .ERR_HIGH_THR(8'd50), .ERR_FORCE_WIN(8'd5)) meta (
        .clk(clk), .rst_n(rst_n),
        .theta_tick(theta_tick),
        .ep_strength(ep_strength),
        .ep_valid(ep_valid),
        .pred_err(pred_err_w),
        .cyc_start(cyc_start),
        .input_mismatch(input_mismatch),  // V3.7b: rel 기반 조기 불일치 감지
        .exploit_mode(exploit_mode),
        .explore_mode(explore_mode),
        .confidence_level(confidence_level),
        .err_explore(err_explore_w)
    );
    // V3.4: Delta (5 theta = 1 대화 주제 단위)
    delta_oscillator #(.THETA_PER_DELTA(3'd4)) delta (
        .clk(clk), .rst_n(rst_n),
        .theta_tick(theta_tick),
        .theta_cnt(theta_cnt),
        .delta_tick(delta_tick),
        .topic_last()
    );

    // V3.4: Topic Memory (주제 기억, 전전두엽 working memory)
    topic_memory topic (
        .clk(clk), .rst_n(rst_n),
        .theta_tick(theta_tick),
        .delta_tick(delta_tick),
        .ep_winner(ep_winner),
        .topic_winner(topic_winner),
        .topic_strength(topic_strength),
        .topic_valid(topic_valid)
    );

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

    // V3.8: STDP global protect (Catastrophic Forgetting 완전 방지)
    // 변경: "topic 불일치 쌍만" → "explore=0이면 모든 쌍 보호"
    // 이유: wAB 하락 원인이 LTD가 아닌 decay임
    //        B 패턴 75사이클 × decay_period=2 → wAB 190→98 (decay가 주범)
    //        topic=AB일 때도 prot_ab=0이어서 decay 계속됨 → 설계 버그
    // 수정: explore=0이면 모든 시냅스 decay+LTD 차단
    //        winner가 된 쌍만 LTP (강화는 항상 허용)
    //        explore=1: 모든 보호 해제 → 완전 자유 학습
    // 효과:
    //   Phase 1 A: AB winner → wAB LTP, wCD decay 없음 (128 유지)
    //   Phase 3 B: CD winner → wCD LTP, wAB decay 없음 → CF 방지! ✅
    //   explore=1: 모든 보호 해제 → 새 패턴 완전 수용
    wire prot_any = topic_valid && !explore_mode;
    wire prot_ab = prot_any;
    wire prot_ac = prot_any;
    wire prot_ad = prot_any;
    wire prot_bc = prot_any;
    wire prot_bd = prot_any;
    wire prot_cd = prot_any;

    // STDP 인스턴스 (V3.0: reward / V3.6: protect)
    stdp_gated #(.W_INIT(8'd128),.ETA_LTP(ETA_LTP),.ETA_LTD(ETA_LTD),.DECAY_PERIOD(DECAY_PERIOD)) s_ab (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.enable(en_ab),.reward(internal_reward),.protect(prot_ab),
        .phase_pre(phase0),.fired_pre(fired0),
        .phase_post(phase1),.fired_post(fired1),
        .weight(stdp_ab));
    stdp_gated #(.W_INIT(8'd128),.ETA_LTP(ETA_LTP),.ETA_LTD(ETA_LTD),.DECAY_PERIOD(DECAY_PERIOD)) s_ac (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.enable(en_ac),.reward(internal_reward),.protect(prot_ac),
        .phase_pre(phase0),.fired_pre(fired0),
        .phase_post(phase2),.fired_post(fired2),
        .weight(stdp_ac));
    stdp_gated #(.W_INIT(8'd128),.ETA_LTP(ETA_LTP),.ETA_LTD(ETA_LTD),.DECAY_PERIOD(DECAY_PERIOD)) s_ad (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.enable(en_ad),.reward(internal_reward),.protect(prot_ad),
        .phase_pre(phase0),.fired_pre(fired0),
        .phase_post(phase3),.fired_post(fired3),
        .weight(stdp_ad));
    stdp_gated #(.W_INIT(8'd128),.ETA_LTP(ETA_LTP),.ETA_LTD(ETA_LTD),.DECAY_PERIOD(DECAY_PERIOD)) s_bc (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.enable(en_bc),.reward(internal_reward),.protect(prot_bc),
        .phase_pre(phase1),.fired_pre(fired1),
        .phase_post(phase2),.fired_post(fired2),
        .weight(stdp_bc));
    stdp_gated #(.W_INIT(8'd128),.ETA_LTP(ETA_LTP),.ETA_LTD(ETA_LTD),.DECAY_PERIOD(DECAY_PERIOD)) s_bd (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.enable(en_bd),.reward(internal_reward),.protect(prot_bd),
        .phase_pre(phase1),.fired_pre(fired1),
        .phase_post(phase3),.fired_post(fired3),
        .weight(stdp_bd));
    stdp_gated #(.W_INIT(8'd128),.ETA_LTP(ETA_LTP),.ETA_LTD(ETA_LTD),.DECAY_PERIOD(DECAY_PERIOD)) s_cd (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.enable(en_cd),.reward(internal_reward),.protect(prot_cd),
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
    // V3.8b: ctx_gate 분리
    //   input_mismatch     (stable 있음) → explore 트리거 (과도 탐색 방지)
    //   input_mismatch_ctx (stable 없음) → w bias 즉시 제거 (B패턴 즉시 인식)
    wire ctx_gate = force_valid_w | explore_mode | input_mismatch_ctx;

    // V3.5: 문맥 bias
    // - ep_winner(theta 단기): 직전 에피소드와 같은 쌍에 +EP_BIAS
    // - topic_winner(delta 장기): 현재 대화 주제와 같은 쌍에 +TOPIC_BIAS
    // - explore=1: 둘 다 0 (편견 완전 제거, Phase 5.5 철학 유지)
    wire [7:0] ep_b_ab    = (ep_valid    && (ep_winner    == 3'd0)) ? {4'd0, EP_BIAS}    : 8'd0;
    wire [7:0] ep_b_ac    = (ep_valid    && (ep_winner    == 3'd1)) ? {4'd0, EP_BIAS}    : 8'd0;
    wire [7:0] ep_b_ad    = (ep_valid    && (ep_winner    == 3'd2)) ? {4'd0, EP_BIAS}    : 8'd0;
    wire [7:0] ep_b_bc    = (ep_valid    && (ep_winner    == 3'd3)) ? {4'd0, EP_BIAS}    : 8'd0;
    wire [7:0] ep_b_bd    = (ep_valid    && (ep_winner    == 3'd4)) ? {4'd0, EP_BIAS}    : 8'd0;
    wire [7:0] ep_b_cd    = (ep_valid    && (ep_winner    == 3'd5)) ? {4'd0, EP_BIAS}    : 8'd0;

    wire [7:0] top_b_ab   = (topic_valid && (topic_winner == 3'd0)) ? {5'd0, TOPIC_BIAS} : 8'd0;
    wire [7:0] top_b_ac   = (topic_valid && (topic_winner == 3'd1)) ? {5'd0, TOPIC_BIAS} : 8'd0;
    wire [7:0] top_b_ad   = (topic_valid && (topic_winner == 3'd2)) ? {5'd0, TOPIC_BIAS} : 8'd0;
    wire [7:0] top_b_bc   = (topic_valid && (topic_winner == 3'd3)) ? {5'd0, TOPIC_BIAS} : 8'd0;
    wire [7:0] top_b_bd   = (topic_valid && (topic_winner == 3'd4)) ? {5'd0, TOPIC_BIAS} : 8'd0;
    wire [7:0] top_b_cd   = (topic_valid && (topic_winner == 3'd5)) ? {5'd0, TOPIC_BIAS} : 8'd0;

    wire [7:0] score_ab = rel_ab[7:1]
                        + (ctx_gate    ? 8'd0 : stdp_ab[7:2])   // w 대싛스
                        + (explore_mode? 8'd0 : ep_b_ab)        // 단기 문맥
                        + (explore_mode? 8'd0 : top_b_ab);      // 장기 주제
    wire [7:0] score_ac = rel_ac[7:1]
                        + (ctx_gate    ? 8'd0 : stdp_ac[7:2])
                        + (explore_mode? 8'd0 : ep_b_ac)
                        + (explore_mode? 8'd0 : top_b_ac);
    wire [7:0] score_ad = rel_ad[7:1]
                        + (ctx_gate    ? 8'd0 : stdp_ad[7:2])
                        + (explore_mode? 8'd0 : ep_b_ad)
                        + (explore_mode? 8'd0 : top_b_ad);
    wire [7:0] score_bc = rel_bc[7:1]
                        + (ctx_gate    ? 8'd0 : stdp_bc[7:2])
                        + (explore_mode? 8'd0 : ep_b_bc)
                        + (explore_mode? 8'd0 : top_b_bc);
    wire [7:0] score_bd = rel_bd[7:1]
                        + (ctx_gate    ? 8'd0 : stdp_bd[7:2])
                        + (explore_mode? 8'd0 : ep_b_bd)
                        + (explore_mode? 8'd0 : top_b_bd);
    wire [7:0] score_cd = rel_cd[7:1]
                        + (ctx_gate    ? 8'd0 : stdp_cd[7:2])
                        + (explore_mode? 8'd0 : ep_b_cd)
                        + (explore_mode? 8'd0 : top_b_cd);

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

    // V3.7b: best_alt_rel = winner 제외 최고 rel
    // "입력이 현재 winner 패턴과 얼마나 다른가"를 측정
    reg [7:0] wa_comb;  // winner_alt_rel
    always @(*) begin
        wa_comb = 8'd0;
        if (w_comb != 3'd0 && rel_ab > wa_comb) wa_comb = rel_ab;
        if (w_comb != 3'd1 && rel_ac > wa_comb) wa_comb = rel_ac;
        if (w_comb != 3'd2 && rel_ad > wa_comb) wa_comb = rel_ad;
        if (w_comb != 3'd3 && rel_bc > wa_comb) wa_comb = rel_bc;
        if (w_comb != 3'd4 && rel_bd > wa_comb) wa_comb = rel_bd;
        if (w_comb != 3'd5 && rel_cd > wa_comb) wa_comb = rel_cd;
    end

    reg [2:0]  winner_r;
    reg [7:0]  winner_score_r, winner_rel_r, winner_alt_rel_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin winner_r<=0; winner_score_r<=0; winner_rel_r<=0; winner_alt_rel_r<=0; end
        else if (cyc_start) begin
            winner_r       <= w_comb;
            winner_score_r <= ws_comb;
            winner_rel_r   <= wr_comb;
            winner_alt_rel_r <= wa_comb;
        end
    end

    assign winner_w     = winner_r;
    assign winner       = winner_r;
    assign winner_score = winner_score_r;
    assign winner_rel   = winner_rel_r;

    // V3.7b: Input Mismatch 감지 + winner 안정성 필터
    // "winner가 충분히 안정된 후에도 rel이 다른 패턴을 원하면 → mismatch"
    // "단순한 노이즈나 초기 과도 상태는 무시"
    localparam [7:0] MISMATCH_DIF   = 8'd20;  // alt rel이 winner rel보다 20 이상
    localparam [7:0] STABLE_WIN     = 8'd10;  // winner가 10사이클 연속 같아야 안정

    reg [2:0] prev_winner_r;
    reg [7:0] stable_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            prev_winner_r <= 3'd0;
            stable_cnt    <= 8'd0;
        end
        else if (cyc_start) begin
            if (winner_r == prev_winner_r) begin
                if (stable_cnt < 8'd255) stable_cnt <= stable_cnt + 8'd1;
            end
            else begin
                stable_cnt <= 8'd0;  // winner 바뀌면 카운터 리셋
            end
            prev_winner_r <= winner_r;
        end
    end

    wire winner_stable = (stable_cnt >= STABLE_WIN);
    // ① explore용 mismatch: stable 필터 있음 (Phase 1 상시 expl 방지)
    wire input_mismatch = !winner_stable &&
                          (winner_alt_rel_r > winner_rel_r + MISMATCH_DIF);
    // ② ctx_gate용 mismatch: stable 필터 없음 (B패턴 즉시 ctx 전환)
    //    DIF=40 (더 큰 차이만 감지, 노이즈/약한 신호 무시)
    //    B패턴: cur0=5, cur1=8 → rel_AB≈0, cur2=200, cur3=180 → rel_CD≈고
    //    차이가 40 이상이면 "완전히 다른 패턴" 판단 → ctx_gate=1
    localparam [7:0] MISMATCH_CTX = 8'd40;
    wire input_mismatch_ctx = (winner_alt_rel_r > winner_rel_r + MISMATCH_CTX);

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
    assign err_explore = err_explore_w;

    wire        pred_err_internal;
    wire [7:0]  pred_err_w;
    wire        err_explore_w;       // V3.7: err 기반 탐색 신호
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
// Module: stdp_gated v3.6 (R-STDP + Context Protection)
// - reward=1:  LTP × 2 (예측 성공 시 각인 2배)
// - protect=1: LTD 완전 차단 (주제 불일치 시 시냅스 보호)
//              = "내 문맥이 아닌 쌍의 시냅스는 허물지 마라"
//              decay도 차단 (보호 중엔 자연 감쇠도 없음)
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
    input  wire       reward,      // V3.0: 1=LTP×2
    input  wire       protect,     // V3.6: 1=LTD+decay 차단

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
                // protect=1이면 decay도 차단 (보호 기간 중 자연 감쇠 없음)
                if (!protect && weight > W_MIN) weight <= weight - 8'd1;
            end
            else begin
                decay_cnt <= decay_cnt + 8'd1;
                if (enable && fired_pre && fired_post && (diff_abs <= WINDOW)) begin
                    if (pre_first) begin
                        // LTP: protect 무관하게 항상 허용 (강화는 언제나 가능)
                        w_next = {1'b0, weight} + {1'b0, eff_ltp};
                        weight <= (w_next > {1'b0, W_MAX}) ? W_MAX : w_next[7:0];
                    end
                    else if (post_first && !protect) begin
                        // LTD: protect=1이면 차단
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
