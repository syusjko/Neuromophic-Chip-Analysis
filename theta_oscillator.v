// =============================================================================
// Module: theta_oscillator
// Project: Phase-based Spiking Transformer - V3.1
//
// [역할]
//   감마 진동(30-80Hz)을 8개 묶어 세타 에피소드(4-8Hz) 경계 생성
//   뇌에서: 해마 theta파가 여러 개의 gamma 사이클을 하나의 에피소드로 묶음
//           예: "I am a boy" = 4단어 = 4 gamma burst = 하나의 theta 에피소드
//
// [포트]
//   gamma_tick: gamma_oscillator의 cyc_start (매 256 클럭마다 1클럭 펄스)
//   theta_tick: 매 GAMMA_PER_THETA gamma 사이클마다 1클럭 펄스 (에피소드 종료)
//   gamma_cnt:  현재 에피소드 내 gamma 위치 (0 ~ GAMMA_PER_THETA-1)
//
// [타이밍 예]
//   GAMMA_PER_THETA=8:
//   gamma 0→7: gamma_cnt 0~7
//   gamma 7 완료: theta_tick=1 (에피소드 경계)
//   gamma 8: 새 에피소드 시작 (gamma_cnt=0)
// =============================================================================

module theta_oscillator #(
    parameter [2:0] GAMMA_PER_THETA = 3'd7  // 8 gamma per theta (0~7)
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       gamma_tick,   // gamma 사이클 시작 펄스 (cyc_start)

    output reg  [2:0] gamma_cnt,    // 에피소드 내 gamma 위치
    output reg        theta_tick,   // 에피소드 경계 (8 gamma마다 1클럭)
    output wire       episode_last  // gamma_cnt==7: 에피소드 마지막 gamma
);
    assign episode_last = (gamma_cnt == GAMMA_PER_THETA);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gamma_cnt  <= 3'd0;
            theta_tick <= 1'b0;
        end
        else begin
            theta_tick <= 1'b0;  // 기본 0 (펄스, 1클럭만)
            if (gamma_tick) begin
                if (gamma_cnt >= GAMMA_PER_THETA) begin
                    // 에피소드 완료: 리셋 + theta_tick 발생
                    gamma_cnt  <= 3'd0;
                    theta_tick <= 1'b1;
                end
                else begin
                    gamma_cnt <= gamma_cnt + 3'd1;
                end
            end
        end
    end
endmodule
