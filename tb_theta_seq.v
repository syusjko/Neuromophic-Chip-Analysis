// =============================================================================
// Testbench: tb_theta_seq v2
// Theta Cycle Counter 수정 후 재검증
// =============================================================================
`timescale 1ns / 1ps

module tb_theta_seq;

    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    wire [7:0] gphase; wire cyc_start;
    gamma_oscillator #(.CYCLE_LEN(9'd256)) osc (
        .clk(clk),.rst_n(rst_n),.phase_out(gphase),.cycle_start(cyc_start)
    );

    reg [7:0] cur;
    integer   cyc_cnt;
    always @(posedge clk) if (cyc_start) cyc_cnt = cyc_cnt + 1;

    // DUT_A: theta active
    wire [7:0] ph_A,pred_A,err_A,W_A,pL3_A,eL3_A,boost_A;
    wire [2:0] th_A;
    wire [7:0] sl0_A, sl4_A;
    wire       f_A;
    pst_2layer_theta #(
        .THRESHOLD(8'd200),.W_INIT(8'd128),
        .ETA_LTP(8'd4),.ETA_LTD(8'd3),
        .WINDOW(8'd128),.SEQ_ETA(8'd8)
    ) DUT_A (
        .clk(clk),.rst_n(rst_n),
        .cycle_start(cyc_start),.global_phase(gphase),
        .input_current(cur),.l3_freeze(1'b0),
        .phase_L1(ph_A),.fired_L1(f_A),
        .pred_L2(pred_A),.error_L2(err_A),.weight_L2(W_A),
        .pred_L3_next(pL3_A),.error_L3(eL3_A),.eta_boost_L2(boost_A),
        .theta_dbg(th_A),.slot0_dbg(sl0_A),.slot4_dbg(sl4_A)
    );

    // DUT_B: theta frozen
    wire [7:0] ph_B,pred_B,err_B,W_B,pL3_B,eL3_B,boost_B;
    wire [2:0] th_B;
    wire [7:0] sl0_B, sl4_B;
    wire       f_B;
    pst_2layer_theta #(
        .THRESHOLD(8'd200),.W_INIT(8'd128),
        .ETA_LTP(8'd4),.ETA_LTD(8'd3),
        .WINDOW(8'd128),.SEQ_ETA(8'd8)
    ) DUT_B (
        .clk(clk),.rst_n(rst_n),
        .cycle_start(cyc_start),.global_phase(gphase),
        .input_current(cur),.l3_freeze(1'b1),
        .phase_L1(ph_B),.fired_L1(f_B),
        .pred_L2(pred_B),.error_L2(err_B),.weight_L2(W_B),
        .pred_L3_next(pL3_B),.error_L3(eL3_B),.eta_boost_L2(boost_B),
        .theta_dbg(th_B),.slot0_dbg(sl0_B),.slot4_dbg(sl4_B)
    );

    always @(posedge clk) begin
        if (cyc_start && cyc_cnt > 19)
            $display("  [C%3d] th=%0d ph=%2d | A:pred=%2d err=%2d L3nx=%2d eL3=%2d bst=%2d s0=%2d s4=%2d | B:pred=%2d err=%2d",
                cyc_cnt, th_A, ph_A,
                pred_A, err_A, pL3_A, eL3_A, boost_A, sl0_A, sl4_A,
                pred_B, err_B);
    end

    initial begin
        rst_n=0; cyc_cnt=0; cur=0;
        repeat(3) @(posedge clk); #1; rst_n=1;

        $display("=== [Phase 1] cur=200(ph~1) 초기 수렴, 20사이클 ===");
        cur = 8'd200;
        repeat(5120) @(posedge clk); #1;
        $display("  완료: A(pred=%0d err=%0d) B(pred=%0d err=%0d)",
                 pred_A,err_A,pred_B,err_B);
        $display("  A slots: slot[0]=%0d slot[4]=%0d theta=%0d",
                 sl0_A, sl4_A, th_A);
        $display("  핵심: slot[0~7] 모두 1에 가까운지?");

        $display("\n=== [Phase 2] 교번 패턴 (8사이클 주기) ===");
        $display("  관찰: slot[짝수]≈1, slot[홀수]≈40으로 분리되는가?");
        $display("  col: [C] th ph | A:pred err L3nx eL3 bst s0 s4 | B:pred err");

        $display("\n--- Trans 1: cur→5 (ph=40) ---");
        cur = 8'd5;
        repeat(2048) @(posedge clk); #1;
        $display("  Trans 1 완료: A s0=%0d s4=%0d | A pred=%0d | B pred=%0d",
                 sl0_A, sl4_A, pred_A, pred_B);

        $display("\n--- Trans 2: cur→200 (ph=1) ---");
        cur = 8'd200;
        repeat(2048) @(posedge clk); #1;
        $display("  Trans 2 완료: A s0=%0d s4=%0d | A pred=%0d | B pred=%0d",
                 sl0_A, sl4_A, pred_A, pred_B);

        $display("\n--- Trans 3: cur→5 ---");
        cur = 8'd5;
        repeat(2048) @(posedge clk); #1;

        $display("\n--- Trans 4: cur→200 ---");
        cur = 8'd200;
        repeat(2048) @(posedge clk); #1;

        $display("\n--- Trans 5: cur→5 (학습 완료 기대) ---");
        cur = 8'd5;
        repeat(2048) @(posedge clk); #1;

        $display("\n--- Trans 6: cur→200 ---");
        cur = 8'd200;
        repeat(2048) @(posedge clk); #1;

        $display("\n=== 최종 관찰 ===");
        $display("  A slots: slot0=%0d slope4=%0d (1과 40으로 분리됐는가?)",
                 sl0_A, sl4_A);
        $display("  A pred=%0d L3_next=%0d (pred_next가 다음 패턴을 가리키나?)",
                 pred_A, pL3_A);
        $display("  B pred=%0d (비교)", pred_B);

        $display("\n[판정]");
        if (sl0_A < 10 && sl4_A > 20)
            $display("  slot 분리 성공! slot0~1 (phase=1구간) slot4~5 (phase=40구간)");
        else
            $display("  slot 분리 실패 (s0=%0d, s4=%0d)", sl0_A, sl4_A);

        $display("\n=== DONE ===");
        $finish;
    end
endmodule
