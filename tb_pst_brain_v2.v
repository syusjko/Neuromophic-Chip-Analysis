// =============================================================================
// Testbench: tb_pst_brain_v2
//
// [검증 항목]
// 1. score = rel + w>>2 → winner 선택 변화 확인
// 2. STDP: 패턴A winner=AB w_ab 증가, 나머지 감소(decay)
// 3. 학습 전/후 winner 안정성 변화 (w 영향)
// 4. homeostasis: w가 계속 255에 박히지 않는지
// 5. injection: 수렴 2 gamma 유지
//
// [핵심 실험]
// Phase 1: 노이즈 입력 (어떤 패턴인지 불명확)
//          → winner가 흔들림
// Phase 2: 패턴A 반복 학습
//          → w_ab 증가 → score_ab 증가
// Phase 3: 같은 노이즈 다시 입력
//          → 학습 전과 다르게 winner가 더 안정적으로 AB 선택
//          = "경험이 지각을 바꿨다"
// =============================================================================
`timescale 1ns / 1ps

module tb_pst_brain_v2;

    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    reg [7:0] cur0, cur1, cur2, cur3;
    integer cyc_cnt;

    wire [7:0] ph0,ph1,ph2,ph3;
    wire [2:0] w_att;
    wire [7:0] w_score, w_rel;
    wire [7:0] wab,wac,wad,wbc,wbd,wcd;
    wire [7:0] sA,sB;
    wire       fv;
    wire [7:0] fp,p_out,p_err;
    wire       reward_sig;
    wire [2:0] gcnt;
    wire       th_tick;
    wire       ep_last;
    wire [2:0] ep_win;
    wire [3:0] ep_str;
    wire       ep_v;
    wire       exploit_s;
    wire       explore_s;
    wire [1:0] conf_lv;
    wire       err_exp;      // V3.7: err 기반 explore 신호
    // V3.4: Delta
    wire [2:0] th_cnt;     // theta_cnt (delta 내 theta 위치)
    wire       d_tick;     // delta_tick
    wire [2:0] top_win;    // topic_winner
    wire [2:0] top_str;    // topic_strength
    wire       top_v;      // topic_valid

    always @(posedge clk) begin
        if (th_tick)
            $display("  [THETA] ep=%0d str=%0d/8 conf=%0d expl=%0d err_exp=%0d th=%0d cyc=%0d",
                ep_win, ep_str, conf_lv, explore_s, err_exp, th_cnt, cyc_cnt);
        if (d_tick)
            $display("  [DELTA] topic=%0d tstr=%0d/5 cyc=%0d",
                top_win, top_str, cyc_cnt);
    end

    pst_brain_v2 #(
        .THRESHOLD(8'd200),
        .PHASE_TOL(8'd20),
        .ETA_LTP(8'd4),
        .ETA_LTD(8'd2),
        .W_SHIFT(3'd3),
        .DECAY_PERIOD(8'd2),
        .ERR_WIN(8'd3),
        .ERR_THR(8'd5),
        .SLOT_A_INIT(8'd0),
        .SLOT_B_INIT(8'd213)
    ) brain (
        .clk(clk), .rst_n(rst_n),
        .cur0(cur0),.cur1(cur1),.cur2(cur2),.cur3(cur3),
        .phase0(ph0),.phase1(ph1),.phase2(ph2),.phase3(ph3),
        .winner(w_att),.winner_score(w_score),.winner_rel(w_rel),
        .w_ab(wab),.w_ac(wac),.w_ad(wad),
        .w_bc(wbc),.w_bd(wbd),.w_cd(wcd),
        .seq_slot_A(sA),.seq_slot_B(sB),
        .seq_force_valid(fv),.seq_force_pred(fp),
        .pred_out(p_out),.pred_err(p_err),
        .reward_out(reward_sig),
        .gamma_cnt(gcnt),
        .theta_tick(th_tick),
        .episode_last(ep_last),
        .ep_winner(ep_win),
        .ep_strength(ep_str),
        .ep_valid(ep_v),
        .exploit_mode(exploit_s),
        .explore_mode(explore_s),
        .confidence_level(conf_lv),
        .theta_cnt(th_cnt),
        .delta_tick(d_tick),
        .topic_winner(top_win),
        .topic_strength(top_str),
        .topic_valid(top_v),
        .err_explore(err_exp)
    );

    // X 감지
    always @(posedge clk) begin
        if (^wab===1'bx) $display("  [!] w_ab=X at cyc=%0d",cyc_cnt);
    end

    task show_weights;
        begin
            $display("  weights: AB=%0d AC=%0d AD=%0d BC=%0d BD=%0d CD=%0d",
                wab,wac,wad,wbc,wbd,wcd);
        end
    endtask

    task tick; begin
        repeat(256) @(posedge clk); #1;
        cyc_cnt = cyc_cnt + 1;
    end endtask

    task show;
        input integer c;
        reg [7:0] eb, tb;
        begin
            // ep_bias: explore=0, ep_valid, ep_winner==현재 winner
            eb = (!explore_s && ep_v  && (ep_win  == w_att)) ? 8'd4 : 8'd0;
            // topic_bias: explore=0, topic_valid, topic_winner==현재 winner
            tb = (!explore_s && top_v && (top_win == w_att)) ? 8'd2 : 8'd0;
            $display("[C%3d] win=%0d sc=%0d | wAB=%0d wCD=%0d | ep=%0d(+%0d) top=%0d(+%0d) exl=%0d | err=%0d rwd=%0d",
                c, w_att, w_score,
                wab, wcd,
                ep_win, eb, top_win, tb, explore_s,
                p_err, reward_sig);
        end
    endtask

    integer i;
    integer win_ab_before, win_ab_after;  // 노이즈에서 AB 선택 횟수

    initial begin
        rst_n=0; cyc_cnt=0;
        cur0=0;cur1=0;cur2=0;cur3=0;
        repeat(3) @(posedge clk); #1; rst_n=1;

        // =====================================================================
        // Phase 0: 초기 상태 확인
        // =====================================================================
        $display("\n=== [Phase 0] Ambiguous input BEFORE training ===");
        // 모호한 입력: 4채널 유사 강도
        // cur0=140, cur1=130 (AB 쌍, 위상차 작음)
        // cur2=135, cur3=125 (CD 쌍, 위상차 작음)
        // 두 쌍의 rel이 비슷함 → w의 차이가 winner를 결정
        // cur0=200(ph≈1), cur1=20(ph≈230) → AB 위상차 큼 → rel_AB 낮음
        // cur2=195(ph≈1), cur3=180(ph≈2)  → CD 위상차 작음 → rel_CD 높음
        // 학습 전: CD가 이김
        // AB 학습 후: w_AB 증가 → score_AB > score_CD → AB 이김
        cur0=200; cur1=20; cur2=195; cur3=180;
        win_ab_before = 0;
        for (i=0; i<20; i=i+1) begin
            tick;
            if (w_att==3'd0) win_ab_before = win_ab_before+1;
        end
        $display("  Ambiguous input: AB winner %0d/20 times", win_ab_before);
        show_weights;

        // =====================================================================
        // Phase 1: 패턴A 집중 학습 (AB 쌍 강화)
        // cur0=200(phase≈1), cur1=180(phase≈2): AB 쌍이 강하게 공명
        // =====================================================================
        $display("\n=== [Phase 1] Pattern A training (100 cycles) ===");
        cur0=200; cur1=180; cur2=5; cur3=8;
        for (i=0; i<100; i=i+1) begin
            tick;
            if (i==29 || i==49 || i==99) show(cyc_cnt);
        end
        $display("  After 100 cycles training:");
        show_weights;

        // =====================================================================
        // Phase 2: 같은 모호한 입력 → 학습 후 winner 변화 확인
        // "경험이 지각을 바꿨는가?"
        // =====================================================================
        $display("\n=== [Phase 2] Same ambiguous input (after learning) ===");
        // cur0=200(ph≈1), cur1=20(ph≈230) → AB 위상차 큼 → rel_AB 낮음
        // cur2=195(ph≈1), cur3=180(ph≈2)  → CD 위상차 작음 → rel_CD 높음
        // 학습 전: CD가 이김
        // AB 학습 후: w_AB 증가 → score_AB > score_CD → AB 이김
        cur0=200; cur1=20; cur2=195; cur3=180;
        win_ab_after = 0;
        for (i=0; i<20; i=i+1) begin
            tick;
            if (w_att==3'd0) win_ab_after = win_ab_after+1;
        end
        $display("  Ambiguous input: AB winner %0d/20 times", win_ab_after);
        $display("  Before training: %0d/20, After training: %0d/20",
            win_ab_before, win_ab_after);
        $display("  -> Perception changed by experience: %s",
            (win_ab_after > win_ab_before) ? "YES (LEARNING WORKS)" : "NOT YET");

        // =====================================================================
        // Phase 3: B 집중 학습 (w_CD 균형 회복)
        // A만 70사이클 학습했으므로 w_AB >> w_CD
        // B를 같은 만큼 학습해 균형 맞추기
        // =====================================================================
        $display("\n=== [Phase 3] Balance: train Pattern B (75 cycles) ===");
        cur0=5; cur1=8; cur2=200; cur3=180;
        for (i=0; i<75; i=i+1) begin
            tick;
            if (i==49 || i==74) begin
                $display("  [B cyc %0d] wAB=%0d wCD=%0d gap=%0d",
                    i+1, wab, wcd, (wab>wcd)?(wab-wcd):(wcd-wab));
            end
        end
        $display("  After 75 cycles PatB:");
        show_weights;
        $display("  -> w_AB vs w_CD gap: %0d",
            (wab > wcd) ? wab-wcd : wcd-wab);

        // =====================================================================
        // Phase 4: A 안정화 후 Trans
        // =====================================================================
        $display("\n=== [Phase 4] + Trans ===");
        // A 안정화 (30사이클: w_AB 회복)
        cur0=200; cur1=180; cur2=5; cur3=8;
        for (i=0; i<30; i=i+1) tick;
        $display("  Pre-Trans weights:"); show_weights;

        // Trans A→B
        $display("\n--- [Trans A->B] ---");
        cur0=5; cur1=8; cur2=200; cur3=180;
        for (i=0; i<10; i=i+1) begin
            tick;
            $display("  [C%3d] win=%0d sc=%0d rel=%0d wAB=%0d wCD=%0d pred=%0d err=%0d fv=%0d fp=%0d",
                cyc_cnt, w_att, w_score, w_rel, wab, wcd, p_out, p_err, fv, fp);
        end

        // Trans B→A
        $display("\n--- [Trans B->A] ---");
        cur0=200; cur1=180; cur2=5; cur3=8;
        for (i=0; i<10; i=i+1) begin
            tick;
            $display("  [C%3d] win=%0d sc=%0d rel=%0d wAB=%0d wCD=%0d pred=%0d err=%0d fv=%0d fp=%0d",
                cyc_cnt, w_att, w_score, w_rel, wab, wcd, p_out, p_err, fv, fp);
        end

        // =====================================================================
        // Phase 5.5: A/B 교번 -> explore_mode 발동 테스트
        // Phase 4 balanced 상태(w_AB≈w_CD)에서 gamma마다 A/B 교번
        // 4A + 4B per theta → str ≈ 4/8 → conf는 3→2→1 하강 → expl=1 기대
        // =====================================================================
        $display("\n=== [Phase 5.5] A/B alternating → explore_mode test ===");
        $display("  입력: gamma마다 A/B 교번 (4A+4B per theta → str=4/8 기대)");
        for (i=0; i<32; i=i+1) begin
            // 짝수 gamma: 패턴A, 홀수 gamma: 패턴B
            if (i[0] == 1'b0) begin
                cur0=200; cur1=180; cur2=5; cur3=8;   // A
            end else begin
                cur0=5; cur1=8; cur2=200; cur3=180;   // B
            end
            tick;
            if (i==7 || i==15 || i==23 || i==31) begin
                $display("  [Alt C%0d] win=%0d str=%0d conf=%0d expl=%0d sc=%0d",
                    cyc_cnt, w_att, ep_str, conf_lv, explore_s, w_score);
            end
        end
        $display("  Final: conf=%0d expl=%0d", conf_lv, explore_s);
        if (explore_s)
            $display("  -> explore_mode ACTIVATED ✅ 선입견 제거 루프 증명!");
        else
            $display("  -> explore_mode not triggered (str>5 or conf>2)");

        // =====================================================================
        // Phase 5: Homeostasis 장기 관찰
        // =====================================================================
        $display("\n=== [Phase 5] Homeostasis long-term ===");
        cur0=200; cur1=180; cur2=5; cur3=8;
        for (i=0; i<100; i=i+1) tick;
        $display("  After 100 cycles PatA (from balanced state):");
        show_weights;
        $display("  -> w_AB homeostasis: %s",
            (wab<240 && wab>128) ? "BALANCED" :
            (wab>=240)           ? "HIGH (check decay)" : "LOW");

        // =====================================================================
        // Phase 6: Ambiguous 경계값 → explore_mode 발동 테스트
        // A/B 경계값: winner가 자주 바뀜 → str ≤ 5 → expl=1 기대
        // =====================================================================
        $display("\n=== [Phase 6] Ambiguous Boundary → explore_mode test ===");
        $display("  Input: A/B 4-cycle alternating (빠른 교번으로 str 낮추기)");
        $display("  기대: str<=5 → conf↓ → expl=1 → bias 제거");
        for (i=0; i<32; i=i+1) begin
            // 4사이클 A, 4사이클 B 고속 교번
            if ((i/4)%2 == 0) begin
                cur0=200; cur1=180; cur2=5; cur3=8;
            end else begin
                cur0=5; cur1=8; cur2=200; cur3=180;
            end
            tick;
            if (i==7 || i==15 || i==23 || i==31) begin
                $display("  [Amb C%0d] win=%0d str=%0d conf=%0d expl=%0d sc=%0d wAB=%0d wCD=%0d",
                    cyc_cnt, w_att, ep_str, conf_lv, explore_s,
                    w_score, wab, wcd);
            end
        end
        $display("  After 32 cycles ambiguous:");
        $display("  Final: conf=%0d expl=%0d wAB=%0d wCD=%0d",
            conf_lv, explore_s, wab, wcd);
        if (explore_s)
            $display("  -> explore_mode ACTIVATED: 선입견 제거 루프 증명 ✅");
        else
            $display("  -> explore_mode not triggered (str>5 or conf>2)");

        $display("\n=== Brain V3.3 DONE ===");
        $finish;
    end
endmodule
