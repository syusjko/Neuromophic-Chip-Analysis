// =============================================================================
// Testbench: tb_predictive_phase
// 2층 PST 예측 코딩 검증
//
// [실험]
// Layer 1 (감각층): 실제 입력 전류 → phase_neuron → actual_phase
// Layer 2 (예측층): Layer 1 위상을 학습, 예측 생성
//
// [시나리오]
// A. 일정한 입력 패턴 반복 학습
//    입력: cur=50 → phase≈4 (항상 동일)
//    기대: pred_phase가 4로 수렴
//          error_mag 감소 (학습됨)
//
// B. 입력 변화
//    입력 변경: cur=50→cur=20 → phase≈4→phase≈10
//    기대: error_mag 급증 (예측 실패)
//          이후 새 패턴으로 재학습
//
// [측정]
// error_mag가 감소하면 "학습됨" 증명
// error_mag가 변화 후 급증하면 "변화 감지" 증명
// =============================================================================
`timescale 1ns / 1ps

module tb_predictive_phase;

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

    // Layer 1: phase_neuron
    reg [7:0] cur;
    wire       spk_l1;
    wire [7:0] phase_l1;
    wire       fired_l1;

    phase_neuron #(.THRESHOLD(8'd200), .LEAK(8'd0)) l1 (
        .clk(clk), .rst_n(rst_n),
        .global_phase(gphase), .cycle_start(cyc_start),
        .input_current(cur),
        .spike_out(spk_l1),
        .phase_lock(phase_l1),
        .fired_this_cycle(fired_l1)
    );

    // Layer 2: predictive_phase (Layer 1 위상을 학습)
    wire [7:0] err_mag;
    wire       err_sign, err_valid;
    wire [7:0] pred_out;
    wire [7:0] syn_weight;

    predictive_phase #(
        .W_INIT(8'd128),
        .ETA_LTP(8'd4),
        .ETA_LTD(8'd3),
        .WINDOW(8'd30),
        .PRED_GAIN(8'd1)
    ) l2 (
        .clk(clk), .rst_n(rst_n),
        .cycle_start(cyc_start),
        .actual_phase(phase_l1),
        .fired_actual(fired_l1),
        // 초기: 외부 예측 없음 (pred_valid=1, pred_phase_in=128)
        .pred_phase_in(8'd128),
        .pred_valid(1'b1),
        .error_mag(err_mag),
        .error_sign(err_sign),
        .error_valid(err_valid),
        .pred_phase_out(pred_out),
        .weight(syn_weight)
    );

    // 사이클마다 결과 출력
    integer cyc_cnt;
    always @(posedge clk) begin
        if (cyc_start) cyc_cnt = cyc_cnt + 1;

        if (cyc_start && cyc_cnt > 1) begin
            $display("  [Cycle%3d] cur=%3d actual_ph=%3d pred_ph=%3d err=%3d(%s) W=%3d",
                     cyc_cnt, cur, phase_l1, pred_out,
                     err_mag, err_sign ? "slow" : "fast",
                     syn_weight);
        end
    end

    initial begin
        rst_n=0; cyc_cnt=0; cur=0;
        repeat(3) @(posedge clk); #1; rst_n=1;

        // ─────────────────────────────────────────
        // Phase A: cur=50, phase≈4 반복
        // 기대: pred_phase 점점 4로 수렴, error 감소
        // ─────────────────────────────────────────
        $display("=== [Phase A] cur=50 반복 학습 (phase≈4) ===");
        $display("    기대: pred_phase 4로 수렴, error 감소");
        cur = 8'd50;
        repeat(8192) @(posedge clk); #1;  // 32사이클

        // ─────────────────────────────────────────
        // Phase B: cur=20으로 변경 (phase≈10)
        // 기대: error 급증 후 재학습으로 감소
        // ─────────────────────────────────────────
        $display("\n=== [Phase B] cur=50→20 변경 (phase≈10) ===");
        $display("    기대: error 급증(변화 감지) 후 감소(재학습)");
        cur = 8'd20;
        repeat(8192) @(posedge clk); #1;  // 32사이클

        // ─────────────────────────────────────────
        // Phase C: cur=50 복원 (원래 패턴)
        // 기대: 이전에 학습한 패턴이 있으면 빠르게 수렴
        // ─────────────────────────────────────────
        $display("\n=== [Phase C] cur=50 복원 ===");
        $display("    기대: 빠른 재수렴(이전 학습 활용)");
        cur = 8'd50;
        repeat(8192) @(posedge clk); #1;

        $display("\n=== DONE ===");
        $finish;
    end

endmodule
