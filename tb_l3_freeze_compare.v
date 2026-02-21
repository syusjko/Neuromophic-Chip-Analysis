// =============================================================================
// Testbench: tb_l3_freeze_compare
// L3 freeze vs active 비교 → 진짜 계층적 학습 증명
//
// [실험 설계 (GPT 제안)]
//   두 개의 pst_2layer 동시 실행:
//     DUT_A: l3_freeze=0 (L3 active, eta_boost 흐름)
//     DUT_B: l3_freeze=1 (L3 frozen, eta_boost=0)
//
//   동일 입력 → DUT_A가 30%+ 빠르게 수렴하면 계층 효과 증명
//
// [측정]
//   L2 error가 threshold(=5) 이하로 떨어지는 사이클 수 측정
//   DUT_A_conv_cycle vs DUT_B_conv_cycle
//
// [판정 기준]
//   DUT_A < DUT_B × 0.7 → 계층적 학습 증명 (30%+ 빠름)
//   DUT_A ≈ DUT_B       → 효과 없음 (설계 재검토)
// =============================================================================
`timescale 1ns / 1ps

module tb_l3_freeze_compare;

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

    // DUT_A: L3 active (eta_boost 흐름)
    wire [7:0] ph_A, err_A, prd_A, errL3_A, boost_A, W_A;
    wire       f_A, es_A, es3_A;
    wire [7:0] pL3_A, wL3_A;

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

    // DUT_B: L3 frozen (eta_boost=0)
    wire [7:0] ph_B, err_B, prd_B, errL3_B, boost_B, W_B;
    wire       f_B, es_B, es3_B;
    wire [7:0] pL3_B, wL3_B;

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

    // 수렴 사이클 측정
    integer cyc_cnt;
    integer conv_A, conv_B;  // 수렴한 사이클 번호
    localparam CONV_TH = 5;  // err <= 5이면 수렴으로 판정

    always @(posedge clk) begin
        if (cyc_start) cyc_cnt = cyc_cnt + 1;

        // 수렴 감지
        if (cyc_start && conv_A == 0 && err_A <= CONV_TH && cyc_cnt > 2)
            conv_A = cyc_cnt;
        if (cyc_start && conv_B == 0 && err_B <= CONV_TH && cyc_cnt > 2)
            conv_B = cyc_cnt;

        if (cyc_start && cyc_cnt > 1)
            $display("  [C%3d] A(active):pred=%2d err=%2d boost=%2d W=%3d | B(frozen):pred=%2d err=%2d W=%3d",
                cyc_cnt, prd_A, err_A, boost_A, W_A,
                prd_B, err_B, W_B);
    end

    initial begin
        rst_n=0; cyc_cnt=0; conv_A=0; conv_B=0; cur=0;
        repeat(3) @(posedge clk); #1; rst_n=1;

        // ─────────────────────────────────────────
        // Exp 1: 단일 패턴 수렴 속도 비교
        // ─────────────────────────────────────────
        $display("=== [Exp 1] cur=50 (phase=4) ===");
        $display("  A=L3 active, B=L3 frozen");
        $display("  판정: A가 30%+ 빠르면 계층 효과 증명");
        cur = 8'd50;
        repeat(10240) @(posedge clk); #1;  // 40사이클

        $display("\n  [수렴 비교]");
        $display("    A(active): Cycle %0d에서 err<=%0d", conv_A, CONV_TH);
        $display("    B(frozen): Cycle %0d에서 err<=%0d", conv_B, CONV_TH);
        if (conv_A > 0 && conv_B > 0) begin
            if (conv_A < conv_B)
                $display("    → A가 %0d사이클 빠름 (%0d%% 향상)",
                    conv_B-conv_A, (conv_B-conv_A)*100/conv_B);
            else
                $display("    → 차이 없음 (A=%0d, B=%0d)", conv_A, conv_B);
        end

        // ─────────────────────────────────────────
        // Exp 2: 강한 변화 (재적응 속도)
        // ─────────────────────────────────────────
        conv_A=0; conv_B=0;
        $display("\n=== [Exp 2] cur=50→10 (phase 4→20) 재적응 ===");
        $display("  기대: L3 error 급증 → A의 학습률 증폭 → 더 빠른 재수렴");
        cur = 8'd10;
        repeat(10240) @(posedge clk); #1;

        $display("\n  [재적응 비교]");
        $display("    A(active): Cycle %0d에서 재수렴", conv_A);
        $display("    B(frozen): Cycle %0d에서 재수렴", conv_B);
        if (conv_A > 0 && conv_B > 0 && conv_A < conv_B)
            $display("    → 계층적 학습 효과 증명! A가 %0d%% 빠름",
                (conv_B-conv_A)*100/conv_B);
        else
            $display("    → 효과 미미");

        $display("\n=== DONE ===");
        $finish;
    end

endmodule
