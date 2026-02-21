// =============================================================================
// Testbench: tb_phase_stdp
//
// [검증 시나리오]
// 1. pre 먼저 발화 (인과적) → 가중치 증가 확인
// 2. post 먼저 발화 (비인과적) → 가중치 감소 확인
// 3. 동시 발화 (Δphase=0) → 변화 없음 확인
// 4. 윈도우 밖 (|Δphase|>30) → 변화 없음 확인
// 5. 반복 LTP → 포화 (W_MAX=255) 확인
// 6. 반복 LTD → 하한 (W_MIN=1) 확인
//
// [기대 결과]
// 시나리오 1: weight 128 → 132 (+4) ✅
// 시나리오 2: weight 132 → 129 (-3) ✅
// 시나리오 3: weight 변화 없음 ✅
// 시나리오 4: weight 변화 없음 ✅
// 시나리오 5: 반복 후 255 (포화) ✅
// 시나리오 6: 반복 후 1 (하한) ✅
// =============================================================================
`timescale 1ns / 1ps

module tb_phase_stdp;

    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    // 감마 오실레이터 (256클럭 사이클)
    wire [7:0] gphase;
    wire       cyc_start;
    gamma_oscillator #(.CYCLE_LEN(9'd256)) osc (
        .clk(clk), .rst_n(rst_n),
        .phase_out(gphase), .cycle_start(cyc_start)
    );

    // STDP 입력
    reg [7:0] ph_pre, ph_post;
    reg       f_pre,  f_post;

    // STDP 모듈
    wire [7:0] weight;
    wire       ltp_ev, ltd_ev;

    phase_stdp #(
        .W_INIT(8'd128),
        .ETA_LTP(8'd4),
        .ETA_LTD(8'd3),
        .WINDOW(8'd30)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .cycle_start(cyc_start),
        .phase_pre(ph_pre),   .phase_post(ph_post),
        .fired_pre(f_pre),    .fired_post(f_post),
        .weight(weight),
        .ltp_event(ltp_ev),   .ltd_event(ltd_ev)
    );

    // 결과 출력
    always @(posedge clk) begin
        if (cyc_start) begin
            $display("  [cyc] weight=%3d ltp=%b ltd=%b | ph_pre=%3d ph_post=%3d f=%b%b",
                     weight, ltp_ev, ltd_ev, ph_pre, ph_post, f_pre, f_post);
        end
    end

    integer i;
    initial begin
        rst_n=0; ph_pre=0; ph_post=0; f_pre=0; f_post=0;
        repeat(3) @(posedge clk); #1; rst_n=1;
        repeat(2) @(posedge clk); #1; // 안정화

        // ─────────────────────────────────────────
        // 시나리오 1: LTP (pre=5, post=20 → pre 먼저)
        // Δphase=15, WINDOW=30 안 → LTP 발생
        // ─────────────────────────────────────────
        $display("\n=== [Scenario 1] LTP: pre=phase5 먼저, post=phase20 ===");
        $display("    기대: weight 128 → 132 (+4)");
        ph_pre=8'd5; ph_post=8'd20; f_pre=1; f_post=1;
        repeat(512) @(posedge clk); #1;
        $display("    최종 weight = %0d", weight);

        // ─────────────────────────────────────────
        // 시나리오 2: LTD (pre=20, post=5 → post 먼저)
        // ─────────────────────────────────────────
        $display("\n=== [Scenario 2] LTD: post=phase5 먼저, pre=phase20 ===");
        $display("    기대: weight 감소 (-3/cycle)");
        ph_pre=8'd20; ph_post=8'd5; f_pre=1; f_post=1;
        repeat(512) @(posedge clk); #1;
        $display("    최종 weight = %0d", weight);

        // ─────────────────────────────────────────
        // 시나리오 3: 동시 발화 (Δphase=0)
        // ─────────────────────────────────────────
        $display("\n=== [Scenario 3] 동시 발화: ph_pre=ph_post=10 ===");
        $display("    기대: weight 변화 없음");
        ph_pre=8'd10; ph_post=8'd10; f_pre=1; f_post=1;
        repeat(512) @(posedge clk); #1;
        $display("    최종 weight = %0d", weight);

        // ─────────────────────────────────────────
        // 시나리오 4: 윈도우 밖 (|Δphase|=50 > WINDOW=30)
        // ─────────────────────────────────────────
        $display("\n=== [Scenario 4] 윈도우 밖: ph_pre=0, ph_post=50 ===");
        $display("    기대: weight 변화 없음");
        ph_pre=8'd0; ph_post=8'd50; f_pre=1; f_post=1;
        repeat(512) @(posedge clk); #1;
        $display("    최종 weight = %0d", weight);

        // ─────────────────────────────────────────
        // 시나리오 5: 반복 LTP → 포화
        // ─────────────────────────────────────────
        $display("\n=== [Scenario 5] 반복 LTP → 포화(255) ===");
        ph_pre=8'd1; ph_post=8'd10; f_pre=1; f_post=1;
        repeat(16384) @(posedge clk); #1;  // 64사이클 → 충분히 포화
        $display("    최종 weight = %0d (기대: 255)", weight);

        // ─────────────────────────────────────────
        // 시나리오 6: 반복 LTD → 하한
        // ─────────────────────────────────────────
        $display("\n=== [Scenario 6] 반복 LTD → 하한(1) ===");
        ph_pre=8'd10; ph_post=8'd1; f_pre=1; f_post=1;
        repeat(16384) @(posedge clk); #1;  // 64사이클 → 충분히 하한
        $display("    최종 weight = %0d (기대: 1)", weight);

        // ─────────────────────────────────────────
        // 시나리오 7: 발화 없음 → 변화 없음
        // ─────────────────────────────────────────
        $display("\n=== [Scenario 7] 발화 없음 ===");
        ph_pre=8'd5; ph_post=8'd20; f_pre=0; f_post=0;
        repeat(512) @(posedge clk); #1;
        $display("    최종 weight = %0d (기대: 1, 변화 없음)", weight);

        $display("\n=== DONE ===");
        $finish;
    end

endmodule
