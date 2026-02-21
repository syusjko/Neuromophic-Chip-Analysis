// =============================================================================
// Testbench: tb_alternating_v3
// L2 의도적 약화 (ETA=1) + 큰 phase 차이 (cur=200/5)
//
// [변경점]
//   ETA_LTP=1, ETA_LTD=1 → L2 느리게 학습 (기존 4)
//   cur=200(phase=1) vs cur=5(phase=40) → 차이=39 (기존 6)
//
// [기대]
//   B(frozen): 8~15사이클 걸림 (현저히 느림)
//   A(active): L3 boost가 실제로 도움 → 5~8사이클
//   → 30%+ 차이 → 계층 효과 증명
// =============================================================================
`timescale 1ns / 1ps

module tb_alternating_v3;

    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    wire [7:0] gphase; wire cyc_start;
    gamma_oscillator #(.CYCLE_LEN(9'd256)) osc (
        .clk(clk),.rst_n(rst_n),.phase_out(gphase),.cycle_start(cyc_start)
    );

    reg [7:0] cur;

    // ETA=1로 낮춤 → L2가 느리게 학습
    wire [7:0] ph_A,err_A,prd_A,errL3_A,boost_A,W_A,pL3_A,wL3_A;
    wire       f_A,es_A,es3_A;
    pst_2layer #(.THRESHOLD(8'd200),.W_INIT(8'd128),
                 .ETA_LTP(8'd1),.ETA_LTD(8'd1),.WINDOW(8'd128)) DUT_A (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.global_phase(gphase),
        .input_current(cur),.l3_freeze(1'b0),
        .phase_L1(ph_A),.fired_L1(f_A),
        .pred_L2(prd_A),.error_L2(err_A),.err_sign_L2(es_A),.weight_L2(W_A),
        .pred_L3(pL3_A),.error_L3(errL3_A),.err_sign_L3(es3_A),.weight_L3(wL3_A),
        .eta_boost_L2(boost_A)
    );

    wire [7:0] ph_B,err_B,prd_B,errL3_B,boost_B,W_B,pL3_B,wL3_B;
    wire       f_B,es_B,es3_B;
    pst_2layer #(.THRESHOLD(8'd200),.W_INIT(8'd128),
                 .ETA_LTP(8'd1),.ETA_LTD(8'd1),.WINDOW(8'd128)) DUT_B (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.global_phase(gphase),
        .input_current(cur),.l3_freeze(1'b1),
        .phase_L1(ph_B),.fired_L1(f_B),
        .pred_L2(prd_B),.error_L2(err_B),.err_sign_L2(es_B),.weight_L2(W_B),
        .pred_L3(pL3_B),.error_L3(errL3_B),.err_sign_L3(es3_B),.weight_L3(wL3_B),
        .eta_boost_L2(boost_B)
    );

    integer cyc_cnt;
    always @(posedge clk) if (cyc_start) cyc_cnt = cyc_cnt + 1;

    integer a_lat[1:6], b_lat[1:6];

    task do_transition;
        input [7:0] new_cur;
        input integer trans_num, max_cyc;
        integer start, i, a_done, b_done;
        begin
            cur = new_cur;
            start = cyc_cnt;
            a_done = 0; b_done = 0;
            $display("\n--- [Trans %0d] cur->%0d (expected_phase=%0d) ---",
                trans_num, new_cur, (new_cur==8'd200)?1:40);
            for (i=0; i<max_cyc; i=i+1) begin
                repeat(256) @(posedge clk); #1;
                $display("  [C%3d] ph=%2d | A:pred=%2d err=%2d bst=%2d L3p=%2d L3e=%2d | B:pred=%2d err=%2d",
                    cyc_cnt, ph_A,
                    prd_A, err_A, boost_A, pL3_A, errL3_A,
                    prd_B, err_B);
                if (a_done==0 && err_A<=5) a_done = cyc_cnt - start;
                if (b_done==0 && err_B<=5) b_done = cyc_cnt - start;
            end
            a_lat[trans_num] = (a_done>0) ? a_done : max_cyc;
            b_lat[trans_num] = (b_done>0) ? b_done : max_cyc;
            if (a_lat[trans_num] < b_lat[trans_num])
                $display("  -> A=%0d B=%0d [A가 %0d%% 빠름!]",
                    a_lat[trans_num], b_lat[trans_num],
                    (b_lat[trans_num]-a_lat[trans_num])*100/b_lat[trans_num]);
            else
                $display("  -> A=%0d B=%0d [차이없음]",
                    a_lat[trans_num], b_lat[trans_num]);
        end
    endtask

    integer t;
    initial begin
        rst_n=0; cyc_cnt=0; cur=0;
        for(t=1;t<=6;t=t+1) begin a_lat[t]=99; b_lat[t]=99; end
        repeat(3) @(posedge clk); #1; rst_n=1;

        // 초기 수렴 (cur=200, phase=1, 30사이클)
        $display("=== Phase 1: 초기 수렴 (cur=200, phase~1, 30cyc) ===");
        cur = 8'd200;
        repeat(7680) @(posedge clk); #1;
        $display("  완료: A(pred=%0d err=%0d boost=%0d) B(pred=%0d err=%0d)",
                 prd_A, err_A, boost_A, prd_B, err_B);

        $display("\n=== Phase 2: 교번 패턴 (cur=200/5, phase=1/40) ===");
        $display("  ETA=1(느림), phase차이=39(큼)");
        $display("  B가 충분히 느려야 A 계층 효과 가시화");

        do_transition(8'd5,   1, 16);  // phase 1→40
        repeat(3840) @(posedge clk); #1;

        do_transition(8'd200, 2, 16);  // phase 40→1
        repeat(3840) @(posedge clk); #1;

        do_transition(8'd5,   3, 16);
        repeat(3840) @(posedge clk); #1;

        do_transition(8'd200, 4, 16);
        repeat(3840) @(posedge clk); #1;

        do_transition(8'd5,   5, 16);
        repeat(3840) @(posedge clk); #1;

        do_transition(8'd200, 6, 16);

        $display("\n=== 결과 요약 ===");
        $display("Trans | A수렴 | B수렴 | 향상");
        for(t=1; t<=6; t=t+1)
            $display("  %0d   |  %2d   |  %2d   |  %s",
                t, a_lat[t], b_lat[t],
                (a_lat[t]<b_lat[t]) ? "+계층효과" : "없음");

        $display("\n[최종 판정]");
        if (a_lat[5]<b_lat[5] || a_lat[6]<b_lat[6])
            $display("  후반 전환 A 빠름 -> 계층적 학습 증명!");
        else
            $display("  차이없음 -> 방법B(transition predictor) 필요");

        $finish;
    end
endmodule
