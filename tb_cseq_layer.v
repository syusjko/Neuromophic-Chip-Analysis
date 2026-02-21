// =============================================================================
// Testbench: tb_cseq_layer
// competitive_seq L3가 연결된 2층 구조의 계층 효과 측정
//
// [실험]
//   A: L3(competitive_seq) active → L2에 미래 패턴 top-down
//   B: L3 frozen → L2 단독
//
// [핵심 측정]
//   L3가 "다음 패턴"을 학습한 후:
//   실제 전환 발생 전/중에 A의 L2가 더 빠르게 수렴하는가?
//   = L3의 pred_next가 L2를 미리 당기는 효과
// =============================================================================
`timescale 1ns / 1ps

module tb_cseq_layer;

    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    wire [7:0] gphase; wire cyc_start;
    gamma_oscillator #(.CYCLE_LEN(9'd256)) osc (
        .clk(clk),.rst_n(rst_n),.phase_out(gphase),.cycle_start(cyc_start)
    );

    reg [7:0] cur;
    integer cyc_cnt;
    always @(posedge clk) if (cyc_start) cyc_cnt = cyc_cnt + 1;

    // DUT_A: L3 active
    wire [7:0] phA,predA,errA,wA,pL3A,eL3A,s0A,s1A,s2A,s3A;
    wire [1:0] winA;
    wire       fA;
    pst_2layer_cseq #(
        .THRESHOLD(8'd200),.W_INIT(8'd128),
        .ETA_LTP(8'd4),.ETA_LTD(8'd3),
        .WINDOW(8'd128),.ETA_SLOT(8'd8),.ETA_SEQ(8'd4)
    ) DUT_A (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.global_phase(gphase),
        .input_current(cur),.l3_freeze(1'b0),
        .phase_L1(phA),.fired_L1(fA),
        .pred_L2(predA),.error_L2(errA),.weight_L2(wA),
        .pred_L3_next(pL3A),.error_L3(eL3A),.winner_L3(winA),
        .slot0_L3(s0A),.slot1_L3(s1A),.slot2_L3(s2A),.slot3_L3(s3A)
    );

    // DUT_B: L3 frozen
    wire [7:0] phB,predB,errB,wB,pL3B,eL3B,s0B,s1B,s2B,s3B;
    wire [1:0] winB;
    wire       fB;
    pst_2layer_cseq #(
        .THRESHOLD(8'd200),.W_INIT(8'd128),
        .ETA_LTP(8'd4),.ETA_LTD(8'd3),
        .WINDOW(8'd128),.ETA_SLOT(8'd8),.ETA_SEQ(8'd4)
    ) DUT_B (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.global_phase(gphase),
        .input_current(cur),.l3_freeze(1'b1),
        .phase_L1(phB),.fired_L1(fB),
        .pred_L2(predB),.error_L2(errB),.weight_L2(wB),
        .pred_L3_next(pL3B),.error_L3(eL3B),.winner_L3(winB),
        .slot0_L3(s0B),.slot1_L3(s1B),.slot2_L3(s2B),.slot3_L3(s3B)
    );

    integer a_lat[1:6], b_lat[1:6], t;

    task do_trans;
        input [7:0] new_cur;
        input integer tnum, maxc;
        integer st, i, ad, bd;
        begin
            cur = new_cur;
            st = cyc_cnt; ad = 0; bd = 0;
            $display("\n--- [Trans %0d] cur->%0d (ph~%0d) ---",
                tnum, new_cur, (new_cur==8'd200)?1:40);
            for (i=0; i<maxc; i=i+1) begin
                repeat(256) @(posedge clk); #1;
                $display("  [C%3d] ph=%2d | A:pred=%2d err=%2d L3nx=%2d W=%0d | B:pred=%2d err=%2d",
                    cyc_cnt, phA, predA, errA, pL3A, winA, predB, errB);
                if (ad==0 && errA<=5) ad = cyc_cnt - st;
                if (bd==0 && errB<=5) bd = cyc_cnt - st;
            end
            a_lat[tnum] = (ad>0)?ad:maxc;
            b_lat[tnum] = (bd>0)?bd:maxc;
            $display("  -> A=%0d사이클 B=%0d사이클 %s",
                a_lat[tnum], b_lat[tnum],
                (ad<bd && ad>1)?"[A FASTER!]":"");
        end
    endtask

    initial begin
        rst_n=0; cyc_cnt=0; cur=0;
        for(t=1;t<=6;t=t+1) begin a_lat[t]=99; b_lat[t]=99; end
        repeat(3) @(posedge clk); #1; rst_n=1;

        // Phase 1: 두 패턴 학습 (L3가 WTA 분리 완료까지)
        $display("=== [Phase 1] 두 패턴 WTA 학습 ===");
        $display("  cur=200(10cyc) → cur=5(10cyc) → cur=200(10cyc) 반복");
        cur = 8'd200; repeat(2560) @(posedge clk); #1;
        cur = 8'd5;   repeat(2560) @(posedge clk); #1;
        cur = 8'd200; repeat(2560) @(posedge clk); #1;
        cur = 8'd5;   repeat(2560) @(posedge clk); #1;

        $display("  WTA 완료: A s0=%0d s1=%0d s2=%0d s3=%0d",s0A,s1A,s2A,s3A);
        $display("  L3 pred_next 학습 완료 예상");

        // Phase 2: 전환 속도 비교
        $display("\n=== [Phase 2] 전환 속도 비교 (A active vs B frozen) ===");
        $display("  L3가 학습 완료 후: A가 먼저 도착하는가?");

        do_trans(8'd200, 1, 10);
        repeat(2560) @(posedge clk); #1;
        do_trans(8'd5,   2, 10);
        repeat(2560) @(posedge clk); #1;
        do_trans(8'd200, 3, 10);
        repeat(2560) @(posedge clk); #1;
        do_trans(8'd5,   4, 10);
        repeat(2560) @(posedge clk); #1;
        do_trans(8'd200, 5, 10);
        repeat(2560) @(posedge clk); #1;
        do_trans(8'd5,   6, 10);

        $display("\n=== 최종 결과 ===");
        $display("Trans | A수렴 | B수렴 | 향상");
        for(t=1;t<=6;t=t+1)
            $display("  %0d   |  %2d   |  %2d   | %s",
                t,a_lat[t],b_lat[t],
                (a_lat[t]<b_lat[t])?"[계층 효과!]":"same");

        $display("\n[판정]");
        if (a_lat[3]<b_lat[3] || a_lat[4]<b_lat[4])
            $display("  계층 효과 증명! Competitive seq L3가 L2를 가속");
        else
            $display("  아직 효과 미흡");

        $finish;
    end
endmodule
