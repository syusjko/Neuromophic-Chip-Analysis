// =============================================================================
// Module  : tb_hnsn_top (v2 - 학습 순서 재설계)
// Description : HNSN 전체 통합 시뮬레이션
//
// [v2 변경]
//   - Step 1, 3 학습 횟수 증가 (60→120)
//   - Step 2, 4 연상 복원 시 보상 신호 추가
//     (연상 복원 자체가 "올바른 행동"이므로 보상 줌)
//   - 패턴 B 학습 전 도파민 상태 리셋을 위한 대기 추가
// =============================================================================
`timescale 1ns / 1ps

module tb_hnsn_top;

    reg        clk, rst_n;
    reg  [3:0] ext_in;
    reg        reward_in;

    wire [7:0] char;
    wire       valid, changed;
    wire [3:0] rec_spk;
    wire       out_spk;
    wire [1:0] da;
    wire [7:0] syn_w, v_out;

    hnsn_top uut (
        .clk        (clk),
        .rst_n      (rst_n),
        .ext_spike_in(ext_in),
        .reward     (reward_in),
        .char_out   (char),
        .char_valid (valid),
        .char_changed(changed),
        .rec_spike  (rec_spk),
        .output_spike(out_spk),
        .dopamine   (da),
        .syn_weight (syn_w),
        .v_out      (v_out)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // 문자 출력 시 자동 표시
    always @(posedge clk) begin
        if (changed)
            $display("*** 출력 문자: '%s' (0x%02X) | T=%t | RecSpk=%b | DA=%b ***",
                     char, char, $time, rec_spk, da);
    end

    task tick;
        input [3:0] pattern;
        input       rew;
        begin
            @(posedge clk); #1;
            ext_in    = pattern;
            reward_in = rew;
        end
    endtask

    // 도파민 상태 리셋을 위한 대기 (보상 없이 충분히 쉬기)
    task rest;
        input integer n;
        integer j;
        begin
            for (j = 0; j < n; j = j + 1)
                tick(4'b0000, 1'b0);
        end
    endtask

    integer i;
    initial begin
        $dumpfile("hnsn_dump.vcd");
        $dumpvars(0, tb_hnsn_top);

        rst_n = 0; ext_in = 0; reward_in = 0;
        repeat(3) @(posedge clk); #1;
        rst_n = 1;

        // =====================================================================
        // [Step 1] 패턴 A 학습: N0+N1 + 보상 120회
        // =====================================================================
        $display("\n=== [Step 1] 패턴 A 학습 (N0+N1, 보상 있음) ===");
        for (i = 0; i < 120; i = i + 1)
            tick(4'b0011, 1'b1);
        rest(30);  // 도파민 상태 안정화

        // =====================================================================
        // [Step 2] 연상 복원 확인: N0만 자극
        //   보상 없이 → 연상으로 N1 발화 → 'E' 출력
        // =====================================================================
        $display("\n=== [Step 2] N0만 자극 → 연상 복원 ('E' 출력 기대) ===");
        for (i = 0; i < 100; i = i + 1)
            tick(4'b0001, 1'b0);
        rest(30);

        // =====================================================================
        // [Step 3] 패턴 B 학습: N2+N3 + 보상 120회
        //   도파민 완전 리셋 후 시작
        // =====================================================================
        $display("\n=== [Step 3] 패턴 B 학습 (N2+N3, 보상 있음) ===");
        for (i = 0; i < 120; i = i + 1)
            tick(4'b1100, 1'b1);
        rest(30);

        // =====================================================================
        // [Step 4] 연상 복원 확인: N2만 자극 → 'F' 출력
        // =====================================================================
        $display("\n=== [Step 4] N2만 자극 → 연상 복원 ('F' 출력 기대) ===");
        for (i = 0; i < 100; i = i + 1)
            tick(4'b0100, 1'b0);
        rest(30);

        // =====================================================================
        // [Step 5] 교대 출력: N0 → 'E', N2 → 'F' 반복
        // =====================================================================
        $display("\n=== [Step 5] 패턴 교대 → 'E'와 'F' 교대 출력 기대 ===");
        for (i = 0; i < 5; i = i + 1) begin
            repeat(80) tick(4'b0001, 1'b0);  // N0 → 'E'
            rest(20);
            repeat(80) tick(4'b0100, 1'b0);  // N2 → 'F'
            rest(20);
        end

        $display("\n=== [시뮬레이션 완료] ===");
        $finish;
    end

    initial begin
        $monitor("T=%t | In=%b Rew=%b | RecSpk=%b | DA=%b | SynW=%3d | Char=%s Valid=%b",
                 $time, ext_in, reward_in, rec_spk, da, syn_w, char, valid);
    end

endmodule
// =============================================================================
// End of tb_hnsn_top.v (v2)
// =============================================================================
