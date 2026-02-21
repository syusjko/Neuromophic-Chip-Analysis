// =============================================================================
// Testbench: tb_alternating_v2
// 교번 패턴 (16사이클 주기) - L2가 완전 수렴 후 전환
//
// [개선]
// 주기: 4사이클 → 16사이클
// → L2 pred가 완전히 수렴 후 전환
// → L3가 명확한 4↔10 진동 학습
//
// [측정]
// Trans N에서 L2 err가 ≤5로 돌아오기까지 사이클 수
// A(active) vs B(frozen) 비교
// Trans 1 → Trans 6으로 갈수록 A가 빨라지면?
// = L3가 패턴을 학습하고 L2를 도운다는 증거
// =============================================================================
`timescale 1ns / 1ps

module tb_alternating_v2;

    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    wire [7:0] gphase; wire cyc_start;
    gamma_oscillator #(.CYCLE_LEN(9'd256)) osc (
        .clk(clk), .rst_n(rst_n), .phase_out(gphase), .cycle_start(cyc_start)
    );

    reg [7:0] cur;

    wire [7:0] ph_A,err_A,prd_A,errL3_A,boost_A,W_A,pL3_A,wL3_A;
    wire       f_A,es_A,es3_A;
    pst_2layer #(.THRESHOLD(8'd200),.W_INIT(8'd128),
                 .ETA_LTP(8'd4),.ETA_LTD(8'd3),.WINDOW(8'd128)) DUT_A (
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
                 .ETA_LTP(8'd4),.ETA_LTD(8'd3),.WINDOW(8'd128)) DUT_B (
        .clk(clk),.rst_n(rst_n),.cycle_start(cyc_start),.global_phase(gphase),
        .input_current(cur),.l3_freeze(1'b1),
        .phase_L1(ph_B),.fired_L1(f_B),
        .pred_L2(prd_B),.error_L2(err_B),.err_sign_L2(es_B),.weight_L2(W_B),
        .pred_L3(pL3_B),.error_L3(errL3_B),.err_sign_L3(es3_B),.weight_L3(wL3_B),
        .eta_boost_L2(boost_B)
    );

    integer cyc_cnt;
    always @(posedge clk)
        if (cyc_start) cyc_cnt = cyc_cnt + 1;

    // 전환 후 수렴 사이클 계산
    // new_cur 입력 후 max_cyc사이클 안에 err<=th가 되면 수렴 사이클 반환
    integer a_lat[1:6], b_lat[1:6];

    task do_transition;
        input [7:0] new_cur;
        input integer trans_num;
        input integer max_cyc;
        integer start, i;
        integer a_done, b_done;
        begin
            cur = new_cur;
            start = cyc_cnt;
            a_done = 0; b_done = 0;

            $display("\n--- [Trans %0d] cur→%0d ---", trans_num, new_cur);
            for (i=0; i<max_cyc; i=i+1) begin
                repeat(256) @(posedge clk); #1;
                $display("  [C%3d] ph=%2d | A:pred=%2d err=%2d bst=%2d L3pred=%2d L3err=%2d | B:pred=%2d err=%2d",
                    cyc_cnt, ph_A,
                    prd_A, err_A, boost_A, pL3_A, errL3_A,
                    prd_B, err_B);
                if (a_done==0 && err_A<=5) a_done = cyc_cnt - start;
                if (b_done==0 && err_B<=5) b_done = cyc_cnt - start;
            end
            a_lat[trans_num] = (a_done>0) ? a_done : max_cyc;
            b_lat[trans_num] = (b_done>0) ? b_done : max_cyc;
            $display("  → A수렴: %0d사이클, B수렴: %0d사이클 %s",
                a_lat[trans_num], b_lat[trans_num],
                (a_done < b_done && a_done>0) ? "[A WINS]" : "");
        end
    endtask

    integer t;
    initial begin
        rst_n=0; cyc_cnt=0; cur=0;
        for(t=1;t<=6;t=t+1) begin a_lat[t]=99; b_lat[t]=99; end
        repeat(3) @(posedge clk); #1; rst_n=1;

        // 초기 수렴 (cur=50, 20사이클)
        $display("=== Phase 1: 초기 수렴 (cur=50, 20cyc) ===");
        cur = 8'd50;
        repeat(5120) @(posedge clk); #1;
        $display("  완료: A(pred=%0d err=%0d) B(pred=%0d err=%0d)",
                 prd_A,err_A,prd_B,err_B);

        // 6회 교번 전환 (각 8사이클씩 측정, 8사이클씩 안정)
        $display("\n=== Phase 2: 교번 패턴 (8사이클 주기) ===");

        do_transition(8'd20, 1, 8);  // 50→20
        repeat(2048) @(posedge clk); // 8사이클 안정

        do_transition(8'd50, 2, 8);  // 20→50
        repeat(2048) @(posedge clk);

        do_transition(8'd20, 3, 8);  // 50→20
        repeat(2048) @(posedge clk);

        do_transition(8'd50, 4, 8);  // 20→50
        repeat(2048) @(posedge clk);

        do_transition(8'd20, 5, 8);  // 50→20
        repeat(2048) @(posedge clk);

        do_transition(8'd50, 6, 8);  // 20→50

        // 결과 요약
        $display("\n=== 결과 요약 ===");
        $display("Trans | A수렴 | B수렴 | 차이 | 판정");
        $display("------+-------+-------+------+------");
        for(t=1; t<=6; t=t+1)
            $display("  %0d   |  %2d   |  %2d   |  %+2d  | %s",
                t, a_lat[t], b_lat[t], b_lat[t]-a_lat[t],
                (a_lat[t] < b_lat[t]) ? "A faster" :
                (a_lat[t] == b_lat[t]) ? "same" : "B faster");

        $display("\n[핵심 판정]");
        if (a_lat[5] < b_lat[5] || a_lat[6] < b_lat[6])
            $display("  후반 전환에서 A가 더 빠름 → 계층적 학습 효과 증명!");
        else
            $display("  차이 없음 → 현재 구조로 계층 효과 달성 불가");

        $finish;
    end
endmodule
