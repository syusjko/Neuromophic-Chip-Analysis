// =============================================================================
// Module  : wta_inhibition (v2 - 엄격한 승자 독식)
// Project : HNSN
//
// [v2 변경]
//   동점 처리: 이전엔 모두 통과 → 이제 이전 승자 유지 (히스테리시스)
//   → 패턴 전환 시 노이즈 방지
//
//   [그룹 정의]
//   Group A: N0(bit0), N1(bit1)
//   Group B: N2(bit2), N3(bit3)
//
//   [동작]
//   Group A 발화 수 > Group B → A만 통과
//   Group B 발화 수 > Group A → B만 통과
//   동점 → 이전 승자 그룹 유지 (히스테리시스)
//   둘 다 0 → 공백 출력
// =============================================================================

module wta_inhibition (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [3:0] spike_in,
    output reg  [3:0] spike_out
);

    reg last_winner;  // 0=GroupA, 1=GroupB

    wire [1:0] cnt_a = {1'b0, spike_in[0]} + {1'b0, spike_in[1]};
    wire [1:0] cnt_b = {1'b0, spike_in[2]} + {1'b0, spike_in[3]};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_winner <= 1'b0;
            spike_out   <= 4'b0000;
        end
        else begin
            if (cnt_a > cnt_b) begin
                last_winner <= 1'b0;
                spike_out   <= {2'b00, spike_in[1:0]};  // A만 통과
            end
            else if (cnt_b > cnt_a) begin
                last_winner <= 1'b1;
                spike_out   <= {spike_in[3:2], 2'b00};  // B만 통과
            end
            else begin
                // 동점: 이전 승자 유지
                if (last_winner == 1'b0)
                    spike_out <= {2'b00, spike_in[1:0]};
                else
                    spike_out <= {spike_in[3:2], 2'b00};
            end
        end
    end

endmodule
// =============================================================================
// End of wta_inhibition.v (v2)
// =============================================================================
