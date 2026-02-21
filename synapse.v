// =============================================================================
// Module  : synapse
// Project : Neuromorphic Chip - STDP Learning Synapse
// 
// Description:
//   STDP(Spike-Timing Dependent Plasticity) 학습 규칙을 구현한 시냅스 모듈.
//   pre_spike와 post_spike의 순서를 비교하여 가중치(weight)를 자동 조절.
//
//   LTP (Long-Term Potentiation / 강화):
//     pre_spike → post_spike 순서 (인과관계 성립)
//     → weight = weight + LTP_STEP (최대 MAX_WEIGHT 클램핑)
//
//   LTD (Long-Term Depression / 약화):
//     post_spike → pre_spike 순서 (인과관계 불성립)
//     → weight = weight - LTD_STEP (최소 MIN_WEIGHT 클램핑)
//
// Parameters:
//   INIT_WEIGHT : 초기 가중치 (default 10)
//   MAX_WEIGHT  : 가중치 상한 (default 255)
//   MIN_WEIGHT  : 가중치 하한 (default 0)
//   LTP_STEP    : LTP 강화 스텝 (default 1)
//   LTD_STEP    : LTD 약화 스텝 (default 1)
//   TRACE_DECAY : 트레이스 유지 윈도우 (클럭 수, default 8)
//                 이 클럭 수 이내에 반대 스파이크가 오면 STDP 적용
//
// I/O:
//   clk             : 시스템 클럭
//   rst_n           : 비동기 액티브 로우 리셋
//   pre_spike       : 시냅스 전 뉴런(Pre-synaptic) 스파이크
//   post_spike      : 시냅스 후 뉴런(Post-synaptic) 스파이크
//   weighted_current: 출력 전류 = pre_spike가 1일 때 weight 값 전달
//   weight          : 현재 가중치 (모니터링용)
// =============================================================================

module synapse #(
    parameter [7:0] INIT_WEIGHT  = 8'd10,  // 초기 가중치
    parameter [7:0] MAX_WEIGHT   = 8'd255, // 가중치 상한
    parameter [7:0] MIN_WEIGHT   = 8'd0,   // 가중치 하한
    parameter [7:0] LTP_STEP     = 8'd1,   // LTP 강화 스텝
    parameter [7:0] LTD_STEP     = 8'd1,   // LTD 약화 스텝
    parameter [3:0] TRACE_DECAY  = 4'd8    // 스파이크 트레이스 유지 윈도우 (클럭)
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       pre_spike,        // Pre-synaptic 뉴런 스파이크
    input  wire       post_spike,       // Post-synaptic 뉴런 스파이크

    output wire [7:0] weighted_current, // Post 뉴런으로 전달할 전류
    output wire [7:0] weight            // 현재 가중치 (모니터링)
);

    // -------------------------------------------------------------------------
    // 내부 레지스터
    // -------------------------------------------------------------------------
    reg [7:0] weight_reg;       // 가중치 레지스터

    // 스파이크 트레이스 카운터
    // pre_trace  : pre_spike 발생 후 몇 클럭이 지났는지 카운트
    // post_trace : post_spike 발생 후 몇 클럭이 지났는지 카운트
    // 값이 0이면 "최근에 스파이크 없음", 양수면 "최근 스파이크 있음"
    reg [3:0] pre_trace;        // Pre-spike 트레이스 카운터
    reg [3:0] post_trace;       // Post-spike 트레이스 카운터

    // -------------------------------------------------------------------------
    // 가중치 업데이트 조합 논리
    // 9-bit 연산으로 오버플로우/언더플로우 감지 후 클램핑
    // -------------------------------------------------------------------------
    wire [8:0] weight_ltp = {1'b0, weight_reg} + {1'b0, LTP_STEP};
    wire [8:0] weight_ltd = {1'b0, weight_reg} - {1'b0, LTD_STEP};

    // LTP 적용 후 클램핑 (MAX_WEIGHT 초과 방지)
    wire [7:0] weight_after_ltp =
        (weight_ltp > {1'b0, MAX_WEIGHT}) ? MAX_WEIGHT : weight_ltp[7:0];

    // LTD 적용 후 클램핑 (MIN_WEIGHT 미만 방지, 언더플로우 감지)
    wire [7:0] weight_after_ltd =
        (weight_ltd[8]) ? MIN_WEIGHT :                          // 언더플로우
        (weight_ltd[7:0] < MIN_WEIGHT) ? MIN_WEIGHT :           // 최솟값 미만
        weight_ltd[7:0];

    // -------------------------------------------------------------------------
    // 순차 논리: 트레이스 업데이트 + STDP 가중치 조절
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight_reg <= INIT_WEIGHT;
            pre_trace  <= 4'd0;
            post_trace <= 4'd0;
        end
        else begin
            // -----------------------------------------------------------------
            // 트레이스 카운터 업데이트
            //   스파이크 발생 시 → 카운터를 TRACE_DECAY로 리셋 (최대값 설정)
            //   스파이크 없을 시 → 카운터를 1씩 감소 (0에서 멈춤)
            // -----------------------------------------------------------------
            if (pre_spike)
                pre_trace <= TRACE_DECAY;
            else if (pre_trace > 4'd0)
                pre_trace <= pre_trace - 4'd1;

            if (post_spike)
                post_trace <= TRACE_DECAY;
            else if (post_trace > 4'd0)
                post_trace <= post_trace - 4'd1;

            // -----------------------------------------------------------------
            // STDP 가중치 업데이트
            //
            // LTP: post_spike가 발생했을 때 pre_trace가 살아있으면
            //      → pre가 먼저 왔고 post가 나중에 왔다 = 인과관계 성립
            //      → 가중치 강화
            //
            // LTD: pre_spike가 발생했을 때 post_trace가 살아있으면
            //      → post가 먼저 왔고 pre가 나중에 왔다 = 인과관계 불성립
            //      → 가중치 약화
            //
            // 우선순위: LTP > LTD (동시 발생 시 LTP 우선)
            // -----------------------------------------------------------------
            if (post_spike && (pre_trace > 4'd0)) begin
                // LTP: pre → post 순서 확인됨 → 강화
                weight_reg <= weight_after_ltp;
            end
            else if (pre_spike && (post_trace > 4'd0)) begin
                // LTD: post → pre 순서 확인됨 → 약화
                weight_reg <= weight_after_ltd;
            end
            // 그 외: 가중치 유지
        end
    end

    // -------------------------------------------------------------------------
    // 출력 할당
    //   weighted_current: pre_spike가 1일 때만 weight를 전달
    //                     (스파이크가 없으면 전류 0)
    // -------------------------------------------------------------------------
    assign weighted_current = pre_spike ? weight_reg : 8'd0;
    assign weight           = weight_reg;

endmodule
// =============================================================================
// End of synapse.v
// =============================================================================
