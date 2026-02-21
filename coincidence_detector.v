// =============================================================================
// Module  : coincidence_detector (v2 - 정확한 circular similarity)
// Project : Phase-based Spiking Transformer (PST)
//
// [v2 수정]
//   GPT 지적 사항 수정:
//   1. wrap-around 계산 정확히 구현
//   2. 9비트 연산으로 언더플로우 방지
//   3. 결과를 같은 사이클에 출력 (combinational)
//
//   [정확한 위상 유사도]
//   Δ = min(|a-b|, 256-|a-b|)   ← 원형 공간 최단 거리
//   Rel = 255 - Δ               ← 유사도 (가까울수록 높음)
//
//   [수학적 성질]
//   - 대칭: Rel(A,B) = Rel(B,A)
//   - 최대: A=B → Δ=0 → Rel=255
//   - 최소: |A-B|=128 → Δ=128 → Rel=127
//   - 단조: 위상 차이 증가 → Rel 감소
//
//   이 성질들이 Transformer QK^T와 동일한 구조
// =============================================================================

module coincidence_detector #(
    parameter [7:0] PHASE_TOL  = 8'd20,
    parameter [7:0] CYCLE_LEN  = 8'd255
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       fired_a,
    input  wire       fired_b,
    input  wire [7:0] phase_a,
    input  wire [7:0] phase_b,
    input  wire       cycle_start,

    output reg  [7:0] relevance,
    output reg        coincident
);

    // -------------------------------------------------------------------------
    // 조합 논리: 정확한 circular phase difference
    // -------------------------------------------------------------------------
    // 9비트로 확장하여 언더플로우 방지
    wire [8:0] pa = {1'b0, phase_a};
    wire [8:0] pb = {1'b0, phase_b};

    // |a - b| (절댓값)
    wire [8:0] diff_raw = (pa >= pb) ? (pa - pb) : (pb - pa);

    // circular 최단 거리: min(diff, 256-diff)
    wire [8:0] diff_wrap = 9'd256 - diff_raw;
    wire [7:0] phase_diff = (diff_raw <= diff_wrap) ?
                             diff_raw[7:0] : diff_wrap[7:0];

    // 유사도 = 255 - 최단 거리
    wire [7:0] rel_score = 8'd255 - phase_diff;

    // -------------------------------------------------------------------------
    // 순차 논리: 사이클 시작 시 결과 래치
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            relevance  <= 8'd0;
            coincident <= 1'b0;
        end
        else if (cycle_start) begin
            if (fired_a && fired_b) begin
                relevance  <= rel_score;
                coincident <= (phase_diff <= PHASE_TOL) ? 1'b1 : 1'b0;
            end
            else begin
                relevance  <= 8'd0;
                coincident <= 1'b0;
            end
        end
    end

endmodule
// =============================================================================
// End of coincidence_detector.v (v2)
// =============================================================================
