// =============================================================================
// Testbench: tb_alternating_pattern
// 교번 패턴에서 계층적 학습 효과 검증
//
// [실험 설계]
// Phase 1: cur=50 (phase=4) 고정 → L2, L3 수렴 (20사이클)
// Phase 2: cur=50↔20 교번, 4사이클 주기
//          A (L3 active): L3 top-down → L2 전환 가속?
//          B (L3 frozen): 순수 반응형
//
// [측정 지표]
// 전환 지연 (Transition Latency):
//   cur 변화 후 L2 err가 다시 ≤5가 되는 사이클 수
//   A_latency < B_latency → 계층 효과 증명
//
// [핵심 가설]
// L3가 4↔10 진동 패턴을 학습하면:
//   전환 직전 L3 err가 증가 (패턴 예측 불확실)
//   이 L3 err → L2 eta_boost 증가
//   → L2가 새 패턴으로 더 빠르게 전환
// =============================================================================
`timescale 1ns / 1ps

module tb_alternating_pattern;

    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    wire [7:0] gphase;
    wire       cyc_start;
    gamma_oscillator #(.CYCLE_LEN(9'd256)) osc (
        .clk(clk), .rst_n(rst_n),
        .phase_out(gphase), .cycle_start(cyc_start)
    );

    reg [7:0] cur;

    // DUT_A: L3 active
    wire [7:0] ph_A, err_A, prd_A, errL3_A, boost_A, W_A, pL3_A, wL3_A;
    wire       f_A, es_A, es3_A;

    pst_2layer #(.THRESHOLD(8'd200), .W_INIT(8'd128),
                 .ETA_LTP(8'd4), .ETA_LTD(8'd3), .WINDOW(8'd128))
    DUT_A (
        .clk(clk), .rst_n(rst_n),
        .cycle_start(cyc_start), .global_phase(gphase),
        .input_current(cur), .l3_freeze(1'b0),
        .phase_L1(ph_A), .fired_L1(f_A),
        .pred_L2(prd_A), .error_L2(err_A), .err_sign_L2(es_A), .weight_L2(W_A),
        .pred_L3(pL3_A), .error_L3(errL3_A), .err_sign_L3(es3_A), .weight_L3(wL3_A),
        .eta_boost_L2(boost_A)
    );

    // DUT_B: L3 frozen
    wire [7:0] ph_B, err_B, prd_B, errL3_B, boost_B, W_B, pL3_B, wL3_B;
    wire       f_B, es_B, es3_B;

    pst_2layer #(.THRESHOLD(8'd200), .W_INIT(8'd128),
                 .ETA_LTP(8'd4), .ETA_LTD(8'd3), .WINDOW(8'd128))
    DUT_B (
        .clk(clk), .rst_n(rst_n),
        .cycle_start(cyc_start), .global_phase(gphase),
        .input_current(cur), .l3_freeze(1'b1),
        .phase_L1(ph_B), .fired_L1(f_B),
        .pred_L2(prd_B), .error_L2(err_B), .err_sign_L2(es_B), .weight_L2(W_B),
        .pred_L3(pL3_B), .error_L3(errL3_B), .err_sign_L3(es3_B), .weight_L3(wL3_B),
        .eta_boost_L2(boost_B)
    );

    // 전환 지연 측정
    integer cyc_cnt, pattern;
    integer latency_A, latency_B;
    integer trans_start;
    integer lat_A_total, lat_B_total, trans_count;
    reg     measuring;

    always @(posedge clk) begin
        if (cyc_start) cyc_cnt = cyc_cnt + 1;

        if (cyc_start && cyc_cnt > 1 && pattern == 2) begin
            $display("  [C%3d] cur=%3d ph=%2d | A:pred=%2d err=%2d bst=%2d L3pred=%2d eL3=%2d | B:pred=%2d err=%2d",
                cyc_cnt, cur, ph_A,
                prd_A, err_A, boost_A, pL3_A, errL3_A,
                prd_B, err_B);
        end
    end

    // 전환 후 수렴 사이클 측정 task
    task measure_latency;
        input [7:0] new_cur;
        input integer trans_num;
        integer start_cyc, a_conv, b_conv;
        begin
            cur = new_cur;
            start_cyc = cyc_cnt;
            a_conv = 0; b_conv = 0;

            // 최대 20사이클 측정
            repeat(20) begin
                repeat(256) @(posedge clk);
                if (a_conv == 0 && err_A <= 5) a_conv = cyc_cnt - start_cyc;
                if (b_conv == 0 && err_B <= 5) b_conv = cyc_cnt - start_cyc;
            end

            if (a_conv > 0 && b_conv > 0) begin
                lat_A_total = lat_A_total + a_conv;
                lat_B_total = lat_B_total + b_conv;
                trans_count = trans_count + 1;
            end

            $display("  [Trans%0d: cur=%0d→%0d] A=%0dcyc, B=%0dcyc %s",
                trans_num, (new_cur==8'd20)?8'd50:8'd20, new_cur,
                a_conv, b_conv,
                (a_conv < b_conv) ? "← A faster!" : "");
        end
    endtask

    initial begin
        rst_n=0; cyc_cnt=0; cur=0; pattern=0;
        lat_A_total=0; lat_B_total=0; trans_count=0;
        repeat(3) @(posedge clk); #1; rst_n=1;

        // ─────────────────────────────────────────
        // Phase 1: 수렴 (cur=50 고정, 20사이클)
        // ─────────────────────────────────────────
        $display("=== [Phase 1] 초기 수렴: cur=50, 20사이클 ===");
        pattern = 1;
        cur = 8'd50;
        repeat(5120) @(posedge clk); #1;  // 20사이클
        $display("  수렴 완료: A pred=%0d err=%0d | B pred=%0d err=%0d",
                 prd_A, err_A, prd_B, err_B);

        // ─────────────────────────────────────────
        // Phase 2: 교번 패턴 (4사이클 주기 × 6회 전환)
        // L3가 패턴 학습하면서 boost가 증가하는지 관찰
        // ─────────────────────────────────────────
        $display("\n=== [Phase 2] 교번 패턴 실험 ===");
        $display("  col: [사이클] cur ph | A:pred err boost L3pred L3err | B:pred err");
        pattern = 2;

        // 전환 1: 50→20 (phase 4→10)
        $display("\n--- [Trans 1] cur=50→20 ---");
        cur = 8'd20;
        repeat(1024) @(posedge clk); #1;  // 4사이클

        // 전환 2: 20→50
        $display("\n--- [Trans 2] cur=20→50 ---");
        cur = 8'd50;
        repeat(1024) @(posedge clk); #1;

        // 전환 3: 50→20
        $display("\n--- [Trans 3] cur=50→20 ---");
        cur = 8'd20;
        repeat(1024) @(posedge clk); #1;

        // 전환 4: 20→50
        $display("\n--- [Trans 4] cur=20→50 ---");
        cur = 8'd50;
        repeat(1024) @(posedge clk); #1;

        // 전환 5: 50→20
        $display("\n--- [Trans 5] cur=50→20 ---");
        cur = 8'd20;
        repeat(1024) @(posedge clk); #1;

        // 전환 6: 20→50
        $display("\n--- [Trans 6] cur=20→50 ---");
        cur = 8'd50;
        repeat(1024) @(posedge clk); #1;

        // ─────────────────────────────────────────
        // 결과 분석
        // ─────────────────────────────────────────
        $display("\n=== [분석] ===");
        $display("  초반 전환 (Trans 1-2): L3 아직 패턴 미학습");
        $display("  후반 전환 (Trans 5-6): L3 패턴 학습 후");
        $display("");
        $display("  [핵심 관찰]");
        $display("  Trans 5,6에서 A boost > B boost?");
        $display("  A err가 더 빠르게 감소? → 계층 효과 증명");
        $display("  boost=0으로 동일? → 계층 효과 없음");

        $display("\n=== DONE ===");
        $finish;
    end

endmodule
