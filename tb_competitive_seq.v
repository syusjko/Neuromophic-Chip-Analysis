// =============================================================================
// Testbench: tb_competitive_seq
// WTA + Sequence STDP 검증
//
// [검증 순서]
// 1. 단일 패턴: slot 중 하나가 패턴 전문화
// 2. 두 패턴: slot[0]≈1, slot[1]≈40으로 WTA 분리
// 3. 시퀀스 학습: w_seq[0→1], w_seq[1→0] 강화
// 4. 예측 확인: cur=5(40) 도착 전, pred_next가 이미 40 가리키나?
// =============================================================================
`timescale 1ns / 1ps

module tb_competitive_seq;

    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    wire [7:0] gphase; wire cyc_start;
    gamma_oscillator #(.CYCLE_LEN(9'd256)) osc (
        .clk(clk),.rst_n(rst_n),.phase_out(gphase),.cycle_start(cyc_start)
    );

    reg [7:0]  actual_ph;
    reg        fired_in;
    integer    cyc_cnt;
    always @(posedge clk) if (cyc_start) cyc_cnt = cyc_cnt + 1;

    wire [7:0] pred_nx;
    wire [7:0] err_out;
    wire       err_vld;
    wire [1:0] winner;
    wire [7:0] s0, s1, s2, s3;

    competitive_seq_pred #(
        .N_SLOTS(4), .W_INIT(8'd128),
        .ETA_SLOT(8'd8), .ETA_SEQ(8'd4)
    ) DUT (
        .clk(clk), .rst_n(rst_n),
        .cycle_start(cyc_start),
        .actual_phase(actual_ph),
        .fired(fired_in),
        .pred_next(pred_nx),
        .error_out(err_out),
        .error_valid(err_vld),
        .winner_out(winner),
        .slot0_out(s0), .slot1_out(s1),
        .slot2_out(s2), .slot3_out(s3)
    );

    // 매 gamma 사이클마다 phase_neuron을 흉내내서 fired 생성
    // cur에서 phase가 결정되고 그 사이클에 발화
    reg [7:0] cur;
    wire [7:0] ph_out;
    wire       f_out;
    phase_neuron #(.THRESHOLD(8'd200),.LEAK(8'd0)) PN (
        .clk(clk),.rst_n(rst_n),
        .global_phase(gphase),.cycle_start(cyc_start),
        .input_current(cur),
        .spike_out(),.phase_lock(ph_out),.fired_this_cycle(f_out)
    );

    always @(*) begin
        actual_ph = ph_out;
        fired_in  = f_out;
    end

    always @(posedge clk) begin
        if (cyc_start && cyc_cnt > 1)
            $display("  [C%3d] cur=%3d ph=%2d | pred=%2d err=%2d W=%0d | s0=%2d s1=%2d s2=%2d s3=%2d",
                cyc_cnt, cur, ph_out,
                pred_nx, err_out, winner,
                s0, s1, s2, s3);
    end

    initial begin
        rst_n=0; cyc_cnt=0; cur=0;
        repeat(3) @(posedge clk); #1; rst_n=1;

        // ── Exp 1: 단일 패턴 학습 (cur=200, ph=1) ────────────────────
        $display("=== [Exp 1] 단일 패턴 (cur=200, ph=1) 10사이클 ===");
        $display("  기대: slot 중 하나가 1로 전문화, 나머지 유지");
        cur = 8'd200;
        repeat(2560) @(posedge clk); #1;
        $display("  완료: s0=%0d s1=%0d s2=%0d s3=%0d winner=%0d",
                 s0,s1,s2,s3,winner);

        // ── Exp 2: 두 번째 패턴 도입 (cur=5, ph=40) ──────────────────
        $display("\n=== [Exp 2] 두 번째 패턴 (cur=5, ph=40) 10사이클 ===");
        $display("  기대: 다른 slot이 40으로 전문화 (WTA 분리)");
        cur = 8'd5;
        repeat(2560) @(posedge clk); #1;
        $display("  완료: s0=%0d s1=%0d s2=%0d s3=%0d winner=%0d",
                 s0,s1,s2,s3,winner);

        // ── Exp 3: 교번 패턴 (시퀀스 학습) ──────────────────────────
        $display("\n=== [Exp 3] 교번 패턴으로 시퀀스 학습 ===");
        $display("  기대: w_seq[A→B] 강화, pred_next가 미래 패턴 가리킴");
        $display("  col: [C] cur ph pred err W s0 s1 s2 s3");

        cur = 8'd200;
        repeat(1024) @(posedge clk); #1;

        cur = 8'd5;
        repeat(1024) @(posedge clk); #1;

        cur = 8'd200;
        repeat(1024) @(posedge clk); #1;

        cur = 8'd5;
        repeat(1024) @(posedge clk); #1;

        cur = 8'd200;
        repeat(1024) @(posedge clk); #1;

        cur = 8'd5;
        repeat(1024) @(posedge clk); #1;

        // ── Exp 4: 예측 선행 검증 ─────────────────────────────────────
        $display("\n=== [Exp 4] 예측 선행 확인 ===");
        $display("  cur=200 (ph=1) 유지 중에 pred_next가 40을 가리키는가?");
        $display("  = '곧 cur=5가 올 것'을 미리 예측");
        cur = 8'd200;
        repeat(512) @(posedge clk); #1;

        $display("\n  [Exp 4 결과]");
        $display("  cur=200(ph=1) 상태에서: pred_next=%0d", pred_nx);
        $display("  s0=%0d s1=%0d s2=%0d s3=%0d", s0,s1,s2,s3);
        if (pred_nx > 20)
            $display("  -> pred_next=%0d > 20: 다음 패턴(40) 예측 성공!", pred_nx);
        else
            $display("  -> pred_next=%0d: 예측 실패 또는 학습 부족", pred_nx);

        $display("\n=== DONE ===");
        $finish;
    end
endmodule
