// =============================================================================
// Module  : recurrent_layer (v2 - 그룹 분리 구조)
// Project : HNSN - Phase 4 개선
//
// [v2 변경]
//   기존: 4뉴런 완전 연결 (All-to-All, 12개 시냅스)
//         → 패턴 A 학습 후 패턴 B 학습 시 교차 간섭 발생
//
//   변경: 그룹 내 연결만 허용
//         Group A: N0 ↔ N1  (2개 시냅스)
//         Group B: N2 ↔ N3  (2개 시냅스)
//         그룹 간 연결 없음 → 패턴 독립성 보장
//
//   [생물학적 대응]
//   해마의 CA3 서브필드는 기능적으로 분리된 뉴런 앙상블을 형성
//   억제성 인터뉴런이 앙상블 간 간섭을 차단
//   → 여기서는 구조적으로 그룹 분리를 구현
//
// I/O: 기존과 동일 (하위 호환)
// =============================================================================

module recurrent_layer #(
    parameter [7:0] THRESHOLD   = 8'd50,
    parameter [7:0] LEAK        = 8'd15,
    parameter [7:0] EXT_WEIGHT  = 8'd60,
    parameter [7:0] REC_INIT_W  = 8'd5,
    parameter [7:0] REC_MAX_W   = 8'd45,  // 재귀 최대 가중치 = THRESHOLD-5
                                           // → 재귀 전류만으로 발화 불가능
                                           // → 외부 자극 필수 (자기 발진 방지)
    parameter [7:0] LTP_STEP    = 8'd3,
    parameter [7:0] LTD_STEP    = 8'd1,
    parameter [3:0] TRACE_DECAY = 4'd10
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] ext_spike_in,
    output wire [3:0] spike_out,
    output wire [7:0] v_mem_0,
    output wire [7:0] v_mem_1,
    output wire [7:0] v_mem_2,
    output wire [7:0] v_mem_3,

    // 그룹 내 시냅스 가중치만 모니터링
    output wire [7:0] w01, output wire [7:0] w10,  // Group A
    output wire [7:0] w23, output wire [7:0] w32,  // Group B

    // 미사용 포트 (하위 호환용, 0으로 고정)
    output wire [7:0] w02, output wire [7:0] w20,
    output wire [7:0] w03, output wire [7:0] w30,
    output wire [7:0] w12, output wire [7:0] w21,
    output wire [7:0] w13, output wire [7:0] w31
);

    // =========================================================================
    // 그룹 내 시냅스 전류
    // =========================================================================
    wire [7:0] c01, c10;   // Group A: N0→N1, N1→N0
    wire [7:0] c23, c32;   // Group B: N2→N3, N3→N2

    // =========================================================================
    // 외부 입력 전류
    // =========================================================================
    wire [7:0] ext0 = ext_spike_in[0] ? EXT_WEIGHT : 8'd0;
    wire [7:0] ext1 = ext_spike_in[1] ? EXT_WEIGHT : 8'd0;
    wire [7:0] ext2 = ext_spike_in[2] ? EXT_WEIGHT : 8'd0;
    wire [7:0] ext3 = ext_spike_in[3] ? EXT_WEIGHT : 8'd0;

    // =========================================================================
    // 총 입력 전류 (그룹 내 재귀만)
    // =========================================================================
    wire [8:0] sum0 = {1'b0, ext0} + {1'b0, c10};   // N0 = ext + N1→N0
    wire [8:0] sum1 = {1'b0, ext1} + {1'b0, c01};   // N1 = ext + N0→N1
    wire [8:0] sum2 = {1'b0, ext2} + {1'b0, c32};   // N2 = ext + N3→N2
    wire [8:0] sum3 = {1'b0, ext3} + {1'b0, c23};   // N3 = ext + N2→N3

    wire [7:0] cur0 = sum0[8] ? 8'd255 : sum0[7:0];
    wire [7:0] cur1 = sum1[8] ? 8'd255 : sum1[7:0];
    wire [7:0] cur2 = sum2[8] ? 8'd255 : sum2[7:0];
    wire [7:0] cur3 = sum3[8] ? 8'd255 : sum3[7:0];

    // =========================================================================
    // LIF 뉴런 4개
    // =========================================================================
    lif_neuron #(.THRESHOLD(THRESHOLD), .LEAK(LEAK)) n0
        (.clk(clk), .rst_n(rst_n), .input_current(cur0),
         .spike_out(spike_out[0]), .v_mem(v_mem_0));

    lif_neuron #(.THRESHOLD(THRESHOLD), .LEAK(LEAK)) n1
        (.clk(clk), .rst_n(rst_n), .input_current(cur1),
         .spike_out(spike_out[1]), .v_mem(v_mem_1));

    lif_neuron #(.THRESHOLD(THRESHOLD), .LEAK(LEAK)) n2
        (.clk(clk), .rst_n(rst_n), .input_current(cur2),
         .spike_out(spike_out[2]), .v_mem(v_mem_2));

    lif_neuron #(.THRESHOLD(THRESHOLD), .LEAK(LEAK)) n3
        (.clk(clk), .rst_n(rst_n), .input_current(cur3),
         .spike_out(spike_out[3]), .v_mem(v_mem_3));

    // =========================================================================
    // STDP 시냅스 - 그룹 내만 (4개)
    // =========================================================================

    // --- Group A: N0 ↔ N1 ---
    synapse #(.INIT_WEIGHT(REC_INIT_W),.MAX_WEIGHT(REC_MAX_W),.LTP_STEP(LTP_STEP),.LTD_STEP(LTD_STEP),.TRACE_DECAY(TRACE_DECAY))
        s01(.clk(clk),.rst_n(rst_n),.pre_spike(spike_out[0]),.post_spike(spike_out[1]),.weighted_current(c01),.weight(w01));
    synapse #(.INIT_WEIGHT(REC_INIT_W),.MAX_WEIGHT(REC_MAX_W),.LTP_STEP(LTP_STEP),.LTD_STEP(LTD_STEP),.TRACE_DECAY(TRACE_DECAY))
        s10(.clk(clk),.rst_n(rst_n),.pre_spike(spike_out[1]),.post_spike(spike_out[0]),.weighted_current(c10),.weight(w10));

    // --- Group B: N2 ↔ N3 ---
    synapse #(.INIT_WEIGHT(REC_INIT_W),.MAX_WEIGHT(REC_MAX_W),.LTP_STEP(LTP_STEP),.LTD_STEP(LTD_STEP),.TRACE_DECAY(TRACE_DECAY))
        s23(.clk(clk),.rst_n(rst_n),.pre_spike(spike_out[2]),.post_spike(spike_out[3]),.weighted_current(c23),.weight(w23));
    synapse #(.INIT_WEIGHT(REC_INIT_W),.MAX_WEIGHT(REC_MAX_W),.LTP_STEP(LTP_STEP),.LTD_STEP(LTD_STEP),.TRACE_DECAY(TRACE_DECAY))
        s32(.clk(clk),.rst_n(rst_n),.pre_spike(spike_out[3]),.post_spike(spike_out[2]),.weighted_current(c32),.weight(w32));

    // =========================================================================
    // 미사용 포트 0으로 고정 (하위 호환)
    // =========================================================================
    assign w02 = 8'd0; assign w20 = 8'd0;
    assign w03 = 8'd0; assign w30 = 8'd0;
    assign w12 = 8'd0; assign w21 = 8'd0;
    assign w13 = 8'd0; assign w31 = 8'd0;

endmodule
// =============================================================================
// End of recurrent_layer.v (v2)
// =============================================================================
