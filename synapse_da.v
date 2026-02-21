// =============================================================================
// Module  : synapse_da
// Project : HNSN - Phase 5: Neuromodulation (도파민 조절 시냅스)
//
// Description:
//   기존 STDP 시냅스에 도파민(Dopamine) 신호를 추가한 확장 버전.
//   뇌의 보상 회로(Reward Circuit)를 모사.
//
//   [생물학적 배경]
//   도파민은 "보상 예측 오류(Reward Prediction Error)" 신호.
//   - 예상보다 좋은 일 발생 → 도파민 급증 → 시냅스 강하게 강화
//   - 예상보다 나쁜 일 발생 → 도파민 감소 → 시냅스 약화
//   - 예상대로 → 도파민 변화 없음 → 시냅스 유지
//
//   [하드웨어 구현]
//   기존 STDP:  weight += LTP_STEP (고정)
//   DA-STDP:    weight += LTP_STEP * dopamine_level (가변)
//
//   dopamine_level [1:0]:
//     2'b00 = 도파민 없음  → 학습 억제 (LTP/LTD 모두 절반)
//     2'b01 = 기본 도파민  → 일반 STDP (기존과 동일)
//     2'b10 = 높은 도파민  → 강화 학습 (LTP 2배, LTD 절반)
//     2'b11 = 최대 도파민  → 강력 강화 (LTP 3배, LTD 없음)
//
//   이를 통해 "보상이 있을 때만 강하게 학습" 구현
// =============================================================================

module synapse_da #(
    parameter [7:0] INIT_WEIGHT  = 8'd10,
    parameter [7:0] MAX_WEIGHT   = 8'd255,
    parameter [7:0] MIN_WEIGHT   = 8'd0,
    parameter [7:0] LTP_STEP     = 8'd2,
    parameter [7:0] LTD_STEP     = 8'd1,
    parameter [3:0] TRACE_DECAY  = 4'd8
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       pre_spike,
    input  wire       post_spike,
    input  wire [1:0] dopamine_level,   // 도파민 농도 (00~11)

    output wire [7:0] weighted_current,
    output wire [7:0] weight
);

    reg [7:0] weight_reg;
    reg [3:0] pre_trace;
    reg [3:0] post_trace;

    // -------------------------------------------------------------------------
    // 도파민 레벨에 따른 LTP/LTD 스텝 조절
    // -------------------------------------------------------------------------
    reg [7:0] ltp_effective;
    reg [7:0] ltd_effective;

    always @(*) begin
        case (dopamine_level)
            2'b00: begin  // 도파민 없음: 학습 억제
                ltp_effective = LTP_STEP >> 1;   // LTP 절반
                ltd_effective = LTD_STEP;         // LTD 유지 (망각)
            end
            2'b01: begin  // 기본: 일반 STDP
                ltp_effective = LTP_STEP;
                ltd_effective = LTD_STEP;
            end
            2'b10: begin  // 높은 도파민: 강화 학습
                ltp_effective = LTP_STEP << 1;   // LTP 2배
                ltd_effective = LTD_STEP >> 1;   // LTD 절반
            end
            2'b11: begin  // 최대 도파민: 강력 강화
                ltp_effective = LTP_STEP + (LTP_STEP << 1); // LTP 3배
                ltd_effective = 8'd0;             // LTD 없음 (완전 강화)
            end
        endcase
    end

    // -------------------------------------------------------------------------
    // 가중치 업데이트 (오버플로우/언더플로우 방지)
    // -------------------------------------------------------------------------
    wire [8:0] weight_ltp = {1'b0, weight_reg} + {1'b0, ltp_effective};
    wire [8:0] weight_ltd = {1'b0, weight_reg} - {1'b0, ltd_effective};

    wire [7:0] weight_after_ltp =
        (weight_ltp > {1'b0, MAX_WEIGHT}) ? MAX_WEIGHT : weight_ltp[7:0];
    wire [7:0] weight_after_ltd =
        weight_ltd[8] ? MIN_WEIGHT : weight_ltd[7:0];

    // -------------------------------------------------------------------------
    // 순차 논리
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_reg <= INIT_WEIGHT;
            pre_trace  <= 4'd0;
            post_trace <= 4'd0;
        end
        else begin
            // 트레이스 업데이트
            if (pre_spike)        pre_trace <= TRACE_DECAY;
            else if (pre_trace > 0) pre_trace <= pre_trace - 4'd1;

            if (post_spike)        post_trace <= TRACE_DECAY;
            else if (post_trace > 0) post_trace <= post_trace - 4'd1;

            // DA-STDP 가중치 업데이트
            if (post_spike && (pre_trace > 4'd0))
                weight_reg <= weight_after_ltp;   // LTP (도파민 조절)
            else if (pre_spike && (post_trace > 4'd0))
                weight_reg <= weight_after_ltd;   // LTD (도파민 조절)
        end
    end

    assign weighted_current = pre_spike ? weight_reg : 8'd0;
    assign weight           = weight_reg;

endmodule
// =============================================================================
// End of synapse_da.v
// =============================================================================
