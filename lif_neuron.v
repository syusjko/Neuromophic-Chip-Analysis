// =============================================================================
// Module  : lif_neuron (v2 - STDP 연동 버전)
// Project : Neuromorphic Chip
//
// [변경 사항 from v1]
//   - WEIGHT 파라미터 제거
//   - spike_in 제거
//   - input_current [7:0] 추가: 시냅스가 계산한 전류를 직접 입력받음
//     (시냅스가 "spike × weight" 계산 후 전달)
//
// Description:
//   매 클럭마다:
//     1. LEAK만큼 막전위 감소 (Underflow 방지)
//     2. input_current를 막전위에 더함 (Overflow 포화 처리)
//     3. THRESHOLD 초과 시 spike_out=1, 다음 클럭에 v_mem=0 리셋
// =============================================================================

module lif_neuron #(
    parameter [7:0] THRESHOLD = 8'd127,  // 발화 임계값
    parameter [7:0] LEAK      = 8'd5     // 클럭당 누설 전류
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] input_current,     // 시냅스로부터 받는 입력 전류

    output reg        spike_out,         // 발화 출력
    output wire [7:0] v_mem              // 막전위 모니터링
);

    // -------------------------------------------------------------------------
    // 내부 레지스터
    // -------------------------------------------------------------------------
    reg [7:0] v_mem_reg;

    // -------------------------------------------------------------------------
    // 조합 논리: Leak 감소 (9-bit 언더플로우 감지)
    // -------------------------------------------------------------------------
    wire [8:0] v_after_leak   = {1'b0, v_mem_reg} - {1'b0, LEAK};
    wire [7:0] v_leak_clamped = v_after_leak[8] ? 8'd0 : v_after_leak[7:0];

    // -------------------------------------------------------------------------
    // 조합 논리: 입력 전류 적분 (9-bit 오버플로우 감지 → 255 포화)
    // -------------------------------------------------------------------------
    wire [8:0] v_after_current = {1'b0, v_leak_clamped} + {1'b0, input_current};
    wire [7:0] v_integrated    = v_after_current[8] ? 8'd255 : v_after_current[7:0];

    // -------------------------------------------------------------------------
    // 순차 논리: 막전위 업데이트
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_mem_reg <= 8'd0;
            spike_out <= 1'b0;
        end
        else begin
            if (spike_out) begin
                // 발화 직후: 절대 불응기 → 막전위 리셋
                v_mem_reg <= 8'd0;
                spike_out <= 1'b0;
            end
            else begin
                if (v_integrated > THRESHOLD) begin
                    // 임계값 초과 → 발화
                    v_mem_reg <= v_integrated;
                    spike_out <= 1'b1;
                end
                else begin
                    v_mem_reg <= v_integrated;
                    spike_out <= 1'b0;
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // 출력
    // -------------------------------------------------------------------------
    assign v_mem = v_mem_reg;

endmodule
// =============================================================================
// End of lif_neuron.v (v2)
// =============================================================================
