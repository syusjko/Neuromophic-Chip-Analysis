// =============================================================================
// Module  : tb_reward
// Description : 도파민 보상 회로 + DA-STDP 시냅스 통합 검증
//
// [검증 시나리오]
//
// [Phase A] 보상 없이 학습 → weight 느리게 증가
// [Phase B] 보상 신호 추가 → dopamine=11 → weight 빠르게 증가
// [Phase C] 보상 반복 → predict_state=1 → dopamine=01 (기본으로 복귀)
// [Phase D] 보상 중단 (예측 배반) → dopamine=00 → weight 감소
//
// [관전 포인트]
//   Phase A vs Phase B: weight 증가 속도 차이
//   Phase D: 예상 보상이 안 오면 weight가 줄어드는 것 (실망 반응)
// =============================================================================
`timescale 1ns / 1ps

module tb_reward;

    reg clk, rst_n;
    reg pre_spike, post_spike;
    reg reward_in;

    wire [1:0] dopamine;
    wire       prediction;
    wire [7:0] w_current, w_val;

    // 도파민 회로
    reward_circuit #(.PREDICT_THRESH(4'd4)) rc (
        .clk          (clk),
        .rst_n        (rst_n),
        .reward       (reward_in),
        .dopamine_level(dopamine),
        .prediction   (prediction)
    );

    // DA-STDP 시냅스
    synapse_da #(
        .INIT_WEIGHT (8'd10),
        .LTP_STEP    (8'd3),
        .LTD_STEP    (8'd1),
        .TRACE_DECAY (4'd8)
    ) syn (
        .clk             (clk),
        .rst_n           (rst_n),
        .pre_spike       (pre_spike),
        .post_spike      (post_spike),
        .dopamine_level  (dopamine),
        .weighted_current(w_current),
        .weight          (w_val)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    // pre→post 순서로 스파이크 발생 (LTP 조건)
    task fire_ltp;
        begin
            @(posedge clk); #1; pre_spike = 1; post_spike = 0;
            @(posedge clk); #1; pre_spike = 0; post_spike = 0;
            @(posedge clk); #1; pre_spike = 0; post_spike = 1;
            @(posedge clk); #1; pre_spike = 0; post_spike = 0;
        end
    endtask

    integer i;
    initial begin
        $dumpfile("reward_dump.vcd");
        $dumpvars(0, tb_reward);

        rst_n = 0; pre_spike = 0; post_spike = 0; reward_in = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst_n = 1;

        // =====================================================================
        // [Phase A] 보상 없이 LTP 10회
        //   dopamine=01(기본) → LTP_STEP=3 적용
        // =====================================================================
        $display("\n=== [Phase A] 보상 없이 학습 (dopamine=기본) ===");
        reward_in = 0;
        for (i = 0; i < 10; i = i + 1)
            fire_ltp();

        // =====================================================================
        // [Phase B] 보상 신호 ON + LTP 10회
        //   처음엔 예측 없음 → dopamine=11(최대) → LTP_STEP×3 적용
        //   weight가 Phase A보다 훨씬 빠르게 증가해야 함
        // =====================================================================
        $display("\n=== [Phase B] 보상 신호 ON (dopamine=최대) ===");
        reward_in = 1;
        for (i = 0; i < 10; i = i + 1)
            fire_ltp();

        // =====================================================================
        // [Phase C] 보상 반복 → predict_state 전환
        //   4회 이상 연속 보상 → predict_state=1
        //   → 이제 보상이 와도 dopamine=01(기본)으로 복귀
        //   "익숙해지면 흥분이 줄어드는" 습관화(Habituation)
        // =====================================================================
        $display("\n=== [Phase C] 보상 반복 → 예측 상태 전환 (습관화) ===");
        reward_in = 1;
        for (i = 0; i < 15; i = i + 1)
            fire_ltp();

        // =====================================================================
        // [Phase D] 보상 중단 (예측 배반)
        //   predict_state=1인데 reward=0 → dopamine=00(억제)
        //   → LTP 절반, LTD 유지 → weight 감소
        //   "기대했는데 안 오면 실망" = 소거(Extinction)
        // =====================================================================
        $display("\n=== [Phase D] 보상 중단 (실망 반응 - dopamine=억제) ===");
        reward_in = 0;
        for (i = 0; i < 10; i = i + 1)
            fire_ltp();

        $display("\n=== [시뮬레이션 완료] ===");
        $finish;
    end

    initial begin
        $monitor("T=%t | Pre=%b Post=%b | Reward=%b Predict=%b | DA=%b | Weight=%3d",
                 $time, pre_spike, post_spike,
                 reward_in, prediction, dopamine, w_val);
    end

endmodule
// =============================================================================
// End of tb_reward.v
// =============================================================================
