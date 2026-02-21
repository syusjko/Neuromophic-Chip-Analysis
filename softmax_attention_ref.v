// =============================================================================
// Module  : softmax_attention_ref
// Project : PST vs Softmax 비교 기준 (Reference Implementation)
//
// Description:
//   N=4 토큰, WIDTH=8비트 기준 Softmax Attention RTL.
//   PST_core와 동일 입력/출력 인터페이스.
//
//   [동작]
//   1. Q·K 내적 계산 (8비트 × 8비트 = 16비트)
//   2. exp 근사 (LUT 기반, 8비트 입력 → 16비트 출력)
//   3. 정규화 (합산 후 나눗셈)
//   4. winner 선택 (argmax)
//
//   [비교 지표]
//   - LUT 사용량 (합성 후)
//   - Fmax (합성 후)
//   - 동적 전력 (합성 후)
//   - winner 일치율 (PST_core와 비교)
//
//   [구현 단순화]
//   실제 softmax의 exp는 하드웨어 비용이 매우 큼.
//   여기서는 piecewise linear 근사 사용:
//     exp(x) ≈ 1 + x + x²/2  (x가 작을 때)
//   8비트 입력 범위에서 LUT로 구현.
//
//   [포트]
//   q[3:0][7:0]: Query 벡터 (4토큰 × 8비트)
//   k[3:0][7:0]: Key 벡터 (4토큰 × 8비트)
//   winner[1:0]: 가장 높은 attention score 토큰
//   score[3:0][7:0]: 정규화된 attention score
// =============================================================================

module softmax_attention_ref #(
    parameter N     = 4,   // 토큰 수
    parameter WIDTH = 8    // 비트 폭
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,   // 입력 유효

    // Query, Key (각 N개, WIDTH비트)
    input  wire [WIDTH-1:0] q0, q1, q2, q3,
    input  wire [WIDTH-1:0] k0, k1, k2, k3,

    // 출력
    output reg  [1:0]       winner,      // 가장 높은 attention 토큰
    output reg  [WIDTH-1:0] score0, score1, score2, score3,  // 정규화 score
    output reg              valid_out
);

    // -------------------------------------------------------------------------
    // Stage 1: Q·K 내적 (각 토큰 쌍)
    // 4토큰이면 Query 하나에 대해 4개 Key와 내적
    // 여기선 Query=q0 고정 (단순화)
    // -------------------------------------------------------------------------
    reg [15:0] dot0, dot1, dot2, dot3;  // q0·k0, q0·k1, q0·k2, q0·k3

    // -------------------------------------------------------------------------
    // Stage 2: exp 근사 LUT (8비트 입력 → 8비트 출력)
    // exp(x/32) 근사: x=0→1, x=255→2048 (8비트로 클램핑)
    // 실제로는 dot을 스케일링 후 LUT 통과
    // -------------------------------------------------------------------------
    reg [7:0] exp0, exp1, exp2, exp3;

    // exp 근사 함수 (piecewise linear, 8구간)
    function [7:0] exp_approx;
        input [7:0] x;
        begin
            // x를 8구간으로 나눠 선형 근사
            // exp(x/64): x=0→1.0, x=64→1.65, x=128→2.72, x=192→4.48, x=255→7.4
            // 8비트 정규화: 1.0→34, 7.4→255
            casez (x[7:5])
                3'b000: exp_approx = 8'd34  + x[4:0];          // 34~65
                3'b001: exp_approx = 8'd66  + x[4:0];          // 66~97
                3'b010: exp_approx = 8'd98  + (x[4:0] << 1);   // 98~160
                3'b011: exp_approx = 8'd162 + (x[4:0] << 1);   // 162~224
                3'b1??: exp_approx = 8'd255;                    // 포화
                default: exp_approx = 8'd34;
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // Stage 3: 정규화 (합산 후 나눗셈)
    // -------------------------------------------------------------------------
    reg [9:0] exp_sum;  // 최대 4×255=1020, 10비트
    reg [7:0] norm0, norm1, norm2, norm3;

    // -------------------------------------------------------------------------
    // Stage 4: argmax winner
    // -------------------------------------------------------------------------
    reg [1:0] winner_comb;
    reg [7:0] max_score;

    // 파이프라인 (3단계)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dot0<=0; dot1<=0; dot2<=0; dot3<=0;
            exp0<=0; exp1<=0; exp2<=0; exp3<=0;
            exp_sum<=0;
            norm0<=0; norm1<=0; norm2<=0; norm3<=0;
            winner<=0; score0<=0; score1<=0; score2<=0; score3<=0;
            valid_out<=0;
        end
        else begin
            valid_out <= 1'b0;

            if (valid_in) begin
                // Stage 1: 내적 (q0 기준)
                dot0 <= q0 * k0;
                dot1 <= q0 * k1;
                dot2 <= q0 * k2;
                dot3 <= q0 * k3;

                // Stage 2: exp 근사
                // dot은 8비트×8비트=16비트, 상위 8비트는 너무 큼
                // → 하위 8비트(dot[7:0])를 스케일링해서 사용
                exp0 <= exp_approx(dot0[7:0]);
                exp1 <= exp_approx(dot1[7:0]);
                exp2 <= exp_approx(dot2[7:0]);
                exp3 <= exp_approx(dot3[7:0]);

                // Stage 3: 정규화 (10비트 합산)
                exp_sum <= {2'b0,exp0} + {2'b0,exp1} +
                           {2'b0,exp2} + {2'b0,exp3};

                // 나눗셈: score_i = exp_i * 255 / exp_sum
                // exp_sum은 최대 4*255=1020 → 10비트
                if (exp_sum > 0) begin
                    norm0 <= ({2'b0,exp0} * 8'd255) / exp_sum;
                    norm1 <= ({2'b0,exp1} * 8'd255) / exp_sum;
                    norm2 <= ({2'b0,exp2} * 8'd255) / exp_sum;
                    norm3 <= ({2'b0,exp3} * 8'd255) / exp_sum;
                end else begin
                    norm0<=64; norm1<=64; norm2<=64; norm3<=64;
                end

                // Stage 4: argmax
                score0 <= norm0; score1 <= norm1;
                score2 <= norm2; score3 <= norm3;

                winner_comb = 2'd0; max_score = norm0;
                if (norm1 > max_score) begin winner_comb=2'd1; max_score=norm1; end
                if (norm2 > max_score) begin winner_comb=2'd2; max_score=norm2; end
                if (norm3 > max_score) begin winner_comb=2'd3; max_score=norm3; end
                winner <= winner_comb;

                valid_out <= 1'b1;
            end
        end
    end

endmodule
// =============================================================================
// End of softmax_attention_ref.v
//
// [합성 후 비교 지표]
// LUT:   예상 ~200-400 LUT (곱셈기 때문에 큼)
// Fmax:  예상 ~100-150 MHz
// Power: 예상 ~50-100 mW (FPGA 기준)
//
// PST_core 예상:
// LUT:   ~50-100 LUT (비교기, 누산기만)
// Fmax:  ~200-300 MHz
// Power: ~5-20 mW
//
// 이 차이가 논문의 핵심 Figure
// =============================================================================
