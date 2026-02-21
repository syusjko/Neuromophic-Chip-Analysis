// =============================================================================
// Module  : network (v2 - STDP 학습 시냅스 연동)
// Project : Neuromorphic Chip
//
// 구조:
//   spike_in_global
//        │  input_current_n1 (고정값)
//        ▼
//   [N1: lif_neuron]
//        │ pre_spike (spike_out_n1)
//        ▼
//   [Synapse: STDP]  ←── post_spike (spike_out_n2) 피드백
//        │ weighted_current
//        ▼
//   [N2: lif_neuron]
//        │ spike_out_n2 (최종 출력)
//
// 핵심:
//   - N1이 발화 → Synapse가 weighted_current를 N2에 전달
//   - N2가 발화 → Synapse에 post_spike로 피드백
//   - Synapse는 pre/post 타이밍 비교 → weight 자동 조절 (STDP)
// =============================================================================

module network #(
    // N1 파라미터
    parameter [7:0] N1_THRESHOLD     = 8'd60,
    parameter [7:0] N1_LEAK          = 8'd5,
    parameter [7:0] N1_INPUT_CURRENT = 8'd20,  // N1에 고정으로 들어오는 전류

    // N2 파라미터
    parameter [7:0] N2_THRESHOLD     = 8'd60,
    parameter [7:0] N2_LEAK          = 8'd5,

    // Synapse STDP 파라미터
    parameter [7:0] SYN_INIT_WEIGHT  = 8'd10,
    parameter [7:0] SYN_MAX_WEIGHT   = 8'd255,
    parameter [7:0] SYN_MIN_WEIGHT   = 8'd0,
    parameter [7:0] SYN_LTP_STEP     = 8'd1,
    parameter [7:0] SYN_LTD_STEP     = 8'd1,
    parameter [3:0] SYN_TRACE_DECAY  = 4'd8
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       spike_in_global,  // 외부 자극 (N1 활성화용)

    output wire       spike_out_n1,     // N1 발화 출력
    output wire       spike_out_n2,     // N2 발화 출력 (최종)
    output wire [7:0] v_mem_n1,         // N1 막전위 (모니터링)
    output wire [7:0] v_mem_n2,         // N2 막전위 (모니터링)
    output wire [7:0] syn_weight        // 시냅스 가중치 (학습 관찰용)
);

    // -------------------------------------------------------------------------
    // 내부 연결 와이어
    // -------------------------------------------------------------------------
    wire [7:0] n1_input_current;    // N1으로 들어가는 전류
    wire [7:0] syn_current_to_n2;   // Synapse → N2 전류

    // N1 입력 전류: spike_in_global이 1일 때만 N1_INPUT_CURRENT 전달
    assign n1_input_current = spike_in_global ? N1_INPUT_CURRENT : 8'd0;

    // -------------------------------------------------------------------------
    // N1: 감각 뉴런 (Pre-synaptic Neuron)
    // -------------------------------------------------------------------------
    lif_neuron #(
        .THRESHOLD(N1_THRESHOLD),
        .LEAK     (N1_LEAK)
    ) neuron1 (
        .clk          (clk),
        .rst_n        (rst_n),
        .input_current(n1_input_current),
        .spike_out    (spike_out_n1),
        .v_mem        (v_mem_n1)
    );

    // -------------------------------------------------------------------------
    // Synapse: STDP 학습 시냅스
    //   - pre_spike  = N1의 발화 출력
    //   - post_spike = N2의 발화 출력 (피드백 연결)
    // -------------------------------------------------------------------------
    synapse #(
        .INIT_WEIGHT (SYN_INIT_WEIGHT),
        .MAX_WEIGHT  (SYN_MAX_WEIGHT),
        .MIN_WEIGHT  (SYN_MIN_WEIGHT),
        .LTP_STEP    (SYN_LTP_STEP),
        .LTD_STEP    (SYN_LTD_STEP),
        .TRACE_DECAY (SYN_TRACE_DECAY)
    ) syn (
        .clk             (clk),
        .rst_n           (rst_n),
        .pre_spike       (spike_out_n1),   // N1 발화 → 시냅스 입력
        .post_spike      (spike_out_n2),   // N2 발화 → 피드백
        .weighted_current(syn_current_to_n2),
        .weight          (syn_weight)
    );

    // -------------------------------------------------------------------------
    // N2: 운동 뉴런 (Post-synaptic Neuron)
    // -------------------------------------------------------------------------
    lif_neuron #(
        .THRESHOLD(N2_THRESHOLD),
        .LEAK     (N2_LEAK)
    ) neuron2 (
        .clk          (clk),
        .rst_n        (rst_n),
        .input_current(syn_current_to_n2), // 시냅스 출력 전류 수신
        .spike_out    (spike_out_n2),
        .v_mem        (v_mem_n2)
    );

endmodule
// =============================================================================
// End of network.v (v2)
// =============================================================================
