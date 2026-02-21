// =============================================================================
// Module  : hnsn_top
// Project : HNSN - Phase 6: 전체 통합 Top Module
//
// Description:
//   지금까지 만든 모든 모듈을 하나로 통합한 HNSN 최상위 모듈.
//
//   [전체 데이터 흐름]
//
//   ext_spike_in[3:0]
//        │
//        ▼
//   [recurrent_layer]  ← 해마: 패턴 학습 + 연상 기억
//        │ spike_out[3:0]
//        ├──────────────────────────────────────────┐
//        ▼                                          │ (post_spike 피드백)
//   [synapse_da]       ← STDP + 도파민 조절         │
//        │ weighted_current                         │
//        ▼                                          │
//   [lif_neuron]       ← 출력 뉴런 (운동 피질)      │
//        │ output_spike ────────────────────────────┘
//        ▼
//   [spike_decoder]    ← 브로카 영역: 스파이크 → 문자
//        │
//        ▼
//   char_out[7:0]      ← ASCII 문자 출력!
//
//   [reward_circuit]   ← 도파민 생성 (보상 신호 처리)
//        │ dopamine_level[1:0]
//        └──────────────► synapse_da
//
// =============================================================================

module hnsn_top #(
    // Recurrent Layer
    parameter [7:0] REC_THRESHOLD  = 8'd50,   // 임계값 낮춤
    parameter [7:0] REC_LEAK       = 8'd15,  // LEAK 강화: 포화 방지 (3→15)
    parameter [7:0] REC_EXT_WEIGHT = 8'd60,  // THRESHOLD보다 크게 유지
    parameter [7:0] REC_INIT_W     = 8'd5,
    parameter [7:0] REC_MAX_W      = 8'd45,  // 재귀 MAX: THRESHOLD보다 낮게 → 자기 발진 방지
    parameter [7:0] REC_LTP        = 8'd3,
    parameter [7:0] REC_LTD        = 8'd1,
    parameter [3:0] REC_TRACE      = 4'd10,

    // Output Synapse (DA-STDP)
    parameter [7:0] SYN_INIT_W     = 8'd20,
    parameter [7:0] SYN_LTP        = 8'd3,
    parameter [7:0] SYN_LTD        = 8'd1,
    parameter [3:0] SYN_TRACE      = 4'd8,

    // Output Neuron
    parameter [7:0] OUT_THRESHOLD  = 8'd60,
    parameter [7:0] OUT_LEAK       = 8'd5,

    // Reward Circuit
    parameter [3:0] PREDICT_THRESH = 4'd5,
    parameter [3:0] DECAY_RATE     = 4'd8,

    // Spike Decoder
    parameter [4:0] WINDOW_SIZE    = 5'd16,
    parameter [3:0] FIRE_THRESH    = 4'd2,   // 낮춤: N1 절반 발화도 패턴 인정
    parameter [2:0] CONFIRM_CNT    = 3'd2
)(
    input  wire       clk,
    input  wire       rst_n,

    // 입력
    input  wire [3:0] ext_spike_in,   // 외부 자극 (4채널)
    input  wire       reward,          // 보상 신호

    // 출력
    output wire [7:0] char_out,        // ASCII 문자 출력
    output wire       char_valid,      // 유효 문자 펄스
    output wire       char_changed,    // 새 문자 변경 펄스

    // 모니터링
    output wire [3:0] rec_spike,       // 재귀층 발화 패턴
    output wire       output_spike,    // 출력 뉴런 발화
    output wire [1:0] dopamine,        // 도파민 레벨
    output wire [7:0] syn_weight,      // 출력 시냅스 가중치
    output wire [7:0] v_out            // 출력 뉴런 막전위
);

    // =========================================================================
    // 내부 연결 와이어
    // =========================================================================
    wire [7:0] rec_v0, rec_v1, rec_v2, rec_v3;
    wire [7:0] rec_w01, rec_w10, rec_w02, rec_w20;
    wire [7:0] rec_w03, rec_w30, rec_w12, rec_w21;
    wire [7:0] rec_w13, rec_w31, rec_w23, rec_w32;

    wire [7:0] syn_current;
    wire       predict;

    // =========================================================================
    // 1. 재귀 SNN 레이어 (해마)
    // =========================================================================
    recurrent_layer #(
        .THRESHOLD  (REC_THRESHOLD),
        .LEAK       (REC_LEAK),
        .EXT_WEIGHT (REC_EXT_WEIGHT),
        .REC_INIT_W (REC_INIT_W),
        .REC_MAX_W  (REC_MAX_W),
        .LTP_STEP   (REC_LTP),
        .LTD_STEP   (REC_LTD),
        .TRACE_DECAY(REC_TRACE)
    ) rec_layer (
        .clk        (clk),
        .rst_n      (rst_n),
        .ext_spike_in(ext_spike_in),
        .spike_out  (rec_spike),
        .v_mem_0    (rec_v0), .v_mem_1(rec_v1),
        .v_mem_2    (rec_v2), .v_mem_3(rec_v3),
        .w01(rec_w01), .w10(rec_w10),
        .w02(rec_w02), .w20(rec_w20),
        .w03(rec_w03), .w30(rec_w30),
        .w12(rec_w12), .w21(rec_w21),
        .w13(rec_w13), .w31(rec_w31),
        .w23(rec_w23), .w32(rec_w32)
    );

    // =========================================================================
    // 2. 보상 회로 (도파민)
    // =========================================================================
    reward_circuit #(
        .PREDICT_THRESH(PREDICT_THRESH),
        .DECAY_RATE    (DECAY_RATE)
    ) rew_circ (
        .clk          (clk),
        .rst_n        (rst_n),
        .reward       (reward),
        .dopamine_level(dopamine),
        .prediction   (predict)
    );

    // =========================================================================
    // 3. DA-STDP 출력 시냅스
    //    pre  = 재귀층의 N0 발화 (대표 뉴런)
    //    post = 출력 뉴런 발화
    // =========================================================================
    synapse_da #(
        .INIT_WEIGHT (SYN_INIT_W),
        .LTP_STEP    (SYN_LTP),
        .LTD_STEP    (SYN_LTD),
        .TRACE_DECAY (SYN_TRACE)
    ) out_syn (
        .clk             (clk),
        .rst_n           (rst_n),
        .pre_spike       (rec_spike[0]),   // 재귀층 N0 출력
        .post_spike      (output_spike),   // 출력 뉴런 피드백
        .dopamine_level  (dopamine),
        .weighted_current(syn_current),
        .weight          (syn_weight)
    );

    // =========================================================================
    // 4. 출력 뉴런 (운동 피질)
    // =========================================================================
    lif_neuron #(
        .THRESHOLD(OUT_THRESHOLD),
        .LEAK     (OUT_LEAK)
    ) out_neuron (
        .clk          (clk),
        .rst_n        (rst_n),
        .input_current(syn_current),
        .spike_out    (output_spike),
        .v_mem        (v_out)
    );

    // =========================================================================
    // 5. 스파이크 디코더 (브로카 영역)
    //    그룹별 독립 발화 카운팅으로 패턴 판단
    // =========================================================================
    spike_decoder #(
        .WINDOW_SIZE (WINDOW_SIZE),
        .FIRE_THRESH (FIRE_THRESH),
        .CONFIRM_CNT (CONFIRM_CNT)
    ) decoder (
        .clk         (clk),
        .rst_n       (rst_n),
        .spike_pattern(rec_spike),   // rec_spike 직접 입력
        .char_out    (char_out),
        .char_valid  (char_valid),
        .char_changed(char_changed)
    );

endmodule
// =============================================================================
// End of hnsn_top.v
// =============================================================================
