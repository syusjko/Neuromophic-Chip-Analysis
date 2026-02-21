// =============================================================================
// Module  : phase_attention_4n
// Project : Phase-based Spiking Transformer (PST)
//
// Description:
//   4뉴런 완전 연결 Phase Attention 네트워크.
//   6쌍의 관련성을 동시에 계산 (4C2 = 6).
//
//   [구조]
//   4개 phase_neuron (A, B, C, D)
//   6개 coincidence_detector (AB, AC, AD, BC, BD, CD)
//   1개 winner 선택기 (가장 높은 Rel 쌍 출력)
//
//   [Transformer와 대응]
//   4뉴런 = 4개 토큰
//   6쌍 Rel = Attention Score Matrix (상삼각)
//   Winner = argmax(Attention)
//
//   [출력]
//   rel_XX [7:0]: 각 쌍의 관련성 점수
//   winner [2:0]: 가장 관련성 높은 쌍 인덱스
//                 000=AB, 001=AC, 010=AD, 011=BC, 100=BD, 101=CD
//   winner_rel:   winner 쌍의 Rel 값
// =============================================================================

module phase_attention_4n #(
    parameter [7:0] THRESHOLD = 8'd200,
    parameter [7:0] PHASE_TOL = 8'd20
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] cur_a, cur_b, cur_c, cur_d,  // 4채널 입력 전류

    // 위상 출력 (모니터링)
    output wire [7:0] phase_a, phase_b, phase_c, phase_d,
    output wire       fired_a, fired_b, fired_c, fired_d,

    // 6쌍 관련성
    output wire [7:0] rel_ab, rel_ac, rel_ad,
    output wire [7:0] rel_bc, rel_bd, rel_cd,
    output wire       coin_ab, coin_ac, coin_ad,
    output wire       coin_bc, coin_bd, coin_cd,

    // Winner
    output reg  [2:0] winner,
    output reg  [7:0] winner_rel
);

    // -------------------------------------------------------------------------
    // 전역 위상 오실레이터
    // -------------------------------------------------------------------------
    wire [7:0] gphase;
    wire       cyc_start;

    gamma_oscillator #(.CYCLE_LEN(9'd256)) osc (
        .clk(clk), .rst_n(rst_n),
        .phase_out(gphase), .cycle_start(cyc_start)
    );

    // -------------------------------------------------------------------------
    // 4개 Phase Neuron
    // -------------------------------------------------------------------------
    wire spk_a, spk_b, spk_c, spk_d;

    phase_neuron #(.THRESHOLD(THRESHOLD), .LEAK(8'd0)) nA (
        .clk(clk), .rst_n(rst_n), .global_phase(gphase), .cycle_start(cyc_start),
        .input_current(cur_a), .spike_out(spk_a),
        .phase_lock(phase_a), .fired_this_cycle(fired_a));

    phase_neuron #(.THRESHOLD(THRESHOLD), .LEAK(8'd0)) nB (
        .clk(clk), .rst_n(rst_n), .global_phase(gphase), .cycle_start(cyc_start),
        .input_current(cur_b), .spike_out(spk_b),
        .phase_lock(phase_b), .fired_this_cycle(fired_b));

    phase_neuron #(.THRESHOLD(THRESHOLD), .LEAK(8'd0)) nC (
        .clk(clk), .rst_n(rst_n), .global_phase(gphase), .cycle_start(cyc_start),
        .input_current(cur_c), .spike_out(spk_c),
        .phase_lock(phase_c), .fired_this_cycle(fired_c));

    phase_neuron #(.THRESHOLD(THRESHOLD), .LEAK(8'd0)) nD (
        .clk(clk), .rst_n(rst_n), .global_phase(gphase), .cycle_start(cyc_start),
        .input_current(cur_d), .spike_out(spk_d),
        .phase_lock(phase_d), .fired_this_cycle(fired_d));

    // -------------------------------------------------------------------------
    // 6개 Coincidence Detector (4C2 = 6쌍)
    // -------------------------------------------------------------------------
    coincidence_detector #(.PHASE_TOL(PHASE_TOL)) cd_ab (
        .clk(clk), .rst_n(rst_n), .cycle_start(cyc_start),
        .fired_a(fired_a), .fired_b(fired_b),
        .phase_a(phase_a), .phase_b(phase_b),
        .relevance(rel_ab), .coincident(coin_ab));

    coincidence_detector #(.PHASE_TOL(PHASE_TOL)) cd_ac (
        .clk(clk), .rst_n(rst_n), .cycle_start(cyc_start),
        .fired_a(fired_a), .fired_b(fired_c),
        .phase_a(phase_a), .phase_b(phase_c),
        .relevance(rel_ac), .coincident(coin_ac));

    coincidence_detector #(.PHASE_TOL(PHASE_TOL)) cd_ad (
        .clk(clk), .rst_n(rst_n), .cycle_start(cyc_start),
        .fired_a(fired_a), .fired_b(fired_d),
        .phase_a(phase_a), .phase_b(phase_d),
        .relevance(rel_ad), .coincident(coin_ad));

    coincidence_detector #(.PHASE_TOL(PHASE_TOL)) cd_bc (
        .clk(clk), .rst_n(rst_n), .cycle_start(cyc_start),
        .fired_a(fired_b), .fired_b(fired_c),
        .phase_a(phase_b), .phase_b(phase_c),
        .relevance(rel_bc), .coincident(coin_bc));

    coincidence_detector #(.PHASE_TOL(PHASE_TOL)) cd_bd (
        .clk(clk), .rst_n(rst_n), .cycle_start(cyc_start),
        .fired_a(fired_b), .fired_b(fired_d),
        .phase_a(phase_b), .phase_b(phase_d),
        .relevance(rel_bd), .coincident(coin_bd));

    coincidence_detector #(.PHASE_TOL(PHASE_TOL)) cd_cd (
        .clk(clk), .rst_n(rst_n), .cycle_start(cyc_start),
        .fired_a(fired_c), .fired_b(fired_d),
        .phase_a(phase_c), .phase_b(phase_d),
        .relevance(rel_cd), .coincident(coin_cd));

    // -------------------------------------------------------------------------
    // Winner 선택기: 조합 논리로 6-way argmax
    // -------------------------------------------------------------------------
    reg [2:0] winner_comb;
    reg [7:0] winner_rel_comb;

    always @(*) begin
        // 기본값: AB
        winner_comb     = 3'd0;
        winner_rel_comb = rel_ab;

        if (rel_ac > winner_rel_comb) begin winner_comb = 3'd1; winner_rel_comb = rel_ac; end
        if (rel_ad > winner_rel_comb) begin winner_comb = 3'd2; winner_rel_comb = rel_ad; end
        if (rel_bc > winner_rel_comb) begin winner_comb = 3'd3; winner_rel_comb = rel_bc; end
        if (rel_bd > winner_rel_comb) begin winner_comb = 3'd4; winner_rel_comb = rel_bd; end
        if (rel_cd > winner_rel_comb) begin winner_comb = 3'd5; winner_rel_comb = rel_cd; end
    end

    // do_select 클럭에 래치
    reg do_select;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            do_select  <= 1'b0;
            winner     <= 3'd0;
            winner_rel <= 8'd0;
        end
        else begin
            do_select <= cyc_start;
            if (do_select) begin
                winner     <= winner_comb;
                winner_rel <= winner_rel_comb;
            end
        end
    end

endmodule
// =============================================================================
// End of phase_attention_4n.v
// =============================================================================
