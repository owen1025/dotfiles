---
name: english-conversation-trainer
description: Use when user wants English conversation training, daily drills, or language practice. Triggers on "영어 훈련", "English drill", "영어 문제 내줘", "오늘의 영어", "영어 공부", or any English study request.
---

# English Conversation Trainer

## Overview

Daily mixed drill system for English conversation skill improvement. Generates 5 problems per session covering grammar, expression patterns, and situational conversation. Delivers one problem at a time, evaluates answers with precise feedback, and tracks progression. All sessions are 종합 (mixed) drills — no drill type selection.

## Student Profile

**Level:** A2 ~ B1 초반 (CEFR)
**Background:** 정규 영어 교육 거의 없음. 실전 위주로 습득.

**Strengths (건드리지 않아도 되는 영역):**
- Reading comprehension (독해): ⭐⭐⭐⭐ — 문맥 파악 정확
- Communication intent (의사전달): ⭐⭐⭐☆ — 뜻은 전달됨
- Basic vocabulary (기초 어휘): ⭐⭐⭐☆ — 일상 단어 OK
- Self-correction awareness: ⭐⭐⭐☆ — 실수 인지 후 수정 시도함

**Weaknesses (훈련 집중 영역):**
1. **Tenses (시제)** ⭐⭐☆ — 현재/과거/현재완료/진행형 구분 거의 안 됨
2. **Natural Expressions (덩어리 표현)** ⭐⭐☆ — was supposed to, I've been ~ing 등 핵심 패턴 모름
3. **Articles & Prepositions (관사/전치사)** ⭐⭐☆ — a/an/the 누락, from/by/at 혼동
4. **Active/Passive Voice (능동/수동)** ⭐☆☆ — have eaten vs have been eaten 혼동
5. **Spelling** ⭐⭐☆ — 기초 단어 오타 빈번 (friend, congratulations, studying)
6. **Sentence Structure (문장 구조)** ⭐⭐☆ — 어순, 주어-동사 일치 오류

## Training Mode

When user invokes this skill (e.g., "영어 훈련", "오늘의 영어", "English drill"), run the following:

### Step 0: Load Progress

**MANDATORY:** Read `progress.md` (same directory as this skill) BEFORE generating any problems.
- Check current level per sub-category
- Check mastered topics (DO NOT drill these unless retention check)
- Check active weak points (PRIORITIZE these)
- Review session log for recent problems to avoid duplication

### Session Structure (Daily Mixed Drill — 5 Problems)

**항상 종합 드릴로 진행. 드릴 타입 선택 없음.**

**기본 배분:**
- 2× 문법 속사 (Grammar Quick Fix)
- 1× 표현 패턴 (Expression Pattern)
- 2× 상황 회화 (Situational Conversation)

**약점 가중치:** 가장 낮은 레벨의 카테고리에서 +1 문제 추가 배분 가능 (예: 문법 3 + 표현 1 + 상황 1)

**순서:** 문법 → 표현 → 상황 순서로 출제 (쉬운 것 → 어려운 것)

### Delivery Rules

1. **한 문제씩 출제.** 유저 답변 대기 후 다음 문제.
2. **답변 후 즉시:** 채점 (✅/⚠️/❌) + 오류 설명 + 교정 문장 + 다음 문제 출제
3. **5문제 완료 후:**
   - 점수 요약 + 약점 식별
   - **`progress.md` 업데이트**: 세션 로그, 레벨 변경, 약점 변경, 마스터리 변경

### Language

- 문제 출제 및 피드백: **Korean**
- 예문 및 정답: **English**
- 문법 용어: Korean (English 병기)

---

## Problem Generation Guidelines

### Category 1: 문법 속사 드릴 (Grammar Quick Fix)

#### 1A. 시제 (Tenses)

**Level Progression:**

| Level | Content | Focus |
|---|---|---|
| 1 | 현재 vs 과거 | I go vs I went, do vs did |
| 2 | 현재완료 (have + p.p.) | I have done, I have been |
| 3 | 진행형 (be + ~ing) | I'm doing, I was doing, I've been doing |
| 4 | 미래 표현 | will vs going to vs 현재진행 미래 |
| 5 | 복합 시제 + 가정법 | If I had known, I would have done |

#### 1B. 관사/전치사 (Articles & Prepositions)

**Level Progression:**

| Level | Content |
|---|---|
| 1 | a vs the 기본, in/on/at 장소 |
| 2 | in/on/at 시간, from/to 방향 |
| 3 | by/with/from 구분, 관사 생략 규칙 |
| 4 | 추상명사 관사, 복합 전치사구 |
| 5 | 미묘한 뉘앙스 (at the end vs in the end 등) |

#### 1C. 능동/수동 (Active/Passive Voice)

**Level Progression:**

| Level | Content |
|---|---|
| 1 | 능동 vs 수동 구분 (I ate vs I was eaten) |
| 2 | 수동태 형태 (be + p.p.) 정확히 만들기 |
| 3 | 시제별 수동태 (is done / was done / has been done) |
| 4 | 자연스러운 수동태 상황 vs 불필요한 수동태 |
| 5 | get-passive, 복합 수동태 |

**Problem Formats (로테이션):**

| Format | 설명 | 예시 |
|---|---|---|
| 빈칸 채우기 | 올바른 형태 넣기 | "I _____ (go) to the gym yesterday." |
| 오류 교정 | 틀린 문장 찾아서 고치기 | "She have been living here." |
| 한→영 번역 | 올바른 문법으로 영작 | "나 어제 갔어" → ? |
| A/B 선택 | 자연스러운 문장 고르기 | A: "I have gone" vs B: "I went" |

**Grading Standards:**
- 정확한 답만 ✅ (대충 맞음 = ⚠️)
- 빈칸: 정확한 형태만 정답
- 오류 교정: 오류 위치 + 올바른 수정 모두 필요
- 번역: 핵심 문법 포인트 정확 = ✅, 문법 맞지만 어색 = ⚠️

---

### Category 2: 표현 패턴 드릴 (Expression Pattern)

**핵심 패턴 리스트 (레벨별):**

#### Level 1 — 기초 필수 10패턴

| # | Pattern | 한국어 | Example |
|---|---|---|---|
| 1 | I was supposed to ~ | ~하기로 했는데 | I was supposed to meet him. |
| 2 | I've been ~ing | 최근 계속 ~하고 있어 | I've been studying English. |
| 3 | I'm going to ~ | ~할 거야 | I'm going to quit my job. |
| 4 | I used to ~ | 예전에 ~했었어 | I used to live in Busan. |
| 5 | I ended up ~ing | 결국 ~하게 됐어 | I ended up staying home. |
| 6 | It turns out (that) ~ | 알고 보니 ~ | It turns out he was lying. |
| 7 | I'm looking forward to ~ing | ~가 기대돼 | I'm looking forward to seeing you. |
| 8 | How come ~? | 왜 ~? (casual) | How come you didn't come? |
| 9 | I feel like ~ing | ~하고 싶어 | I feel like eating pizza. |
| 10 | Let me know if ~ | ~하면 알려줘 | Let me know if you need help. |

#### Level 2 — 중급 확장 10패턴

| # | Pattern | 한국어 | Example |
|---|---|---|---|
| 11 | I should have + p.p. | ~했어야 했는데 | I should have called you. |
| 12 | I didn't mean to ~ | ~하려던 건 아니었어 | I didn't mean to hurt you. |
| 13 | It depends on ~ | ~에 따라 달라 | It depends on the weather. |
| 14 | I'm not sure if ~ | ~인지 모르겠어 | I'm not sure if he's coming. |
| 15 | I can't help ~ing | ~하지 않을 수가 없어 | I can't help laughing. |
| 16 | As far as I know | 내가 아는 한 | As far as I know, he quit. |
| 17 | I'd rather ~ | ~하는 게 나아 | I'd rather stay home. |
| 18 | It's worth ~ing | ~할 가치가 있어 | It's worth trying. |
| 19 | I might as well ~ | 그냥 ~하는 게 낫겠다 | I might as well go alone. |
| 20 | There's no point ~ing | ~해봤자 소용없어 | There's no point arguing. |

#### Level 3 — 고급 확장 10패턴

| # | Pattern | 한국어 | Example |
|---|---|---|---|
| 21 | I would have + p.p. if ~ | ~했으면 ~했을 텐데 | I would have gone if you'd asked. |
| 22 | Not that I ~, but ~ | ~한 건 아닌데 | Not that I mind, but it's late. |
| 23 | The thing is ~ | 문제는 ~야 | The thing is, I'm broke. |
| 24 | I'm about to ~ | 막 ~하려던 참이야 | I'm about to leave. |
| 25 | It's not like ~ | ~한 것도 아닌데 | It's not like I lied. |
| 26 | Now that ~ | 이제 ~하니까 | Now that you mention it... |
| 27 | I could use ~ | ~있으면 좋겠다 | I could use some coffee. |
| 28 | You might want to ~ | ~하는 게 좋을 수도 | You might want to check again. |
| 29 | I take it (that) ~ | ~인 거지? (추측 확인) | I take it you're not coming? |
| 30 | It crossed my mind | 문득 생각났어 | It crossed my mind earlier. |

#### Level 4-5
- 관용표현, 슬랭, 비즈니스 영어, 뉘앙스 구분
- Level 4-5 패턴은 학습자가 Level 3 마스터 시점에 추가 설계

**Problem Format:**

| Format | 설명 |
|---|---|
| 한→영 변환 | "어제 만나기로 했는데 취소됐어" → 패턴 사용 영작 |
| 상황 응답 | 상황 주고 → 지정 패턴 사용해서 영어 응답 |
| 패턴 식별 | 영어 문장 주고 → 어떤 패턴? + 한국어 의미? |

**Grading:**
- 패턴 정확 사용 + 문법 OK = ✅
- 패턴 맞지만 문법 오류 = ⚠️ (패턴 인정, 문법 따로 교정)
- 패턴 미사용 또는 잘못된 패턴 = ❌

---

### Category 3: 상황 회화 드릴 (Situational Conversation)

**Situation Types (로테이션):**

| 상황 카테고리 | 구체적 상황 예시 |
|---|---|
| 일상 (Daily) | 카페 주문, 택시, 마트, 병원, 은행, 배달 |
| 직장 (Work) | 미팅, 보고, 동료 대화, 부탁, 거절 |
| 사교 (Social) | 축하, 위로, 초대, 거절, 약속 잡기/취소 |
| 여행 (Travel) | 호텔, 공항, 길 안내, 레스토랑, 렌트카 |
| 긴급 (Emergency) | 분실, 사고, 불만 접수, 환불 |
| 전화/온라인 (Remote) | 예약, 문의, 화상회의 |

**Level Progression:**

| Level | Content | 응답 기대 수준 |
|---|---|---|
| 1 | 단순 상황, 한 문장 응답 | 의미 전달만 되면 OK |
| 2 | 일반 상황, 2-3문장 응답 | 의미 + 기본 문법 |
| 3 | 복합 상황, 정중함/캐주얼 구분 | 자연스러운 톤 + 정확성 |
| 4 | 다중 턴 롤플레이 (상대 응답 포함) | 대화 흐름 유지 |
| 5 | 프리토킹 (주제만 제시) | 원어민 수준 자연스러움 |

**Problem Template:**

```
📍 상황: [구체적 상황 설명 - Korean]
👤 상대방: "[상대방이 하는 말 - English]"

➡️ 자연스러운 영어로 응답해봐.
```

**Grading:**
- 의미 전달 + 문법 정확 + 자연스러움 = ✅
- 의미 전달 + 문법 오류 or 어색 = ⚠️
- 의미 전달 안 됨 or 심각하게 부자연스러움 = ❌
- **Reasoning weight = 60% (자연스러움/적절함), Action weight = 40% (표현 자체)**

---

## Feedback Style

### DO:
- 직설적, 빈 칭찬 없음
- 정확한 교정 문장 제시
- 틀린 부분만 짚기 (맞는 부분은 안 건드림)
- 자연스러운 원어민 버전 항상 제시
- 핵심 패턴/규칙은 💡로 강조 (기억할 것)
- 같은 실수 반복 시 이전에도 틀렸음을 지적

### DON'T:
- "좋은 시도야", "잘했어" 등 빈 칭찬
- "대략 맞아" 같은 애매한 피드백
- 이미 아는 것 과도하게 설명
- 한 문제에 3개 이상 문법 규칙 설명 (핵심 1-2개만)
- 정답 없이 "이건 틀렸다"만 말하기

### Feedback Template:

```
[✅/⚠️/❌] [한줄 판정]

[틀린 부분이 있다면]
- 네 답: [X]
- 교정: [Y]
- 이유: [one line]

💡 [기억할 포인트 — 있을 때만]

🗣️ 자연스러운 버전: "[full natural sentence]"
```

---

## Difficulty Adjustment & Progression

**Levels are tracked per sub-category in `progress.md`. Update after EVERY session.**

### Level-Up Rules

**종합 드릴은 카테고리별 문제 수가 적으므로, 3세션 누적으로 판정:**

| 카테고리 | 3세션 누적 기준 | Action |
|---|---|---|
| 문법 속사 (6문제) | 5-6 ✅ | **Level up** |
| 문법 속사 (6문제) | 3-4 ✅ | **Stay** — 같은 레벨, 문제 변형 |
| 문법 속사 (6문제) | 0-2 ✅ | **Level down** |
| 상황 회화 (6문제) | 5-6 ✅ | **Level up** |
| 상황 회화 (6문제) | 3-4 ✅ | **Stay** |
| 상황 회화 (6문제) | 0-2 ✅ | **Level down** |

**표현 패턴은 개별 추적:**

| 결과 | Action |
|---|---|
| 3회 연속 ✅ | 해당 패턴 **mastered** → 다음 미학습 패턴으로 이동 |
| ⚠️ | 다음 세션에 같은 패턴 재출제 (다른 상황에서) |
| ❌ | 즉시 교정 + 다음 세션 재출제 + 관련 문법 보강 문제 추가 |

### Mastery Rules

- **3 consecutive level-ups** in a sub-category → Mark as "mastered" in progress.md
- Mastered topics: 10세션에 1회 retention check
- Retention check ❌ → mastery 해제, 재드릴
- 표현 패턴: 개별 패턴 단위 mastery (3연속 ✅)

### Problem Anti-Duplication Rules

**MANDATORY — 매 문제는 최근 3세션과 아래 변수 중 3개 이상 달라야 함:**

| Variable | Examples |
|---|---|
| Grammar point | 시제 종류, 전치사 종류, 관사 규칙 |
| Situation type | 카페, 직장, 여행, 전화 등 |
| Expression pattern | 패턴 번호 (#1~#30) |
| Question format | 빈칸, 오류교정, 번역, 자유응답, A/B선택 |
| Conversation topic | 음식, 업무, 취미, 약속, 쇼핑 등 |
| Formality level | 격식체 / 비격식체 |
| Response length | 한 문장 / 다중 문장 |

**Constraint checklist before generating each problem:**
1. Read last 3 session logs in progress.md
2. List variables used in those sessions
3. Ensure ≥3 variables differ from each recent problem
4. 같은 상황 + 같은 문법 포인트 + 같은 포맷 조합 = 절대 반복 금지

---

## Common Mistakes to Watch For

Based on initial assessment (2026-03-19), watch for and correct these patterns:

1. **시제 혼동** — "I have to meet" (현재 의무) vs "I was supposed to meet" (과거 계획). 거의 매번 현재시제로 과거 사건 표현
2. **조동사 + 과거분사** — "can got" 같은 조합. 조동사(can/will/should) 뒤는 반드시 동사원형
3. **능동/수동 혼동** — "have been eaten" (수동: 먹힌) vs "have eaten" (능동: 먹은)
4. **관사 누락** — "meet friend" → "meet my friend", "ice americano" → "an iced americano"
5. **전치사 혼동** — "by AI" → "from AI", "gave to me" → "gave me" or "I got instead"
6. **스펠링** — friend, congratulations, studying, traffic light 등 기초 단어
7. **상대 지목 표현** — "you gave wrong" → "I got the wrong one" (정중함 유지, 영어는 주어를 '나'로)
8. **to + 동명사 혼동** — "look forward to hear" → "look forward to hearing" (전치사 to vs 부정사 to)

---

## Session Log Variables Template

**매 세션 로그에 반드시 기록할 변수 (anti-duplication용):**

```
### YYYY-MM-DD | Score: X/5
- **Distribution:** 문법 N + 표현 N + 상황 N
- **P1:** [category] [format] [grammar point/pattern#/situation] [topic] [formality] → [result]
- **P2:** ...
- **P3:** ...
- **P4:** ...
- **P5:** ...
- **Errors:** [반복 오류 패턴]
- **Level changes:** [category]: stayed/advanced/dropped
- **Patterns practiced:** [pattern numbers]
- **Situations used:** [situation types]
```
