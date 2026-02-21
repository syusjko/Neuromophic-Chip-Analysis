// =============================================================================
// Module  : phase_softmax (v3 - Lateral Inhibition + 잔재 수정)
// Project : Phase-based Spiking Transformer (PST)
//
// [v3 변경]
//   1. Accumulator 잔재 수정
//      cycle_start → rate 저장 + acc 즉시 리셋 (동일 클럭)
//      → 전환 시 이전 상태 완전 제거
//
//   2. Lateral Inhibition 추가 (softmax 대신)
//      winner 쌍이 나머지를 억제
//      억제 강도 = (winner_rel - pair_rel) × INHIBIT_GAIN
//      → 강한 쌍: 발화율 유지
//      → 약한 쌍: 억제로 발화율 감소
//      → 경쟁적 선택 (생물학적 softmax)
//
//   [생물학적 근거]
//   피질의 Lateral Inhibition:
//     강하게 발화하는 뉴런 → 주변 억제 인터뉴런 활성화
//     → 약한 뉴런 억제
//     → 승자 독식(WTA) 경향
//
//   [동작]
//   매 사이클:
//     1. Delta-Sigma로 기본 발화율 계산
//     2. winner 쌍 결정 (최대 Rel)
//     3. 비winner 쌍의 acc에서 억제량 차감
//        inhibit_i = (winner_rel - rel_i) × GAIN / 256
//     4. 결과: winner는 거의 그대로, 나머지는 억제
// =============================================================================

module phase_softmax #(
    parameter [8:0] THRESHOLD    = 9'd256,  // Delta-Sigma 임계값
    parameter [7:0] INHIBIT_GAIN = 8'd4     // 억제 강도 (클수록 WTA에 가까움)
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       cycle_start,

    input  wire [7:0] rel_ab, rel_ac, rel_ad,
    input  wire [7:0] rel_bc, rel_bd, rel_cd,

    output reg        spike_ab, spike_ac, spike_ad,
    output reg        spike_bc, spike_bd, spike_cd,

    output reg  [7:0] rate_ab, rate_ac, rate_ad,
    output reg  [7:0] rate_bc, rate_bd, rate_cd,

    output reg  [2:0] winner_out   // 이번 사이클 winner
);

    // -------------------------------------------------------------------------
    // 누적기 + 카운터
    // -------------------------------------------------------------------------
    reg [8:0] acc_ab, acc_ac, acc_ad;
    reg [8:0] acc_bc, acc_bd, acc_cd;
    reg [8:0] a;

    reg [7:0] cnt_ab, cnt_ac, cnt_ad;
    reg [7:0] cnt_bc, cnt_bd, cnt_cd;

    // -------------------------------------------------------------------------
    // Winner 조합 논리 (현재 Rel 기준)
    // -------------------------------------------------------------------------
    reg [2:0]  winner_comb;
    reg [7:0]  winner_rel_comb;

    always @(*) begin
        winner_comb     = 3'd0; winner_rel_comb = rel_ab;
        if (rel_ac > winner_rel_comb) begin winner_comb=3'd1; winner_rel_comb=rel_ac; end
        if (rel_ad > winner_rel_comb) begin winner_comb=3'd2; winner_rel_comb=rel_ad; end
        if (rel_bc > winner_rel_comb) begin winner_comb=3'd3; winner_rel_comb=rel_bc; end
        if (rel_bd > winner_rel_comb) begin winner_comb=3'd4; winner_rel_comb=rel_bd; end
        if (rel_cd > winner_rel_comb) begin winner_comb=3'd5; winner_rel_comb=rel_cd; end
    end

    // -------------------------------------------------------------------------
    // 억제량 계산: inhibit_i = (winner_rel - rel_i) * GAIN / 16
    // -------------------------------------------------------------------------
    wire [7:0] inh_ab = ((winner_rel_comb > rel_ab) ?
                         ((winner_rel_comb - rel_ab) >> 4) * INHIBIT_GAIN : 8'd0);
    wire [7:0] inh_ac = ((winner_rel_comb > rel_ac) ?
                         ((winner_rel_comb - rel_ac) >> 4) * INHIBIT_GAIN : 8'd0);
    wire [7:0] inh_ad = ((winner_rel_comb > rel_ad) ?
                         ((winner_rel_comb - rel_ad) >> 4) * INHIBIT_GAIN : 8'd0);
    wire [7:0] inh_bc = ((winner_rel_comb > rel_bc) ?
                         ((winner_rel_comb - rel_bc) >> 4) * INHIBIT_GAIN : 8'd0);
    wire [7:0] inh_bd = ((winner_rel_comb > rel_bd) ?
                         ((winner_rel_comb - rel_bd) >> 4) * INHIBIT_GAIN : 8'd0);
    wire [7:0] inh_cd = ((winner_rel_comb > rel_cd) ?
                         ((winner_rel_comb - rel_cd) >> 4) * INHIBIT_GAIN : 8'd0);

    // -------------------------------------------------------------------------
    // 순차 논리: Delta-Sigma + Lateral Inhibition
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_ab<=0; acc_ac<=0; acc_ad<=0;
            acc_bc<=0; acc_bd<=0; acc_cd<=0;
            spike_ab<=0; spike_ac<=0; spike_ad<=0;
            spike_bc<=0; spike_bd<=0; spike_cd<=0;
            rate_ab<=0; rate_ac<=0; rate_ad<=0;
            rate_bc<=0; rate_bd<=0; rate_cd<=0;
            cnt_ab<=0; cnt_ac<=0; cnt_ad<=0;
            cnt_bc<=0; cnt_bd<=0; cnt_cd<=0;
            winner_out <= 3'd0;
        end
        else if (cycle_start) begin
            // ── 수정 1: 동일 클럭에 rate 저장 + acc 즉시 리셋 ──
            rate_ab <= cnt_ab; rate_ac <= cnt_ac; rate_ad <= cnt_ad;
            rate_bc <= cnt_bc; rate_bd <= cnt_bd; rate_cd <= cnt_cd;
            winner_out <= winner_comb;
            // 즉시 리셋 (잔재 제거)
            cnt_ab<=0; cnt_ac<=0; cnt_ad<=0;
            cnt_bc<=0; cnt_bd<=0; cnt_cd<=0;
            acc_ab<=0; acc_ac<=0; acc_ad<=0;  // ← 핵심: 즉시 리셋
            acc_bc<=0; acc_bd<=0; acc_cd<=0;
            spike_ab<=0; spike_ac<=0; spike_ad<=0;
            spike_bc<=0; spike_bd<=0; spike_cd<=0;
        end
        else begin
            // ── Delta-Sigma + Lateral Inhibition ──

            // AB: Rel 누적 - 억제량
            a = acc_ab + {1'b0, rel_ab};
            if (a >= {1'b0, inh_ab})
                a = a - {1'b0, inh_ab};  // 억제 적용
            else
                a = 9'd0;
            if (a >= THRESHOLD) begin spike_ab<=1; acc_ab<=a-THRESHOLD; cnt_ab<=cnt_ab+1; end
            else                begin spike_ab<=0; acc_ab<=a; end

            // AC
            a = acc_ac + {1'b0, rel_ac};
            if (a >= {1'b0, inh_ac}) a = a - {1'b0, inh_ac}; else a = 9'd0;
            if (a >= THRESHOLD) begin spike_ac<=1; acc_ac<=a-THRESHOLD; cnt_ac<=cnt_ac+1; end
            else                begin spike_ac<=0; acc_ac<=a; end

            // AD
            a = acc_ad + {1'b0, rel_ad};
            if (a >= {1'b0, inh_ad}) a = a - {1'b0, inh_ad}; else a = 9'd0;
            if (a >= THRESHOLD) begin spike_ad<=1; acc_ad<=a-THRESHOLD; cnt_ad<=cnt_ad+1; end
            else                begin spike_ad<=0; acc_ad<=a; end

            // BC
            a = acc_bc + {1'b0, rel_bc};
            if (a >= {1'b0, inh_bc}) a = a - {1'b0, inh_bc}; else a = 9'd0;
            if (a >= THRESHOLD) begin spike_bc<=1; acc_bc<=a-THRESHOLD; cnt_bc<=cnt_bc+1; end
            else                begin spike_bc<=0; acc_bc<=a; end

            // BD
            a = acc_bd + {1'b0, rel_bd};
            if (a >= {1'b0, inh_bd}) a = a - {1'b0, inh_bd}; else a = 9'd0;
            if (a >= THRESHOLD) begin spike_bd<=1; acc_bd<=a-THRESHOLD; cnt_bd<=cnt_bd+1; end
            else                begin spike_bd<=0; acc_bd<=a; end

            // CD
            a = acc_cd + {1'b0, rel_cd};
            if (a >= {1'b0, inh_cd}) a = a - {1'b0, inh_cd}; else a = 9'd0;
            if (a >= THRESHOLD) begin spike_cd<=1; acc_cd<=a-THRESHOLD; cnt_cd<=cnt_cd+1; end
            else                begin spike_cd<=0; acc_cd<=a; end
        end
    end

endmodule
// =============================================================================
// End of phase_softmax.v (v3)
// =============================================================================
