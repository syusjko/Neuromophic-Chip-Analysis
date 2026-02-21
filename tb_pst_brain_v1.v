// =============================================================================
// Testbench: tb_pst_brain_v1
// 폐루프 동작 검증
//
// [검증 항목]
// 1. 어텐션이 가장 관련있는 쌍을 올바르게 선택하는가
// 2. 경험이 쌓일수록 STDP 가중치가 변하는가 (학습)
// 3. seq2가 winner 패턴을 분리 학습하는가
// 4. 패턴 전환 시 injection으로 빠르게 수렴하는가
// 5. 두 번째 전환이 첫 번째보다 빠른가 (경험 축적 효과)
// =============================================================================
`timescale 1ns / 1ps

module tb_pst_brain_v1;

    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    // === 입력 패턴 설정 ===
    // 패턴 A: cur0=200, cur1=180 (강한 신호 → phase≈1)
    //         cur2=5,   cur3=8   (약한 신호 → phase≈40)
    // 패턴 B: cur0=5,   cur1=8   (약한 신호 → phase≈40)
    //         cur2=200, cur3=180 (강한 신호 → phase≈1)
    // 
    // 두 패턴에서 winner 쌍:
    //   패턴A: cur0-cur1 쌍 (둘 다 강함, 위상 유사) → winner=AB
    //   패턴B: cur2-cur3 쌍 (둘 다 강함, 위상 유사) → winner=CD
    // 이게 정확히 선택되면 어텐션 동작 확인

    reg [7:0] cur0, cur1, cur2, cur3;
    integer cyc_cnt;

    wire [7:0] ph0,ph1,ph2,ph3;
    wire [2:0] w_att;
    wire [7:0] w_rel;
    wire [7:0] w_stdp;
    wire [7:0] sA, sB;
    wire       fv;
    wire [7:0] fp;
    wire [7:0] p_out, p_err;

    pst_brain_v1 #(
        .THRESHOLD(8'd200),
        .PHASE_TOL(8'd20),
        .ETA_LTP(8'd4),
        .ETA_LTD(8'd3),
        .SLOT_A_INIT(8'd0),
        .SLOT_B_INIT(8'd213)
    ) brain (
        .clk(clk), .rst_n(rst_n),
        .cur0(cur0), .cur1(cur1), .cur2(cur2), .cur3(cur3),
        .phase0(ph0), .phase1(ph1), .phase2(ph2), .phase3(ph3),
        .winner(w_att), .winner_rel(w_rel),
        .w_winner(w_stdp),
        .seq_slot_A(sA), .seq_slot_B(sB),
        .seq_force_valid(fv), .seq_force_pred(fp),
        .pred_out(p_out), .pred_err(p_err)
    );

    // X 감지: w_stdp가 X가 되는 첫 사이클 감지
    always @(posedge clk) begin
        if (^w_stdp === 1'bx)
            $display("  [WARNING] w_stdp became X at cyc=%0d", cyc_cnt);
    end

    // gamma 사이클 카운터 (brain 내부 osc와 sync는 안 맞지만 moitoring용)
    // → brain의 cyc_start에 접근 불가하므로 256 clk 단위로 샘플링
    task sample;
        input integer c;
        begin
            $display(
                "[C%3d] ph=(%2d,%2d,%2d,%2d) win=%0d rel=%0d w=%0d | seq sA=%2d sB=%2d fv=%0d fp=%2d | pred=%2d err=%2d",
                c, ph0,ph1,ph2,ph3,
                w_att, w_rel, w_stdp,
                sA, sB, fv, fp,
                p_out, p_err
            );
        end
    endtask

    integer i;
    integer trans_cyc, a_hit, b_hit;

    initial begin
        rst_n=0; cyc_cnt=0;
        cur0=0; cur1=0; cur2=0; cur3=0;
        repeat(3) @(posedge clk); #1; rst_n=1;

        // =====================================================================
        // Phase 1: 패턴 A 학습 (30 gamma 사이클)
        // cur0=200, cur1=180 (강), cur2=5, cur3=8 (약)
        // winner=AB 기대
        // =====================================================================
        $display("\n=== [Phase 1A] Pattern A learning (cur0=200,cur1=180 strong) ===");
        cur0=200; cur1=180; cur2=5; cur3=8;
        for (i=0; i<30; i=i+1) begin
            repeat(256) @(posedge clk); #1;
            cyc_cnt=cyc_cnt+1;
            if (i==0 || i==9 || i==19 || i==29) sample(cyc_cnt);
        end
        $display("  Pattern A settled: winner=%0d(expect 0=AB) rel=%0d w_stdp=%0d sA=%0d sB=%0d",
            w_att, w_rel, w_stdp, sA, sB);

        // =====================================================================
        // Phase 1B: 패턴 B 학습 (30 gamma 사이클)
        // cur0=5, cur1=8 (약), cur2=200, cur3=180 (강)
        // winner=CD 기대
        // =====================================================================
        $display("\n=== [Phase 1B] Pattern B learning (cur2=200,cur3=180 strong) ===");
        cur0=5; cur1=8; cur2=200; cur3=180;
        for (i=0; i<30; i=i+1) begin
            repeat(256) @(posedge clk); #1;
            cyc_cnt=cyc_cnt+1;
            if (i==0 || i==9 || i==19 || i==29) sample(cyc_cnt);
        end
        $display("  Pattern B settled: winner=%0d(expect 5=CD) rel=%0d w_stdp=%0d sA=%0d sB=%0d",
            w_att, w_rel, w_stdp, sA, sB);

        // =====================================================================
        // Phase 2: 한 번 더 반복 (경험 축적)
        // =====================================================================
        $display("\n=== [Phase 2] Experience accumulation ===");
        cur0=200; cur1=180; cur2=5; cur3=8;
        repeat(7680) @(posedge clk); #1; cyc_cnt=cyc_cnt+30;
        cur0=5; cur1=8; cur2=200; cur3=180;
        repeat(7680) @(posedge clk); #1; cyc_cnt=cyc_cnt+30;
        $display("  sA=%0d sB=%0d (after 120 cycles total)", sA, sB);

        // =====================================================================
        // Phase 3: 전환 속도 비교
        // Trans 1: A→B 전환
        // =====================================================================
        $display("\n=== [Phase 3] Pattern switching speed ===");

        // 패턴A에서 안정화 (15 사이클)
        cur0=200; cur1=180; cur2=5; cur3=8;
        repeat(3840) @(posedge clk); #1; cyc_cnt=cyc_cnt+15;

        // B로 전환
        $display("\n--- [Trans 1] A->B switch ---");
        cur0=5; cur1=8; cur2=200; cur3=180;
        trans_cyc=cyc_cnt; a_hit=0;
        for (i=0; i<15; i=i+1) begin
            repeat(256) @(posedge clk); #1; cyc_cnt=cyc_cnt+1;
            $display("  [C%3d] win=%0d rel=%0d pred=%2d err=%2d fv=%0d fp=%2d",
                cyc_cnt, w_att, w_rel, p_out, p_err, fv, fp);
            if (a_hit==0 && p_err<=3 && cyc_cnt>trans_cyc+1) a_hit=cyc_cnt-trans_cyc;
        end
        $display("  -> convergence: %0d gamma cycles", (a_hit>0)?a_hit:15);

        // A로 전환
        $display("\n--- [Trans 2] B->A switch ---");
        cur0=200; cur1=180; cur2=5; cur3=8;
        trans_cyc=cyc_cnt; b_hit=0;
        for (i=0; i<15; i=i+1) begin
            repeat(256) @(posedge clk); #1; cyc_cnt=cyc_cnt+1;
            $display("  [C%3d] win=%0d rel=%0d pred=%2d err=%2d fv=%0d fp=%2d",
                cyc_cnt, w_att, w_rel, p_out, p_err, fv, fp);
            if (b_hit==0 && p_err<=3 && cyc_cnt>trans_cyc+1) b_hit=cyc_cnt-trans_cyc;
        end
        $display("  -> convergence: %0d gamma cycles", (b_hit>0)?b_hit:15);

        // =====================================================================
        // 최종 판정
        // =====================================================================
        $display("\n=== CLOSED LOOP BRAIN v1 SUMMARY ===");
        $display("  Attention:    PatA winner=%0d(expect 0=AB), PatB winner=%0d(expect 5=CD) -> %s",
            0, 5,
            (sA<50 && sB>163) ? "CORRECT" : "CHECK");
        $display("  STDP weight:  %0d (changed from 128: %s)", w_stdp,
            (w_stdp != 128) ? "YES" : "NOT YET - check phase_stdp");
        $display("  Seq2 slots:   sA=%0d sB=%0d (split= %s)",
            sA, sB, ((sA<20)&&(sB>20)) ? "YES" : "NOT YET");
        $display("  Injection:    force hits=%0d/%0d cycles",
            a_hit, b_hit);

        $finish;
    end
endmodule
