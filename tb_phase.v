// =============================================================================
// Module  : tb_phase (v2 - 올바른 파라미터)
// Description : Phase-based Attention 검증
//
// [v2 수정]
//   핵심 원리 재정립:
//   
//   위상 코딩의 동작 조건:
//     input_current << THRESHOLD 여야 함
//     → 여러 클럭 누적 후 발화
//     → 강한 입력 = 빨리 누적 = 낮은 위상
//     → 약한 입력 = 천천히 누적 = 높은 위상
//
//   파라미터:
//     THRESHOLD = 200 (높게)
//     입력 범위 = 1~50 (낮게)
//     → 4~200 클럭 후 발화 → 위상 차이 명확
//
//   [예시]
//   input=50: 200/50 = 4클럭 후 발화 → phase≈4
//   input=10: 200/10 = 20클럭 후 발화 → phase≈20
//   input=2:  200/2  = 100클럭 후 발화 → phase≈100
//   input=1:  200/1  = 200클럭 후 발화 → phase≈200
//   input=0:  발화 안 함
// =============================================================================
`timescale 1ns / 1ps

module tb_phase;

    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    wire [7:0] gphase;
    wire       cyc_start;

    gamma_oscillator #(.CYCLE_LEN(9'd256)) osc (
        .clk(clk), .rst_n(rst_n),
        .phase_out(gphase), .cycle_start(cyc_start)
    );

    // THRESHOLD=200, LEAK=0, 입력은 소전류
    reg [7:0] cur_a, cur_b, cur_c;
    wire spk_a, spk_b, spk_c;
    wire [7:0] ph_a, ph_b, ph_c;
    wire fired_a, fired_b, fired_c;

    phase_neuron #(.THRESHOLD(8'd200), .LEAK(8'd0), .CYCLE_LEN(8'd255)) nA (
        .clk(clk), .rst_n(rst_n), .global_phase(gphase), .cycle_start(cyc_start),
        .input_current(cur_a), .spike_out(spk_a),
        .phase_lock(ph_a), .fired_this_cycle(fired_a));

    phase_neuron #(.THRESHOLD(8'd200), .LEAK(8'd0), .CYCLE_LEN(8'd255)) nB (
        .clk(clk), .rst_n(rst_n), .global_phase(gphase), .cycle_start(cyc_start),
        .input_current(cur_b), .spike_out(spk_b),
        .phase_lock(ph_b), .fired_this_cycle(fired_b));

    phase_neuron #(.THRESHOLD(8'd200), .LEAK(8'd0), .CYCLE_LEN(8'd255)) nC (
        .clk(clk), .rst_n(rst_n), .global_phase(gphase), .cycle_start(cyc_start),
        .input_current(cur_c), .spike_out(spk_c),
        .phase_lock(ph_c), .fired_this_cycle(fired_c));

    // A vs B
    wire [7:0] rel_ab; wire coin_ab;
    coincidence_detector #(.PHASE_TOL(8'd20)) cd_ab (
        .clk(clk), .rst_n(rst_n),
        .fired_a(fired_a), .fired_b(fired_b),
        .phase_a(ph_a), .phase_b(ph_b),
        .cycle_start(cyc_start),
        .relevance(rel_ab), .coincident(coin_ab));

    // A vs C
    wire [7:0] rel_ac; wire coin_ac;
    coincidence_detector #(.PHASE_TOL(8'd20)) cd_ac (
        .clk(clk), .rst_n(rst_n),
        .fired_a(fired_a), .fired_b(fired_c),
        .phase_a(ph_a), .phase_b(ph_c),
        .cycle_start(cyc_start),
        .relevance(rel_ac), .coincident(coin_ac));

    // Result output
    reg [7:0] diff_ab, diff_ac, rel_ab_now, rel_ac_now;
    wire fa = (ph_a != 8'd255);  // fired if phase_lock != 255 (default)
    wire fb = (ph_b != 8'd255);
    wire fc = (ph_c != 8'd255);

    always @(posedge clk) begin
        if (spk_a) $display("  [A fired] phase=%3d", gphase);
        if (spk_b) $display("  [B fired] phase=%3d", gphase);
        if (spk_c) $display("  [C fired] phase=%3d", gphase);

        if (gphase == 8'd254) begin
            // circular diff A-B
            diff_ab = (ph_a >= ph_b) ? (ph_a - ph_b) : (ph_b - ph_a);
            if (diff_ab > 8'd128) diff_ab = 8'd255 - diff_ab;
            rel_ab_now = 8'd255 - diff_ab;

            // circular diff A-C
            diff_ac = (ph_a >= ph_c) ? (ph_a - ph_c) : (ph_c - ph_a);
            if (diff_ac > 8'd128) diff_ac = 8'd255 - diff_ac;
            rel_ac_now = 8'd255 - diff_ac;

            $display("  [cycle] phA=%3d(f=%b) phB=%3d(f=%b) phC=%3d(f=%b)",
                     ph_a, fa, ph_b, fb, ph_c, fc);
            if (fa && fb)
                $display("    A vs B: diff=%3d  Rel=%3d  Coin=%b  [%s]",
                    diff_ab, rel_ab_now,
                    (diff_ab <= 8'd20) ? 1'b1 : 1'b0,
                    (diff_ab <= 8'd20) ? "RELATED" : "UNRELATED");
            if (fa && fc)
                $display("    A vs C: diff=%3d  Rel=%3d  Coin=%b  [%s]",
                    diff_ac, rel_ac_now,
                    (diff_ac <= 8'd20) ? 1'b1 : 1'b0,
                    (diff_ac <= 8'd20) ? "RELATED" : "UNRELATED");
        end
    end


    initial begin
        $dumpfile("phase_dump.vcd");
        $dumpvars(0, tb_phase);
        rst_n=0; cur_a=0; cur_b=0; cur_c=0;
        repeat(3) @(posedge clk); #1; rst_n=1;

        // ─────────────────────────────────────────────────────
        // [Test 1] A=강(50/사이클) vs B=강(45/사이클)
        //   → 둘 다 위상 초반 발화 → 관련성 높음
        // ─────────────────────────────────────────────────────
        $display("\n=== [Test 1] A=50(강) vs B=45(강) → 관련성 높음 기대 ===");
        $display("  예상: A≈phase4, B≈phase4 → Rel 높음");
        cur_a=8'd50; cur_b=8'd45; cur_c=8'd0;
        repeat(512) @(posedge clk); #1;

        // ─────────────────────────────────────────────────────
        // [Test 2] A=강(50) vs C=약(5)
        //   → A는 위상 4, C는 위상 40 → 관련성 낮음
        // ─────────────────────────────────────────────────────
        $display("\n=== [Test 2] A=50(강) vs C=5(약) → 관련성 낮음 기대 ===");
        $display("  예상: A≈phase4, C≈phase40 → Rel 낮음");
        cur_a=8'd50; cur_b=8'd0; cur_c=8'd5;
        repeat(512) @(posedge clk); #1;

        // ─────────────────────────────────────────────────────
        // [Test 3] A=중(20) vs B=중(22)
        //   → 비슷한 위상 → 관련성 높음
        // ─────────────────────────────────────────────────────
        $display("\n=== [Test 3] A=20(중) vs B=22(중) → 관련성 높음 기대 ===");
        $display("  예상: A≈phase10, B≈phase9 → Rel 높음");
        cur_a=8'd20; cur_b=8'd22; cur_c=8'd0;
        repeat(512) @(posedge clk); #1;

        // ─────────────────────────────────────────────────────
        // [Test 4] A=강(50) vs B=약(5) → 관련성 낮음
        // ─────────────────────────────────────────────────────
        $display("\n=== [Test 4] A=50(강) vs B=5(약) → 관련성 낮음 기대 ===");
        $display("  예상: A≈phase4, B≈phase40 → Rel 낮음");
        cur_a=8'd50; cur_b=8'd5; cur_c=8'd0;
        repeat(512) @(posedge clk); #1;

        $display("\n=== [완료] ===");
        $finish;
    end

endmodule
