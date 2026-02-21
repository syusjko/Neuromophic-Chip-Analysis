// =============================================================================
// Module  : phase_neuron
// Project : Phase-based Spiking Transformer (PST)
//
// Description:
//   위상 코딩(Phase Coding) 뉴런.
//   입력 전류의 강도를 발화 위상으로 변환.
//
//   [핵심 원리]
//   감마 사이클(0~255) 내에서:
//     강한 입력 → 낮은 위상(초반)에서 발화
//     약한 입력 → 높은 위상(후반)에서 발화
//     입력 없음 → 발화 안 함
//
//   [수식]
//   fire_phase = CYCLE_LEN - (input_current / THRESHOLD × CYCLE_LEN)
//   → input이 THRESHOLD 이상이면 위상 0에서 발화
//   → input이 THRESHOLD/2이면 위상 128에서 발화
//   → input이 0이면 발화 안 함
//
//   [왜 이게 Attention인가]
//   두 뉴런의 발화 위상이 가까울수록 = 두 입력이 비슷한 강도
//   Coincidence Detector가 이를 감지 = 관련성 계산
//   = 행렬 곱셈 없는 Attention!
//
//   [출력]
//   spike_out:  발화 펄스 (1클럭)
//   phase_lock: 발화한 위상값 (다음 사이클까지 유지)
//   fired:      이번 사이클에 발화했는지 여부
// =============================================================================

module phase_neuron #(
    parameter [7:0] THRESHOLD  = 8'd64,   // 발화 최소 입력 강도
    parameter [7:0] LEAK       = 8'd8,    // 사이클 내 누설
    parameter [7:0] CYCLE_LEN  = 8'd255   // 감마 사이클 길이
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] global_phase,    // gamma_oscillator에서 오는 위상
    input  wire       cycle_start,     // 사이클 시작 펄스
    input  wire [7:0] input_current,   // 시냅스 입력 전류

    output reg        spike_out,       // 발화 펄스
    output reg  [7:0] phase_lock,      // 발화한 위상 (유지됨)
    output reg        fired_this_cycle // 이번 사이클 발화 여부
);

    reg [7:0] v_mem;        // 막전위 누적기
    reg       has_fired;    // 이번 사이클 발화 플래그 (중복 발화 방지)
    reg [8:0] v_next;       // 다음 막전위 (9비트 오버플로우 감지용)

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_mem           <= 8'd0;
            spike_out       <= 1'b0;
            phase_lock      <= 8'd255;  // 발화 안 함 = 최대 위상
            fired_this_cycle<= 1'b0;
            has_fired       <= 1'b0;
            v_next          <= 9'd0;
        end
        else begin
            spike_out <= 1'b0;  // 기본값: 발화 없음

            // ─────────────────────────────────────────────────────
            // 사이클 시작: 막전위 리셋, 발화 플래그 리셋
            // ─────────────────────────────────────────────────────
            if (cycle_start) begin
                v_mem            <= 8'd0;
                has_fired        <= 1'b0;
                fired_this_cycle <= 1'b0;
            end
            else if (!has_fired) begin
                // ─────────────────────────────────────────────────
                // 막전위 누적
                // ─────────────────────────────────────────────────
                v_next = {1'b0, v_mem} + {1'b0, input_current};
                v_mem  <= v_next[8] ? 8'd255 : v_next[7:0];

                // ─────────────────────────────────────────────────
                // 임계값 초과 → 발화 (위상 기록)
                // ─────────────────────────────────────────────────
                if (v_next[8] || v_next[7:0] >= THRESHOLD) begin
                    spike_out        <= 1'b1;
                    phase_lock       <= global_phase;
                    fired_this_cycle <= 1'b1;
                    has_fired        <= 1'b1;
                    v_mem            <= 8'd0;
                end
            end
        end
    end

endmodule
// =============================================================================
// End of phase_neuron.v
// =============================================================================

