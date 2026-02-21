// =============================================================================
// Testbench: tb_pst_vs_softmax (v2)
// =============================================================================
`timescale 1ns / 1ps

module tb_pst_vs_softmax;

    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    reg [7:0] cur0, cur1, cur2, cur3;

    // PST_core
    wire [7:0] ph0, ph1, ph2, ph3;
    wire       f0, f1, f2, f3;
    wire [7:0] rel_ab, rel_ac, rel_ad, rel_bc, rel_bd, rel_cd;
    wire [2:0] pst_winner;
    wire [7:0] pst_winner_rel;
    wire [7:0] rate_ab, rate_ac, rate_ad, rate_bc, rate_bd, rate_cd;
    wire [2:0] pst_winner_rate;

    pst_core #(.THRESHOLD(8'd200), .PHASE_TOL(8'd15),
               .DS_THR(9'd256), .INH_GAIN(8'd4)) pst (
        .clk(clk), .rst_n(rst_n),
        .cur0(cur0), .cur1(cur1), .cur2(cur2), .cur3(cur3),
        .phase0(ph0), .phase1(ph1), .phase2(ph2), .phase3(ph3),
        .fired0(f0), .fired1(f1), .fired2(f2), .fired3(f3),
        .rel_ab(rel_ab), .rel_ac(rel_ac), .rel_ad(rel_ad),
        .rel_bc(rel_bc), .rel_bd(rel_bd), .rel_cd(rel_cd),
        .winner(pst_winner), .winner_rel(pst_winner_rel),
        .rate_ab(rate_ab), .rate_ac(rate_ac), .rate_ad(rate_ad),
        .rate_bc(rate_bc), .rate_bd(rate_bd), .rate_cd(rate_cd),
        .winner_rate(pst_winner_rate)
    );

    // ─────────────────────────────────────────
    // Softmax Reference (조합 논리로 직접 계산)
    // 파이프라인 지연 없이 즉시 결과
    // ─────────────────────────────────────────
    // Q·K 내적 (q=k=cur, 자기 자신과 내적)
    wire [15:0] dot0 = cur0 * cur0;
    wire [15:0] dot1 = cur1 * cur1;
    wire [15:0] dot2 = cur2 * cur2;
    wire [15:0] dot3 = cur3 * cur3;

    // 상위 8비트 (스케일링)
    wire [7:0] sc0 = dot0[15:8];
    wire [7:0] sc1 = dot1[15:8];
    wire [7:0] sc2 = dot2[15:8];
    wire [7:0] sc3 = dot3[15:8];

    // argmax (조합 논리)
    reg [1:0] smx_winner;
    reg [7:0] smx_max;
    always @(*) begin
        smx_winner = 2'd0; smx_max = sc0;
        if (sc1 > smx_max) begin smx_winner=2'd1; smx_max=sc1; end
        if (sc2 > smx_max) begin smx_winner=2'd2; smx_max=sc2; end
        if (sc3 > smx_max) begin smx_winner=2'd3; smx_max=sc3; end
    end

    wire cyc_start = pst.cyc_start;

    // 통계
    integer total_tests, winner_match, cycle_count;

    // PST winner 쌍 → 더 강한 토큰 (입력 전류 기준)
    function [1:0] pst_strong_tok;
        input [2:0] pw;
        input [7:0] c0, c1, c2, c3;
        begin
            case (pw)
                3'd0: pst_strong_tok = (c0>=c1) ? 2'd0 : 2'd1;
                3'd1: pst_strong_tok = (c0>=c2) ? 2'd0 : 2'd2;
                3'd2: pst_strong_tok = (c0>=c3) ? 2'd0 : 2'd3;
                3'd3: pst_strong_tok = (c1>=c2) ? 2'd1 : 2'd2;
                3'd4: pst_strong_tok = (c1>=c3) ? 2'd1 : 2'd3;
                3'd5: pst_strong_tok = (c2>=c3) ? 2'd2 : 2'd3;
                default: pst_strong_tok = 2'd0;
            endcase
        end
    endfunction

    function [23:0] pair_name;
        input [2:0] w;
        case (w)
            3'd0: pair_name = "A-B";
            3'd1: pair_name = "A-C";
            3'd2: pair_name = "A-D";
            3'd3: pair_name = "B-C";
            3'd4: pair_name = "B-D";
            3'd5: pair_name = "C-D";
            default: pair_name = "???";
        endcase
    endfunction

    // PST 사이클마다 비교
    always @(posedge clk) begin
        if (cyc_start) cycle_count = cycle_count + 1;

        if (cyc_start && cycle_count > 1) begin
            total_tests = total_tests + 1;

            $display("  [Test %3d] cur=%3d %3d %3d %3d",
                     total_tests, cur0, cur1, cur2, cur3);
            $display("    PST: winner=%s Rel=%3d | phases=%3d %3d %3d %3d",
                     pair_name(pst_winner), pst_winner_rel,
                     ph0, ph1, ph2, ph3);
            $display("    SMX: winner=tok%0d | scores=%3d %3d %3d %3d",
                     smx_winner, sc0, sc1, sc2, sc3);

            if (pst_strong_tok(pst_winner,cur0,cur1,cur2,cur3) == smx_winner) begin
                winner_match = winner_match + 1;
                $display("    >> MATCH");
            end else begin
                $display("    >> DIFFER (PST_tok=%0d SMX_tok=%0d)",
                         pst_strong_tok(pst_winner,cur0,cur1,cur2,cur3), smx_winner);
            end
        end
    end

    initial begin
        rst_n=0; total_tests=0; winner_match=0; cycle_count=0;
        cur0=0; cur1=0; cur2=0; cur3=0;
        repeat(3) @(posedge clk); #1; rst_n=1;

        $display("=== PST_core vs Softmax 비교 (N=4) ===");

        $display("--- [Group 1] tok0 압도: 200 50 30 20 ---");
        cur0=200; cur1=50; cur2=30; cur3=20;
        repeat(512) @(posedge clk); #1;

        $display("--- [Group 2] tok0 vs tok1: 200 195 30 20 ---");
        cur0=200; cur1=195; cur2=30; cur3=20;
        repeat(512) @(posedge clk); #1;

        $display("--- [Group 3] 균등: 100 100 100 100 ---");
        cur0=100; cur1=100; cur2=100; cur3=100;
        repeat(512) @(posedge clk); #1;

        $display("--- [Group 4] 계단식: 200 150 100 50 ---");
        cur0=200; cur1=150; cur2=100; cur3=50;
        repeat(512) @(posedge clk); #1;

        $display("--- [Group 5] tok2+tok3 강자: 30 20 200 195 ---");
        cur0=30; cur1=20; cur2=200; cur3=195;
        repeat(512) @(posedge clk); #1;

        $display("--- [Group 6] tok1 압도: 20 200 30 25 ---");
        cur0=20; cur1=200; cur2=30; cur3=25;
        repeat(512) @(posedge clk); #1;

        $display("");
        $display("=== 최종 결과 ===");
        $display("  총 테스트: %0d", total_tests);
        $display("  winner 일치: %0d", winner_match);
        if (total_tests > 0)
            $display("  일치율: %0d%%", winner_match*100/total_tests);
        $display("=== DONE ===");
        $finish;
    end

endmodule
