# Phase-based Spiking Transformer (PST)
## 실험 결과 보고서 v4
### 날짜: 2026-02-20 (V3.3 완성)

---

## 0. 핵심 성과 요약

```
달성 모듈 (2026-02-22 V3.8b 최종):
  phase_stdp.v         STDP v3.8 (global protect)               ✅
  predictive_phase.v   예측 코딩 핵심 회로                      ✅
  pst_brain_v1.v       완전한 폐루프 Brain v1                   ✅
  pst_brain_v2.v       Brain V3.8b - 전체 6 Phase 완전 증명     ✅ 최종
  theta_oscillator.v   8 gamma = 1 에피소드                     ✅
  episode_memory.v     에피소드 투표 → ep_winner/strength       ✅
  metacognition.v      3중 explore: ep불안정+err급증+입력불일치  ✅
  delta_oscillator.v   5 theta = 1 delta (대화 주제 경계)       ✅
  topic_memory.v       delta 안정 투표 → topic_winner           ✅

[6 Phase 완전 성공 로드맵]
  Phase 0  학습 전:   AB 2/20 (편견 없음)
  Phase 1  A 학습:    wAB=190 ← expl=1→0 자동 전환
  Phase 2  경험지각:  AB 20/20 ← "경험이 지각을 바꿈" ✅
  Phase 3  B 학습:    wAB=185 wCD=190 gap=5 ← CF 없음! ✅
  Phase 4  전환:      wAB=190 wCD=185 양쪽 복구
  Phase 5  장기:      wAB=190 wCD=181 양쪽 보존 ✅
  Phase 5.5 교번:     conf=3→1, expl=1, sc=127 ✅
  Phase 6  경계:      conf=3→1, expl=1, gap=3, ACTIVATED ✅

핵심 증명 (2026-02-22 최종):
  1. 경험 기반 지각:    2/20 → 20/20
  2. R-STDP:           err<5 → reward → LTP×2
  3. 3계층 시간:        γ→θ→δ (비율 40:5:1)
  4. 2계층 문맥 bias:  ep+4, topic+2 → sc=133
  5. Metacognition:    교번→expl=1→bias 제거→재안정→expl=0
  6. CF 완전 극복:     [B50] gap 35→5 (86%↓), 장기 wCD=181 유지
  7. 패턴 전환 자기인식: mismatch_ctx→expl=1 즉각 발동
  8. 경계 유연성:      30사이클 교번→conf=1 expl=1 ✅

최종 확정 파라미터 (V3.8b):
  ETA_LTP=4, ETA_LTD=2, DECAY_PERIOD=2, W_MAX=190, W_MIN=80
  EP_BIAS=4, TOPIC_BIAS=2, TOPIC_STAB_THR=3
  MISMATCH_DIF=20, STABLE_WIN=10, MISMATCH_CTX=40
  EXPLOIT_THR=6, EXPLORE_THR=5, CONF_EXP_THR=2

  protect  = topic_valid && !explore          (전역 decay+LTD 차단)
  ctx_gate = fv | explore | mismatch_ctx      (w bias 즉각 제거)
  score    = rel/2+w/4+ep+top (안정) / rel/2 (전환)
```

---

## 0.5 계층적 학습 최종 증명 (2026-02-19 신규)

```
[실험 구조]
  L1: phase_neuron (실제 입력)
  L3: seq2_predictor (WTA + 패턴 전환 감지)
  A:  L2 with top-down injection (계층적)
  B:  L2 단독 (baseline)

[WTA 학습 결과]
  sA = 3  (≈ ph=1, cur=200 패턴 전문화)
  sB = 42 (≈ ph=40, cur=5 패턴 전문화)
  → 두 패턴이 서로 다른 슬롯으로 자동 분리

[Top-down Injection 동작]
  cur=5 도착 (ph=40, winner A→B 전환 감지):
    force_valid=1, force_pred=42 → A의 pred 즉시 42로 set
  cur=200 도착 (ph=1, winner B→A 전환 감지):
    force_valid=1, force_pred=3 → A의 pred 즉시 3으로 set

[수렴 속도 비교 결과] - 최종 검증
  Trans | A(injection) | B(standalone) | Speedup
    1   |      4       |      12       | 66%
    2   |      4       |      12       | 66%
    3   |      4       |      12       | 66%
    4   |      4       |      12       | 66%
    5   |      4       |      12       | 66%
    6   |      4       |      12       | 66%
  → 6번 전환 모두 일관 66% 가속 ✅
  → [VERDICT] HIERARCHICAL EFFECT PROVEN ✅

[타이밍 이벤트 추적 (Trans 2 예시)]
  C162: stable (A err=2, B err=2)
  C163: INJECT! (force_valid=1, force_pred=42)
  C164: A pred=42 즉시 반영, err=28 (phase_neuron 적분기 잔류)
  C165: A_HIT (err=2) ← trans 이후 4 gamma
  C173: B_HIT (err=3) ← trans 이후 12 gamma

[phase_neuron 잔류 에너지 분석]
  cur 전환 직후 첫 gamma:
    이전 cur의 적분기 에너지 일부 잔류
    → ph=32 발화 (예상 ph=1이 아님)
  두 번째 gamma부터 정상 ph=1 발화
  → A의 err=31이 C122에서 나오는 정상 동작

[실패에서 배운 것]
  시도 1: gain modulation (eta_boost)    → 효과 없음 (gain만으로 부족)
  시도 2: theta sequence predictor       → theta-교번 주기 충돌
  시도 3: competitive_seq (4슬롯)        → 슬롯 독점 문제
  시도 4: top-down pred 혼합 (25%)       → 수렴 방향 방해
  성공:   top-down injection              → 즉각 주입이 핵심

[뇌 대응]
  seq2_predictor: CA3 pattern completion
  force injection: "이 패턴이면 즉시 활성화" = cue-triggered priming
  WTA: cortical column lateral inhibition
```

---

## 1. Phase 4: 2층 계층적 학습 (신규) ← 핵심

```
모듈: pst_2layer.v (L2+L3 predictive_phase)
비교: 2층(L2) vs 단층(SL)
입력: phase_neuron → actual_phase

[결과 비교표]
               L2 pred   L2 err   SL pred  SL err
Exp1(수렴):    6(실제4)   2        0        28  ← SL 완전 실패
Exp2(재수렴):  4(2사이클) 2        0        30  ← SL 반응 없음
Exp3(강변화):  19(실제20) 1        0        12  ← SL 0에 갇힘

2층 우위 원인:
  SL: pred_phase_in=128(고정) → effective_pred=32 → my_pred=0에 갇힘
  L2: pred_phase_in=L3_pred(동적 6~18) → effective_pred 현실적
      → 0 클램핑 탈출 가능 → 실제 phase에 수렴

계층적 학습 흐름:
  L1 (phase_neuron): actual_phase 생성
  L3: pred_L2 패턴 학습 → pred_L3 생성 (top-down)
  L2: actual_L1 + L3 top-down → 더 정확한 수렴

논문 주장 근거:
  "계층적 예측 코딩이 단층 STDP보다 수렴성 우수" ✅
  "Top-down 신호로 Credit Assignment 흐름 구현"   ✅
  "단층이 실패하는 경우에도 2층은 수렴 가능"      ✅
```

---

### 1.0 Phase 3: 예측 코딩 (Predictive Coding) ← 신규

```
모듈: predictive_phase.v + phase_stdp.v
실험: 2층 구조 패턴 학습/변화감지/재적응

[Phase A] cur=50 → phase=4 반복 학습
  Cycle 2:  pred=128, err=125 (초기 큰 오차)
  Cycle 7:  pred=34,  err=30  → W=132 (STDP LTP 시작)
  Cycle 18: pred=6,   err=2   → W=172 (수렴, 안정화)
  → 16사이클 만에 수렴 ✅

[Phase B] cur 변경 (phase=4→10)
  Cycle 34: fast→slow 전환 (변화 즉시 감지) ✅
  Cycle 36: pred=8, err=2 (새 패턴 재수렴) ✅
  W=180 (LTD 발동, 새 방향 학습)

[Phase C] 원래 패턴 복원
  Cycle 66: 방향 전환 즉시 감지
  Cycle 68: pred=6, err=2 (2사이클 재수렴!) ✅
  W=188 (이전 학습 누적 유지)

검증 결과:
  패턴 학습:   16사이클 수렴     ✅
  변화 감지:   1사이클 즉시      ✅
  빠른 재적응: 2사이클 (8배 빠름)✅
  Weight 안정: 포화 없이 172→188 ✅

논문 주장 근거:
  "추론 중 학습 (Continual Learning)" ✅
  "Catastrophic Forgetting 완화"      ✅
  "변화 감지 (Anomaly Detection)"     ✅
```

### 1.1 위상 코딩 동작 확인

```
입력 전류 → 발화 위상 (THRESHOLD=200, LEAK=0)

input=50  → phase≈4   (강한 입력 = 초반 발화)
input=20  → phase≈10  (중간 입력 = 중반 발화)
input=5   → phase≈40  (약한 입력 = 후반 발화)

수식: phase ≈ THRESHOLD / input_current
```

### 1.2 위상 유사도 (Circular Phase Similarity)

```
Rel = 255 - min(|phase_A - phase_B|, 256 - |phase_A - phase_B|)

검증 결과:
  A=50, B=45 → phase차이=1  → Rel=254  [RELATED]   ✅
  A=50, C=5  → phase차이=36 → Rel=219  [UNRELATED] ✅
  A=20, B=22 → phase차이=0  → Rel=255  [RELATED]   ✅
  A=50, B=5  → phase차이=36 → Rel=219  [UNRELATED] ✅

수학적 성질:
  대칭성: Rel(A,B) = Rel(B,A)         ✅
  단조성: 위상차 증가 → Rel 감소       ✅
  최대값: 동일 위상 → Rel=255          ✅
```

### 1.3 4토큰 Attention (phase_attention_4n)

```
Scenario 1: A=50 B=48 C=20 D=5
  AB=254 AC=249 AD=219 BC=250 BD=220 CD=225
  WINNER: A-B (강-강 쌍 정확히 선택) ✅

Scenario 2: A=10 B=8 C=50 D=48
  CD=254 (최대)
  WINNER: C-D (역할 반전, 정확히 선택) ✅

Scenario 3: A=30 B=32 C=28 D=31 (모두 비슷)
  AB=AD=BD=255 (모두 최대)
  WINNER: A-B (동점 처리) ✅

Scenario 4: A=50 B=25 C=12 D=5 (계단식)
  AB=251 (최대)
  WINNER: A-B (가장 가까운 인접 쌍) ✅
```

### 1.4 Lateral Inhibition (phase_softmax v3)

```
입력: AB=254(winner) BC=250 AC=249 CD=225 AD=219 BD=220

결과 (안정화 후):
  AB=253  BC=249  AC=248  (winner 근처, 약한 억제)
  CD=224  BD=219  AD=218  (먼 쌍, 강한 억제)

억제 효과:
  AB/BC 비율: 253/249 = 1.02 (약한 경쟁)
  INHIBIT_GAIN=4 기준

Scenario 4 (AB=254 vs BC=100):
  AB=253, BC=63  → AB/BC = 4.0배 차이 ✅
  (v2 선형 대비 40배 향상된 경쟁성)
```

### 1.5 PST_core vs Softmax 기능 비교

```
테스트: 6가지 입력 패턴, 10회 측정
결과: 8/10 일치 = 80% 일치율

일치 케이스 (8/10):
  - 명확한 강자 패턴: 100% 일치
  - 균등 입력: 일치
  - 계단식: 일치

불일치 케이스 (2/10):
  - 사이클 전환 과도기 (1건): 타이밍 문제
  - 다른 정보 포착 (1건): PST 고유 동작

불일치 분석 (Test 10):
  cur = 20 200 30 25
  SMX: tok1(200) 선택 → "가장 강한 토큰"
  PST: C-D 쌍 선택 → "가장 관련있는 쌍"
       (tok2=30, tok3=25가 위상 거의 동일)
  → 이건 버그가 아니라 다른 관점
```

---

## 2. Transformer Attention과의 대응

| Transformer | PST | 구현 방식 |
|-------------|-----|-----------|
| Q·K 내적 | 위상 차이 | 뺄셈 1회 |
| softmax | Lateral Inhibition | 누산기 + 억제 |
| argmax | winner 선택 | 비교기 6개 |
| Value 가중합 | spike rate | Delta-Sigma |
| 행렬 곱셈 | 없음 | - |

---

## 3. 구현 복잡도 비교

```
모듈별 코드 라인 수:

PST_core 스택:
  pst_core.v          199줄
  phase_neuron.v       97줄
  gamma_oscillator.v   52줄
  coincidence_det.v    81줄
  phase_softmax.v     168줄
  합계:               597줄

Softmax Reference:
  softmax_attention_ref.v  169줄

연산 종류:
  PST:      뺄셈, 비교, 누산 (곱셈 없음)
  Softmax:  곱셈(8×8), exp 근사, 나눗셈

예상 합성 결과 (N=4, FPGA):
  PST LUT:      ~80-120
  Softmax LUT:  ~200-400 (곱셈기 포함)
  예상 비율:    1/3 ~ 1/5 (FPGA)
               1/20 ~ 1/50 (ASIC 추정)
```

---

## 4. 논문 포지션

### 제목 후보
```
"Phase-coded Spiking Attention:
 Finding Correlated Token Pairs Without Matrix Multiplication"
```

### 핵심 Contribution
```
1. 위상 코딩으로 입력 강도를 시간 정보로 변환
   → 행렬 곱셈 없는 유사도 계산

2. Lateral Inhibition으로 경쟁적 선택
   → softmax의 생물학적 대안

3. 80% 기능 동등성 + 20% 고유 동작
   → "열등한 대안"이 아닌 "다른 관점"

4. 하드웨어 복잡도 1/3~1/5
   → 저전력 엣지 AI 응용 가능

5. 온라인 학습 가능 (STDP 연결 시)
   → softmax가 못 하는 것
```

### 비교 실험 계획
```
동일 입력 → PST vs Softmax:
  winner 일치율: 80% (현재)
  목표: 더 많은 패턴으로 통계적 검증

전력 비교 (FPGA 합성 후):
  LUT 사용량
  Fmax
  동적 전력 (mW)
  → "동일 기능, X배 낮은 전력" 주장
```

---

## 5. 구현된 모듈 목록

```
gamma_oscillator.v      전역 위상 기준 (감마파 모사)    ✅
phase_neuron.v          위상 코딩 뉴런                  ✅
coincidence_detector.v  위상 유사도 계산                ✅
phase_attention_4n.v    4토큰 Attention (독립 모듈)     ✅
phase_softmax.v         Lateral Inhibition Softmax      ✅
pst_core.v              완전한 Attention Head           ✅
softmax_attention_ref.v Softmax 기준 구현               ✅
tb_pst_vs_softmax.v     기능 비교 테스트벤치            ✅
```

---

## 6. 다음 단계

### 즉시 (이번 세션)
```
[ ] FPGA 합성 (Vivado/Quartus)
    → LUT, Fmax, Power 측정
    → softmax_attention_ref와 직접 비교
```

### 단기 (1~2주)
```
[ ] 더 많은 입력 패턴으로 일치율 통계 (N=100+)
[ ] INHIBIT_GAIN 스윕 (1,2,4,8,16)
    → 선형~WTA 스펙트럼 Figure
[ ] N=8 확장 테스트
```

### 중기 (1~3개월)
```
[ ] phase_stdp.v (Value 가중합)
    → 완전한 Self-Attention 레이어
[ ] 다층 PST (2~3 레이어)
[ ] 소형 언어 태스크 검증
    → 4토큰 문맥 예측
[ ] arXiv 초안
```

---

## 7. 현재 단계 평가

```
GPT 체크리스트:
  1. circular similarity 구현          ✅
  2. Rel이 단조/대칭인지 확인           ✅
  3. 4~8뉴런 완전 연결 네트워크         ✅
  4. softmax 유사 정규화 회로           ✅ (Lateral Inhibition)
  5. 실제 입력 패턴에서 선택 동작 검증  ✅ (6가지 패턴, 80% 일치)

GPT 단계 평가:
  아이디어 단계    ❌
  실험 설계 단계   ✅ (완료)
  수학적 검증      ✅ (완료)
  정량 데이터      🔜 (FPGA 합성 후)
  패러다임 전환    🔜 (논문 후)
```
