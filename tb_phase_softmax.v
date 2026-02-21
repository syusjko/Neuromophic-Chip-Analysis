// =============================================================================
// Testbench: tb_phase_softmax (v2)
// =============================================================================
`timescale 1ns / 1ps

module tb_phase_softmax;

    reg clk, rst_n;
    initial clk = 0;
    always #5 clk = ~clk;

    reg [7:0] r_ab, r_ac, r_ad, r_bc, r_bd, r_cd;
    reg       cyc;

    wire spk_ab, spk_ac, spk_ad, spk_bc, spk_bd, spk_cd;
    wire [7:0] rate_ab, rate_ac, rate_ad, rate_bc, rate_bd, rate_cd;
    wire [2:0] winner_out;

    phase_softmax #(.THRESHOLD(9'd256), .INHIBIT_GAIN(8'd4)) uut (
        .clk(clk), .rst_n(rst_n), .cycle_start(cyc),
        .rel_ab(r_ab), .rel_ac(r_ac), .rel_ad(r_ad),
        .rel_bc(r_bc), .rel_bd(r_bd), .rel_cd(r_cd),
        .spike_ab(spk_ab), .spike_ac(spk_ac), .spike_ad(spk_ad),
        .spike_bc(spk_bc), .spike_bd(spk_bd), .spike_cd(spk_cd),
        .rate_ab(rate_ab), .rate_ac(rate_ac), .rate_ad(rate_ad),
        .rate_bc(rate_bc), .rate_bd(rate_bd), .rate_cd(rate_cd),
        .winner_out(winner_out)
    );

    // 256클럭 사이클 생성
    reg [7:0] phase_cnt;
    integer   cycle_num;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin phase_cnt<=0; cyc<=0; end
        else begin
            cyc       <= (phase_cnt == 8'd255);
            phase_cnt <= phase_cnt + 1;
        end
    end

    // winner 이름
    function [23:0] wname;
        input [2:0] w;
        case (w)
            3'd0: wname = "A-B";
            3'd1: wname = "A-C";
            3'd2: wname = "A-D";
            3'd3: wname = "B-C";
            3'd4: wname = "B-D";
            3'd5: wname = "C-D";
            default: wname = "???";
        endcase
    endfunction

    // 사이클마다 결과 출력
    always @(posedge clk) begin
        if (cyc && cycle_num > 0) begin
            $display("  [Cycle %2d] Winner=%s | AB=%3d BC=%3d AC=%3d CD=%3d AD=%3d BD=%3d",
                     cycle_num, wname(winner_out),
                     rate_ab, rate_bc, rate_ac, rate_cd, rate_ad, rate_bd);
            $display("             Rel:       AB=%3d BC=%3d AC=%3d CD=%3d AD=%3d BD=%3d",
                     r_ab, r_bc, r_ac, r_cd, r_ad, r_bd);
            // 억제 효과: winner vs 2위 비율
            if (rate_bc > 0)
                $display("             AB/BC ratio: %0d/%0d", rate_ab, rate_bc);
        end
        if (cyc) cycle_num = cycle_num + 1;
    end

    initial begin
        rst_n=0; cyc=0; cycle_num=0;
        repeat(3) @(posedge clk); #1; rst_n=1;

        // ─────────────────────────────────────────
        // Scenario 1: AB 최강 (254), 나머지 비슷
        // 기대: AB 압도적, 나머지 억제됨
        // ─────────────────────────────────────────
        $display("\n=== Scenario 1: AB=254(max) BC=250 AC=249 CD=225 AD=219 BD=220 ===");
        $display("    Expect: AB >> others (lateral inhibition)");
        r_ab=254; r_bc=250; r_ac=249; r_cd=225; r_ad=219; r_bd=220;
        repeat(1024) @(posedge clk); #1;

        // ─────────────────────────────────────────
        // Scenario 2: 모두 동일
        // 기대: 모두 같은 발화율 (억제 없음)
        // ─────────────────────────────────────────
        $display("\n=== Scenario 2: All Rel=200 (uniform) ===");
        $display("    Expect: all equal, no inhibition");
        r_ab=200; r_ac=200; r_ad=200; r_bc=200; r_bd=200; r_cd=200;
        repeat(1024) @(posedge clk); #1;

        // ─────────────────────────────────────────
        // Scenario 3: AB 압도적 (255), 나머지 0
        // 기대: AB만 발화
        // ─────────────────────────────────────────
        $display("\n=== Scenario 3: AB=255 only, rest=0 ===");
        $display("    Expect: only AB fires");
        r_ab=255; r_ac=0; r_ad=0; r_bc=0; r_bd=0; r_cd=0;
        repeat(1024) @(posedge clk); #1;

        // ─────────────────────────────────────────
        // Scenario 4: 두 쌍이 경쟁 (AB=254, CD=252)
        // 기대: AB가 CD를 억제
        // ─────────────────────────────────────────
        $display("\n=== Scenario 4: AB=254 vs CD=252 (close competition) ===");
        $display("    Expect: AB wins, CD suppressed");
        r_ab=254; r_ac=100; r_ad=100; r_bc=100; r_bd=100; r_cd=252;
        repeat(1024) @(posedge clk); #1;

        $display("\n=== DONE ===");
        $finish;
    end

endmodule
