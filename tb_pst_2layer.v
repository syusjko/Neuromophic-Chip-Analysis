// =============================================================================
// Testbench: tb_pst_2layer
// 2층 예측 코딩 PST 검증
//
// [핵심 질문]
// "계층적 학습이 단층보다 빠른가?"
// "L3 top-down이 L2 학습을 가속하는가?"
//
// [실험 설계]
// 비교 A: pst_2layer (L2+L3)
// 비교 B: predictive_phase 단층 (L2만)
// 동일 입력 → 수렴 속도 비교
//
// [시나리오]
// 1. 단일 패턴: cur=50 (phase≈4)
//    → L2 pred: 4로 수렴
//    → L3 pred: L2 예측 패턴(4) 예측 → 4로 수렴
//
// 2. 교번 패턴: cur=50(even), cur=20(odd)
//    → L2: phase 4↔10 교번 예측 어려움
//    → L3: L2가 흔들리는 패턴 감지
//
// 3. 입력 변화: cur=50 → cur=100 (phase 4→2)
//    → L2: error 감지, 재수렴
//    → L3: L2 오차 패턴 변화 감지
//    → L3 top-down이 L2 수렴 돕는가?
// =============================================================================
`timescale 1ns / 1ps

module tb_pst_2layer;

    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    // 감마 오실레이터
    wire [7:0] gphase;
    wire       cyc_start;
    gamma_oscillator #(.CYCLE_LEN(9'd256)) osc (
        .clk(clk), .rst_n(rst_n),
        .phase_out(gphase), .cycle_start(cyc_start)
    );

    // 입력
    reg [7:0] cur;

    // 2층 PST
    wire [7:0] ph_L1;
    wire       f_L1;
    wire [7:0] pred_L2, err_L2, pred_L3, err_L3;
    wire       esign_L2, esign_L3;
    wire [7:0] W_L2, W_L3;

    pst_2layer #(
        .THRESHOLD(8'd200),
        .W_INIT(8'd128),
        .ETA_LTP(8'd4),
        .ETA_LTD(8'd3),
        .WINDOW(8'd128)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .cycle_start(cyc_start),
        .global_phase(gphase),
        .input_current(cur),
        .phase_L1(ph_L1),    .fired_L1(f_L1),
        .pred_L2(pred_L2),   .error_L2(err_L2),
        .err_sign_L2(esign_L2), .weight_L2(W_L2),
        .pred_L3(pred_L3),   .error_L3(err_L3),
        .err_sign_L3(esign_L3), .weight_L3(W_L3)
    );

    // 단층 비교 (L2만, top-down 없음)
    wire [7:0] pred_SL, err_SL, W_SL;
    wire       esign_SL, eval_SL;

    predictive_phase #(
        .W_INIT(8'd128),
        .ETA_LTP(8'd4),
        .ETA_LTD(8'd3),
        .WINDOW(8'd128)
    ) single_layer (
        .clk(clk), .rst_n(rst_n),
        .cycle_start(cyc_start),
        .actual_phase(ph_L1),
        .fired_actual(f_L1),
        .pred_phase_in(8'd128),  // top-down 없음
        .pred_valid(1'b1),
        .error_mag(err_SL),
        .error_sign(esign_SL),
        .error_valid(eval_SL),
        .pred_phase_out(pred_SL),
        .weight(W_SL)
    );

    integer cyc_cnt;
    always @(posedge clk) begin
        if (cyc_start) cyc_cnt = cyc_cnt + 1;
        if (cyc_start && cyc_cnt > 1) begin
            $display("  [C%3d] cur=%3d ph=%2d | L2:pred=%2d err=%2d(%s) W=%3d | L3:pred=%2d err=%2d W=%3d | SL:pred=%2d err=%2d W=%3d",
                cyc_cnt, cur, ph_L1,
                pred_L2, err_L2, esign_L2?"slow":"fast", W_L2,
                pred_L3, err_L3, W_L3,
                pred_SL, err_SL, W_SL);
        end
    end

    initial begin
        rst_n=0; cyc_cnt=0; cur=0;
        repeat(3) @(posedge clk); #1; rst_n=1;

        // ─────────────────────────────────────
        // 실험 1: 단일 패턴 학습
        // 2층 vs 단층 수렴 속도 비교
        // ─────────────────────────────────────
        $display("=== [Exp 1] 단일 패턴: cur=50 (phase≈4) ===");
        $display("  비교: 2층(L2) vs 단층(SL)");
        $display("  기대: 2층이 더 빠르게 수렴 (L3 top-down 도움)");
        cur = 8'd50;
        repeat(8192) @(posedge clk); #1;  // 32사이클

        // ─────────────────────────────────────
        // 실험 2: 입력 변화 → 재적응 비교
        // ─────────────────────────────────────
        $display("\n=== [Exp 2] 입력 변화: cur=50→100 (phase 4→2) ===");
        $display("  기대: 2층이 변화 더 빠르게 감지/재수렴");
        cur = 8'd100;
        repeat(8192) @(posedge clk); #1;

        // ─────────────────────────────────────
        // 실험 3: 강한 입력 변화 cur=100→10
        // ─────────────────────────────────────
        $display("\n=== [Exp 3] 강한 변화: cur=100→10 (phase 2→20) ===");
        $display("  기대: L3 error 강한 오차 신호 → L2 학습 가속");
        cur = 8'd10;
        repeat(8192) @(posedge clk); #1;

        $display("\n=== DONE ===");
        $finish;
    end

endmodule
