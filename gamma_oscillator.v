// =============================================================================
// Module  : gamma_oscillator
// Project : Phase-based Spiking Transformer (PST)
//
// Description:
//   뇌의 감마파(Gamma Oscillation, ~40Hz)를 모사하는 전역 위상 생성기.
//   모든 phase_neuron이 이 신호를 공유 → 공통 시간 기준
//
//   [생물학적 대응]
//   해마/피질의 감마 오실레이션
//   → 뉴런들이 이 리듬에 맞춰 발화 위상을 결정
//
//   [동작]
//   CYCLE_LEN 클럭마다 위상 0→CYCLE_LEN-1 반복
//   cycle_start: 사이클 시작 펄스 (1클럭)
//   phase_out:   현재 위상 (0 ~ CYCLE_LEN-1)
//
//   [파라미터]
//   CYCLE_LEN = 256: 위상 해상도 8비트
//                    → 256단계로 입력 강도 표현
// =============================================================================

module gamma_oscillator #(
    parameter [8:0] CYCLE_LEN = 9'd256  // 위상 해상도
)(
    input  wire       clk,
    input  wire       rst_n,
    output reg  [7:0] phase_out,    // 현재 위상 (0~255)
    output reg        cycle_start   // 사이클 시작 펄스
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_out   <= 8'd0;
            cycle_start <= 1'b0;
        end
        else begin
            if (phase_out == CYCLE_LEN - 1) begin
                phase_out   <= 8'd0;
                cycle_start <= 1'b1;  // 다음 클럭에 새 사이클
            end
            else begin
                phase_out   <= phase_out + 8'd1;
                cycle_start <= 1'b0;
            end
        end
    end

endmodule
// =============================================================================
// End of gamma_oscillator.v
// =============================================================================
