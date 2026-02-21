// =============================================================================
// Module  : phase_stdp
// Project : Phase-based Spiking Transformer (PST)
//
// [역할]
//   위상 기반 STDP (Spike-Timing Dependent Plasticity)
//   단층 시냅스 가중치 학습 (Phase 2)
//   예측 코딩의 기초 회로 (Phase 3 전단계)
//
// [STDP 원칙]
//   pre 뉴런이 post 뉴런보다 먼저 발화 (pre → post, Δt > 0)
//     → 인과적 관계 → 시냅스 강화 (LTP)
//
//   post 뉴런이 pre 뉴런보다 먼저 발화 (post → pre, Δt < 0)
//     → 비인과적 관계 → 시냅스 약화 (LTD)
//
// [위상 기반 구현]
//   위상 = 발화 타이밍 → 위상 차이 = Δt
//
//   phase_pre < phase_post: pre가 먼저 발화 → LTP (+)
//   phase_pre > phase_post: post가 먼저 발화 → LTD (-)
//   |차이| 클수록 약한 업데이트 (멀수록 약한 상관)
//
//   ΔW = η × f(Δphase)
//   f(Δphase) = +A_LTP × exp(-Δphase / τ)  [Δphase > 0]
//             = -A_LTD × exp(+Δphase / τ)  [Δphase < 0]
//
// [하드웨어 근사]
//   exp 생략 → 선형 근사
//   ΔW = +η  [pre 먼저]
//   ΔW = -η  [post 먼저]
//   |Δphase| > WINDOW → 업데이트 없음 (상관 없음)
//
// [포트]
//   phase_pre [7:0] : pre 뉴런 발화 위상
//   phase_post[7:0] : post 뉴런 발화 위상
//   fired_pre       : pre 뉴런 이번 사이클 발화 여부
//   fired_post      : post 뉴런 이번 사이클 발화 여부
//   cycle_start     : 가중치 업데이트 타이밍
//   weight [7:0]    : 현재 시냅스 가중치 (읽기)
//   weight_out[7:0] : 업데이트된 가중치 (쓰기)
//   ltp_event       : LTP 발생 (모니터링)
//   ltd_event       : LTD 발생 (모니터링)
// =============================================================================

module phase_stdp #(
    parameter [7:0] W_INIT   = 8'd128,  // 초기 가중치 (중간)
    parameter [7:0] W_MAX    = 8'd255,  // 최대 가중치
    parameter [7:0] W_MIN    = 8'd1,    // 최소 가중치 (0이면 완전 차단)
    parameter [7:0] ETA_LTP  = 8'd4,    // LTP 학습률
    parameter [7:0] ETA_LTD  = 8'd3,    // LTD 학습률 (약간 작게 → 순 강화 경향)
    parameter [7:0] WINDOW   = 8'd30    // 위상 상관 윈도우 (이 안에서만 업데이트)
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       cycle_start,      // 감마 사이클 시작 (업데이트 타이밍)

    input  wire [7:0] phase_pre,        // pre 뉴런 발화 위상
    input  wire [7:0] phase_post,       // post 뉴런 발화 위상
    input  wire       fired_pre,        // pre 이번 사이클 발화
    input  wire       fired_post,       // post 이번 사이클 발화

    // [신규] 동적 학습률 부스트 (상위층 오차 신호)
    // 0: 기본 ETA 사용, 1~N: ETA_LTP/LTD에 더해짐
    input  wire [7:0] eta_boost,

    output reg  [7:0] weight,           // 현재 시냅스 가중치
    output reg        ltp_event,        // LTP 발생 플래그
    output reg        ltd_event         // LTD 발생 플래그
);

    // -------------------------------------------------------------------------
    // 위상 차이 (circular)
    // Δphase = phase_pre - phase_post (부호 있음, 9비트)
    // -------------------------------------------------------------------------
    wire [7:0] raw_diff = phase_pre - phase_post;  // unsigned 뺄셈

    // circular 보정: 더 짧은 방향 사용
    // diff_abs = min(raw_diff, 256 - raw_diff)
    wire [7:0] inv_diff   = 8'd255 - raw_diff + 8'd1; // 256 - raw_diff
    wire [7:0] diff_abs   = (raw_diff <= inv_diff) ? raw_diff : inv_diff;

    // pre/post 먼저 발화 판단 (별도 wire로 분리)
    // phase_pre < phase_post → 언더플로우 → raw_diff[7]=1 → pre 먼저 → LTP
    // phase_pre > phase_post → 정상 양수  → raw_diff[7]=0 → post 먼저 → LTD
    // phase_pre == phase_post → raw_diff=0 → 둘 다 FALSE → 업데이트 없음
    // pre/post 먼저 발화 판단
    wire pre_first  = (raw_diff[7] == 1'b1) && (raw_diff != 8'd0);
    wire post_first = (raw_diff[7] == 1'b0) && (raw_diff != 8'd0);

    // -------------------------------------------------------------------------
    // 동적 학습률: ETA + eta_boost
    // eta_boost = 0: 기본
    // eta_boost = k: 상위층 오차 k만큼 ETA 증가
    // -------------------------------------------------------------------------
    wire [8:0] dyn_ltp = {1'b0, ETA_LTP} + {1'b0, eta_boost};
    wire [8:0] dyn_ltd = {1'b0, ETA_LTD} + {1'b0, eta_boost};
    wire [7:0] eff_ltp = (dyn_ltp > 9'd255) ? 8'd255 : dyn_ltp[7:0];
    wire [7:0] eff_ltd = (dyn_ltd > 9'd255) ? 8'd255 : dyn_ltd[7:0];

    // -------------------------------------------------------------------------
    // 가중치 업데이트
    // -------------------------------------------------------------------------
    reg [8:0] w_next;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            weight    <= W_INIT;
            ltp_event <= 1'b0;
            ltd_event <= 1'b0;
        end
        else if (cycle_start) begin
            ltp_event <= 1'b0;
            ltd_event <= 1'b0;

            if (fired_pre && fired_post && (diff_abs <= WINDOW)) begin
                if (pre_first) begin
                    // LTP: 동적 학습률 적용
                    w_next = {1'b0, weight} + {1'b0, eff_ltp};
                    weight    <= (w_next > {1'b0, W_MAX}) ? W_MAX : w_next[7:0];
                    ltp_event <= 1'b1;
                end
                else if (post_first) begin
                    // LTD: 동적 학습률 적용
                    if (weight > eff_ltd + W_MIN)
                        weight <= weight - eff_ltd;
                    else
                        weight <= W_MIN;
                    ltd_event <= 1'b1;
                end
            end
        end
    end

endmodule
// =============================================================================
// End of phase_stdp.v
//
// [다음 단계: predictive_phase.v (Phase 3)]
//   phase_stdp + 예측 위상 생성
//   top-down: 상위 층 → 예측 위상
//   bottom-up: 실제 위상 - 예측 위상 = 오차
//   오차 → STDP 방향 결정
//   → Credit Assignment 해결
// =============================================================================
