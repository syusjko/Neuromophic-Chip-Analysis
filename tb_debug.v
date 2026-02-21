// =============================================================================
// Module  : tb_debug
// Description : 각 단계별 발화 패턴 디버그용 테스트벤치
//   - 각 뉴런의 발화 여부를 직접 확인
//   - 재귀 시냅스 가중치 변화 추적
// =============================================================================
`timescale 1ns / 1ps

module tb_debug;

    reg        clk, rst_n;
    reg  [3:0] ext_in;
    reg        reward_in;

    wire [7:0] char;
    wire       valid, changed;
    wire [3:0] rec_spk;
    wire       out_spk;
    wire [1:0] da;
    wire [7:0] syn_w, v_out;

    // 재귀층 내부 가중치 직접 접근
    wire [7:0] w01, w10, w23, w32;
    wire [7:0] v0, v1, v2, v3;

    // hnsn_top 내부 recurrent_layer 접근
    assign w01 = uut.rec_layer.w01;
    assign w10 = uut.rec_layer.w10;
    assign w23 = uut.rec_layer.w23;
    assign w32 = uut.rec_layer.w32;
    assign v0  = uut.rec_layer.v_mem_0;
    assign v1  = uut.rec_layer.v_mem_1;
    assign v2  = uut.rec_layer.v_mem_2;
    assign v3  = uut.rec_layer.v_mem_3;

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

    task tick;
        input [3:0] pattern;
        input       rew;
        begin
            @(posedge clk); #1;
            ext_in    = pattern;
            reward_in = rew;
        end
    endtask

    integer i, fire_n0, fire_n1, fire_n2, fire_n3;

    // 발화 카운터
    always @(posedge clk) begin
        if (rec_spk[0]) fire_n0 = fire_n0 + 1;
        if (rec_spk[1]) fire_n1 = fire_n1 + 1;
        if (rec_spk[2]) fire_n2 = fire_n2 + 1;
        if (rec_spk[3]) fire_n3 = fire_n3 + 1;
    end

    task reset_counters;
        begin
            fire_n0 = 0; fire_n1 = 0;
            fire_n2 = 0; fire_n3 = 0;
        end
    endtask

    task report;
        input [63:0] label; // 사용 안 함, $display로 직접
        begin
            $display("  발화횟수: N0=%0d N1=%0d N2=%0d N3=%0d",
                     fire_n0, fire_n1, fire_n2, fire_n3);
            $display("  가중치:  W01=%0d W10=%0d W23=%0d W32=%0d",
                     w01, w10, w23, w32);
            $display("  막전위:  V0=%0d V1=%0d V2=%0d V3=%0d",
                     v0, v1, v2, v3);
            $display("  DA=%b Char=%s", da, char);
        end
    endtask

    initial begin
        rst_n = 0; ext_in = 0; reward_in = 0;
        fire_n0=0; fire_n1=0; fire_n2=0; fire_n3=0;
        repeat(3) @(posedge clk); #1;
        rst_n = 1;

        // ─────────────────────────────────────────
        $display("\n[Step 1] 패턴 A 학습: N0+N1 x120 + 보상");
        reset_counters;
        for (i = 0; i < 120; i = i + 1) tick(4'b0011, 1'b1);
        report(0);

        $display("\n[휴식 30]");
        reset_counters;
        for (i = 0; i < 30; i = i + 1) tick(4'b0000, 1'b0);
        report(0);

        // ─────────────────────────────────────────
        $display("\n[Step 2] N0만 자극 x100");
        reset_counters;
        for (i = 0; i < 100; i = i + 1) tick(4'b0001, 1'b0);
        report(0);
        for (i = 0; i < 30; i = i + 1) tick(4'b0000, 1'b0);

        // ─────────────────────────────────────────
        $display("\n[Step 3] 패턴 B 학습: N2+N3 x120 + 보상");
        reset_counters;
        for (i = 0; i < 120; i = i + 1) tick(4'b1100, 1'b1);
        report(0);

        $display("\n[휴식 30]");
        reset_counters;
        for (i = 0; i < 30; i = i + 1) tick(4'b0000, 1'b0);
        report(0);

        // ─────────────────────────────────────────
        $display("\n[Step 4] N2만 자극 x100");
        reset_counters;
        for (i = 0; i < 100; i = i + 1) tick(4'b0100, 1'b0);
        report(0);

        $display("\n[완료]");
        $finish;
    end

endmodule
