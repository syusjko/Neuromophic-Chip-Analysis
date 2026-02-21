// =============================================================================
// Module  : theta_seq_predictor (v2)
//
// [버그 수정]
//   v1: global_phase[7:5] → cycle_start일 때 항상 0 (phase=0)
//   v2: 내부 gamma cycle 카운터 사용
//       cycle_start마다 theta_cycle++ (0→1→...→7→0)
//
// [Theta-Gamma 대응]
//   gamma 1사이클 = 256클럭 (감마 오실레이터)
//   theta 1사이클 = 8 gamma 사이클
//   = 뇌의 theta(~8Hz):gamma(~40Hz) 비율과 동일 구조
//
//   이제 slot[0]은 gamma사이클 0,8,16,... 에서 관측
//       slot[1]은 gamma사이클 1,9,17,... 에서 관측
//       → 교번 패턴에서 slot[짝수]≈A, slot[홀수]≈B 분리 가능
// =============================================================================

module theta_seq_predictor #(
    parameter [7:0] W_INIT = 8'd128,
    parameter [7:0] ETA    = 8'd4
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       cycle_start,   // gamma 사이클 시작 (이걸로 theta 카운트)
    input  wire [7:0] global_phase,  // 사용 안 함 (호환성 유지)

    input  wire [7:0] actual_phase,
    input  wire       fired,

    output reg  [7:0] pred_next,
    output reg  [7:0] error_out,
    output reg        error_valid,

    // 디버그용
    output wire [2:0] theta_out,
    output wire [7:0] slot0_out,
    output wire [7:0] slot4_out
);

    // -------------------------------------------------------------------------
    // Theta cycle counter (gamma 사이클마다 1씩 증가)
    // -------------------------------------------------------------------------
    reg [2:0] theta_cycle;   // 0~7
    wire [2:0] theta_now  = theta_cycle;
    wire [2:0] theta_next = theta_cycle + 3'd1;  // 자동 wrap

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) theta_cycle <= 3'd0;
        else if (cycle_start) theta_cycle <= theta_cycle + 3'd1;
    end

    // -------------------------------------------------------------------------
    // 8개 슬롯 메모리
    // 초기값: 0 (128 아님! top-down이 L2를 잡아당기지 않도록)
    // -------------------------------------------------------------------------
    reg [7:0] slot [0:7];
    integer   k;

    assign theta_out  = theta_now;
    assign slot0_out  = slot[0];
    assign slot4_out  = slot[4];

    // -------------------------------------------------------------------------
    // 오차 계산: actual vs slot[theta_now]
    // -------------------------------------------------------------------------
    wire [7:0] raw_e  = actual_phase - slot[theta_now];
    wire [7:0] inv_e  = 8'd255 - raw_e + 8'd1;
    wire [7:0] err_ab = (raw_e <= inv_e) ? raw_e : inv_e;
    wire       dn_dir = (raw_e[7] == 1'b1) && (raw_e != 8'd0);
    wire       up_dir = (raw_e[7] == 1'b0) && (raw_e != 8'd0);
    wire [7:0] step   = (err_ab[7:2] > 8'd1) ? err_ab[7:2] : 8'd1;

    reg [8:0] slot_up;

    // -------------------------------------------------------------------------
    // 슬롯 업데이트 + 예측 출력
    // -------------------------------------------------------------------------
    // 최소 1 theta 사이클(8 gamma 사이클) 학습 후 pred_valid 활성화
    reg [3:0] warmup_cnt;  // 8 gamma 사이클 대기
    reg       warmed_up;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k=0; k<8; k=k+1) slot[k] <= 8'd0;  // 초기값 0
            pred_next   <= 8'd0;
            error_out   <= 8'd0;
            error_valid <= 1'b0;
            warmup_cnt  <= 4'd0;
            warmed_up   <= 1'b0;
        end
        else if (cycle_start) begin
            // warmup 카운터
            if (!warmed_up) begin
                if (warmup_cnt == 4'd7) warmed_up <= 1'b1;
                else warmup_cnt <= warmup_cnt + 4'd1;
            end

            if (fired) begin
                // 현재 theta 슬롯 → actual_phase로 수렴
                if (err_ab > 8'd2) begin
                    if (dn_dir) begin
                        slot[theta_now] <= (slot[theta_now] >= step) ?
                                           slot[theta_now] - step : 8'd0;
                    end else if (up_dir) begin
                        slot_up = {1'b0, slot[theta_now]} + {1'b0, step};
                        slot[theta_now] <= (slot_up > 9'd255) ? 8'd255 : slot_up[7:0];
                    end
                end

                error_out   <= err_ab;
                error_valid <= (err_ab > 8'd2) && warmed_up;
            end else begin
                error_valid <= 1'b0;
            end

            // 다음 theta 슬롯 값을 top-down 예측으로 출력
            pred_next <= slot[theta_next];
        end
    end

endmodule
