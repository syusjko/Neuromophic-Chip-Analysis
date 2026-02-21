// =============================================================================
// Testbench: tb_seq2 v4 - 정밀 측정 + ASCII 출력
// GPT 제안 반영:
//   1. ASCII 문자열만 사용 (한국어 깨짐 방지)
//   2. 정밀 타이밍: trans_detect, force_valid 사이클, hit 사이클 표시
//   3. 측정 시작점 명확화: cur 변경 다음 첫 fired 사이클부터
// =============================================================================
`timescale 1ns / 1ps

module tb_seq2;

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

    // L1
    wire [7:0] ph_L1; wire f_L1;
    phase_neuron #(.THRESHOLD(8'd200),.LEAK(8'd0)) L1 (
        .clk(clk),.rst_n(rst_n),
        .global_phase(gphase),.cycle_start(cyc_start),
        .input_current(cur),
        .spike_out(),.phase_lock(ph_L1),.fired_this_cycle(f_L1)
    );

    // seq2 L3
    wire [7:0] force_px, err_s, sA, sB;
    wire       force_vld, last_w;
    seq2_predictor #(.SLOT_A_INIT(8'd5),.SLOT_B_INIT(8'd50),.ETA(8'd8)) L3 (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),
        .actual_phase(ph_L1),.fired(f_L1),
        .force_pred(force_px),.force_valid(force_vld),
        .slot_A(sA),.slot_B(sB),.last_winner(last_w),.error_out(err_s)
    );

    // DUT_A: injection
    wire [7:0] predA,errA,wA,bA;
    wire sA1,vA;
    predictive_phase #(.W_INIT(8'd128),.ETA_LTP(8'd4),.ETA_LTD(8'd3),.WINDOW(8'd128)) L2_A (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),
        .actual_phase(ph_L1),.fired_actual(f_L1),
        .pred_phase_in(8'd0),.pred_valid(1'b0),.eta_boost_in(8'd0),
        .force_pred(force_px),.force_valid(force_vld),
        .error_mag(errA),.error_sign(sA1),.error_valid(vA),
        .pred_phase_out(predA),.weight(wA),.eta_boost_out(bA)
    );

    // DUT_B: no injection
    wire [7:0] predB,errB,wB,bB;
    wire sB1,vB;
    predictive_phase #(.W_INIT(8'd128),.ETA_LTP(8'd4),.ETA_LTD(8'd3),.WINDOW(8'd128)) L2_B (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),
        .actual_phase(ph_L1),.fired_actual(f_L1),
        .pred_phase_in(8'd0),.pred_valid(1'b0),.eta_boost_in(8'd0),
        .force_pred(8'd0),.force_valid(1'b0),
        .error_mag(errB),.error_sign(sB1),.error_valid(vB),
        .pred_phase_out(predB),.weight(wB),.eta_boost_out(bB)
    );

    integer a_lat[1:6], b_lat[1:6], t;
    integer a_hit[1:6], b_hit[1:6];  // 실제 수렴 cyc 번호

    task do_trans;
        input [7:0] nc; input integer tn, mx;
        integer st, i, ad, bd;
        reg    fv_seen;
        begin
            cur=nc; st=cyc_cnt; ad=0; bd=0; fv_seen=0;
            $display("\n--- [Trans %0d] cur=%0d (ph~%0d) sA=%0d sB=%0d frc=%0d ---",
                tn, nc, (nc==8'd200)?1:40, sA, sB, force_px);
            $display("         | A:pred err | B:pred err | frc fvld | note");
            for (i=0; i<mx; i=i+1) begin
                repeat(256) @(posedge clk); #1;
                $display("  [C%3d] | A:%2d   %2d  | B:%2d   %2d  | %2d  %0d   | %s%s%s",
                    cyc_cnt,
                    predA, errA, predB, errB,
                    force_px, force_vld,
                    (force_vld && !fv_seen) ? "INJECT!" : "",
                    (ad==0 && errA<=3 && cyc_cnt>st+1) ? " A_HIT" : "",
                    (bd==0 && errB<=3 && cyc_cnt>st+1) ? " B_HIT" : "");
                if (force_vld) fv_seen = 1;
                if (ad==0 && errA<=3 && cyc_cnt>st+1) begin
                    ad=cyc_cnt-st; a_hit[tn]=cyc_cnt;
                end
                if (bd==0 && errB<=3 && cyc_cnt>st+1) begin
                    bd=cyc_cnt-st; b_hit[tn]=cyc_cnt;
                end
            end
            a_lat[tn]=(ad>0)?ad:mx;
            b_lat[tn]=(bd>0)?bd:mx;
            $display("  -> A=%0d cyc (hit@C%0d)  B=%0d cyc (hit@C%0d)  %s",
                a_lat[tn], a_hit[tn],
                b_lat[tn], b_hit[tn],
                (a_lat[tn]<b_lat[tn]) ? "[A FASTER]" : "SAME");
        end
    endtask

    initial begin
        rst_n=0; cyc_cnt=0; cur=0;
        for(t=1;t<=6;t=t+1) begin
            a_lat[t]=99; b_lat[t]=99;
            a_hit[t]=0;  b_hit[t]=0;
        end
        repeat(3) @(posedge clk); #1; rst_n=1;

        $display("=== [Phase 1] WTA learning ===");
        cur=8'd200; repeat(7680) @(posedge clk); #1;
        cur=8'd5;   repeat(7680) @(posedge clk); #1;
        cur=8'd200; repeat(7680) @(posedge clk); #1;
        cur=8'd5;   repeat(7680) @(posedge clk); #1;
        $display("  Done: sA=%0d(target=1) sB=%0d(target=40)", sA, sB);

        $display("\n=== [Phase 2] Convergence speed comparison ===");
        $display("  A=injection  B=standalone  threshold: err<=3");

        do_trans(8'd200,1,12); repeat(7680) @(posedge clk); #1;
        do_trans(8'd5,  2,12); repeat(7680) @(posedge clk); #1;
        do_trans(8'd200,3,12); repeat(7680) @(posedge clk); #1;
        do_trans(8'd5,  4,12); repeat(7680) @(posedge clk); #1;
        do_trans(8'd200,5,12); repeat(7680) @(posedge clk); #1;
        do_trans(8'd5,  6,12);

        $display("\n=== FINAL RESULTS ===");
        $display("Trans | A(inj) | B(solo) | Speedup | Verdict");
        for(t=1;t<=6;t=t+1) begin
            $display("  %0d   |   %2d   |   %2d    | %0d%%     | %s",
                t, a_lat[t], b_lat[t],
                (b_lat[t]>0) ? (b_lat[t]-a_lat[t])*100/b_lat[t] : 0,
                (a_lat[t]<b_lat[t]) ? "HIERARCHICAL EFFECT PROVEN" : "same");
        end

        $display("\n[VERDICT]");
        if (a_lat[3]<b_lat[3] && a_lat[4]<b_lat[4])
            $display("  Hierarchical learning acceleration CONFIRMED.");
        else
            $display("  Insufficient effect.");

        $finish;
    end
endmodule
