// =============================================================================
// Testbench : tb_phase_attention_4n
// Description: 4뉴런 Phase Attention 검증
//
// [시나리오]
// Scenario 1: A=B >> C >> D
//   A=50, B=48, C=20, D=5
//   기대: AB가 winner (강-강 쌍)
//
// Scenario 2: C=D >> A >> B
//   A=10, B=8, C=50, D=48
//   기대: CD가 winner (강-강 쌍)
//
// Scenario 3: 모두 비슷
//   A=30, B=32, C=28, D=31
//   기대: 모두 비슷한 Rel, winner는 가장 가까운 쌍
//
// Scenario 4: 완전 다름
//   A=50, B=25, C=12, D=5
//   기대: 모두 낮은 Rel, 그나마 가장 가까운 쌍이 winner
// =============================================================================
`timescale 1ns / 1ps

module tb_phase_attention_4n;

    reg        clk, rst_n;
    reg  [7:0] cur_a, cur_b, cur_c, cur_d;

    wire [7:0] ph_a, ph_b, ph_c, ph_d;
    wire       fa, fb, fc, fd;
    wire [7:0] rel_ab, rel_ac, rel_ad, rel_bc, rel_bd, rel_cd;
    wire       coin_ab, coin_ac, coin_ad, coin_bc, coin_bd, coin_cd;
    wire [2:0] winner;
    wire [7:0] winner_rel;

    phase_attention_4n #(.THRESHOLD(8'd200), .PHASE_TOL(8'd15)) uut (
        .clk(clk), .rst_n(rst_n),
        .cur_a(cur_a), .cur_b(cur_b), .cur_c(cur_c), .cur_d(cur_d),
        .phase_a(ph_a), .phase_b(ph_b), .phase_c(ph_c), .phase_d(ph_d),
        .fired_a(fa), .fired_b(fb), .fired_c(fc), .fired_d(fd),
        .rel_ab(rel_ab), .rel_ac(rel_ac), .rel_ad(rel_ad),
        .rel_bc(rel_bc), .rel_bd(rel_bd), .rel_cd(rel_cd),
        .coin_ab(coin_ab), .coin_ac(coin_ac), .coin_ad(coin_ad),
        .coin_bc(coin_bc), .coin_bd(coin_bd), .coin_cd(coin_cd),
        .winner(winner), .winner_rel(winner_rel)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // winner 이름 변환
    function [23:0] winner_name;
        input [2:0] w;
        begin
            case (w)
                3'd0: winner_name = "A-B";
                3'd1: winner_name = "A-C";
                3'd2: winner_name = "A-D";
                3'd3: winner_name = "B-C";
                3'd4: winner_name = "B-D";
                3'd5: winner_name = "C-D";
                default: winner_name = "???";
            endcase
        end
    endfunction

    // 사이클마다 결과 출력
    // phase_attention_4n 내부 osc에 접근
    wire [7:0] gphase = uut.gphase;
    wire       cyc    = uut.cyc_start;

    always @(posedge clk) begin
        if (gphase == 8'd253) begin
            $display("  phases: A=%3d B=%3d C=%3d D=%3d",
                     ph_a, ph_b, ph_c, ph_d);
            $display("  AB=%3d AC=%3d AD=%3d BC=%3d BD=%3d CD=%3d",
                     rel_ab, rel_ac, rel_ad, rel_bc, rel_bd, rel_cd);
            $display("  >> WINNER: %s  Rel=%3d",
                     winner_name(winner), winner_rel);
        end
    end

    integer i;
    initial begin
        rst_n=0; cur_a=0; cur_b=0; cur_c=0; cur_d=0;
        repeat(3) @(posedge clk); #1; rst_n=1;

        // ─────────────────────────────────────────
        // Scenario 1: A=B 강, C 중, D 약
        // 기대 winner: A-B
        // ─────────────────────────────────────────
        $display("\n=== Scenario 1: A=50 B=48 C=20 D=5 ===");
        $display("    Expect winner: A-B (strong pair)");
        cur_a=50; cur_b=48; cur_c=20; cur_d=5;
        repeat(768) @(posedge clk); #1;  // 3 cycles

        // ─────────────────────────────────────────
        // Scenario 2: C=D 강, A B 약
        // 기대 winner: C-D
        // ─────────────────────────────────────────
        $display("\n=== Scenario 2: A=10 B=8 C=50 D=48 ===");
        $display("    Expect winner: C-D (strong pair)");
        cur_a=10; cur_b=8; cur_c=50; cur_d=48;
        repeat(768) @(posedge clk); #1;

        // ─────────────────────────────────────────
        // Scenario 3: 모두 비슷
        // 기대 winner: 가장 가까운 쌍
        // ─────────────────────────────────────────
        $display("\n=== Scenario 3: A=30 B=32 C=28 D=31 ===");
        $display("    Expect: all similar, winner = closest pair");
        cur_a=30; cur_b=32; cur_c=28; cur_d=31;
        repeat(768) @(posedge clk); #1;

        // ─────────────────────────────────────────
        // Scenario 4: 완전 계단식
        // 기대 winner: 인접 쌍
        // ─────────────────────────────────────────
        $display("\n=== Scenario 4: A=50 B=25 C=12 D=5 ===");
        $display("    Expect: graded Rel, winner = closest adjacent");
        cur_a=50; cur_b=25; cur_c=12; cur_d=5;
        repeat(768) @(posedge clk); #1;

        $display("\n=== DONE ===");
        $finish;
    end

endmodule
// =============================================================================
// End of tb_phase_attention_4n.v
// =============================================================================
