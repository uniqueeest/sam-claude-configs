---
name: jury-brainstorm
description: "배심원단 토론 시스템. 3명의 독립 에이전트(옹호자/회의론자/중재자)가 만장일치에 도달할 때까지 실제로 토론. 기능 설계, 전략 수립, 의사결정에 사용."
argument-hint: "[주제] [--rounds 3|5] [--save]"
allowed-tools: Read, Glob, Write, Edit, Bash, AskUserQuestion, Task, TeamCreate, TeamDelete, SendMessage, TaskCreate, TaskUpdate, TaskList, TaskGet
---

# 배심원단 브레인스토밍 시스템 (Jury Brainstorm)

David Eagleman의 "Incognito" — 뇌는 라이벌로 이루어진 팀.
3명의 독립 에이전트가 실제로 메시지를 주고받으며 만장일치에 도달할 때까지 토론한다.

---

## 매개변수 파싱

사용자 입력에서 다음을 추출한다:
- `topic`: 토론 주제 (필수, `--` 플래그를 제외한 나머지 텍스트 전부)
- `--rounds`: 최대 라운드 수 (기본값: 5, 허용값: 3 또는 5)
- `--save`: 결과를 파일로 저장할지 여부 (플래그 존재 시 true)

---

## Phase 0: SETUP (주제 분석)

1. 사용자 입력에서 `topic`, `--rounds`, `--save`를 파싱한다.
2. 주제를 분석하여 **핵심 쟁점 3개**를 도출한다. 쟁점은 서로 다른 관점에서의 판단이 필요한 하위 질문이다.
3. `AskUserQuestion`으로 사용자에게 도출된 쟁점을 보여주고 확인/조정 기회를 제공한다:
   - 옵션 1: "이대로 진행" (Recommended)
   - 옵션 2: "쟁점 수정하고 싶습니다"
4. 쟁점이 확정되면 다음 Phase로 진행한다.

---

## Phase 1: SUMMON (배심원 소환)

1. `TeamCreate`로 팀을 생성한다:
   - team_name: `jury-brainstorm`
   - description: `배심원단 토론: {topic}`

2. 3개의 TaskCreate로 작업을 정의한다:
   - "Advocate 개회 진술 작성"
   - "Skeptic 개회 진술 작성"
   - "Mediator 개회 진술 작성"

3. Task 도구로 3개 에이전트를 **동시에** spawn한다 (각각 별도 Task 호출, 병렬 실행):

**Advocate spawn:**
```
Task(
  subagent_type: "general-purpose",
  name: "advocate",
  team_name: "jury-brainstorm",
  prompt: 아래 Advocate 브리핑 템플릿 사용
)
```

**Skeptic spawn:**
```
Task(
  subagent_type: "general-purpose",
  name: "skeptic",
  team_name: "jury-brainstorm",
  prompt: 아래 Skeptic 브리핑 템플릿 사용
)
```

**Mediator spawn:**
```
Task(
  subagent_type: "general-purpose",
  name: "mediator",
  team_name: "jury-brainstorm",
  prompt: 아래 Mediator 브리핑 템플릿 사용
)
```

### 에이전트 브리핑 템플릿

각 에이전트에게 전달하는 초기 프롬프트:

```
너는 배심원단 토론 시스템의 [{역할명}]이다.

먼저 너의 페르소나 파일을 읽어라: .claude/agents/{역할}.md

## 토론 주제
{topic}

## 핵심 쟁점
1. {쟁점1}
2. {쟁점2}
3. {쟁점3}

## 너의 임무
1. 페르소나 파일(.claude/agents/{역할}.md)을 읽고 너의 역할과 행동 원칙을 숙지한다.
2. 팀 리더(jury-lead)에게 **개회 진술**을 SendMessage로 보낸다.
   - 위 쟁점들에 대한 너의 초기 입장을 페르소나의 응답 형식에 맞춰 작성한다.
3. 이후 팀 리더로부터 라운드별 메시지를 받을 때마다, 페르소나의 응답 형식에 맞춰 회신한다.
4. 모든 응답은 반드시 SendMessage로 팀 리더(jury-lead)에게 보낸다.

지금 바로 페르소나 파일을 읽고 개회 진술을 작성하여 보내라.
```

---

## Phase 2: OPENING STATEMENTS (개회 진술)

1. 3개 에이전트의 개회 진술 응답을 수집한다 (자동 수신 대기).
2. 각 응답에서 주장, 동의 점수를 추출한다.
3. 사용자에게 개회 진술 요약을 표시한다:

```markdown
## 개회 진술 요약

### 🔥 Advocate (옹호자)
{advocate 주장 요약}
> 동의 점수: {점수}/10

### 🧊 Skeptic (회의론자)
{skeptic 주장 요약}
> 동의 점수: {점수}/10

### ⚖️ Mediator (중재자)
{mediator 종합 요약}
> 동의 점수: {점수}/10
```

4. 합의 체크: 전원 8+ 이면 Phase 4로 (극히 드물지만 가능).

---

## Phase 3: DELIBERATION LOOP (토론 루프)

```
for round in 1..max_rounds:
```

### 3-1. 라운드 메시지 구성

이전 라운드의 모든 논거를 종합하여 각 에이전트에게 보낼 메시지를 구성한다:

```
[Round {N} / {max_rounds}]
주제: {topic}
현재 쟁점: {current_issue — Mediator가 지정한 다음 라운드 핵심 쟁점, 없으면 순차적으로 쟁점 진행}

이전 라운드 논거:
---
🔥 Advocate:
{advocate_prev_argument}

🧊 Skeptic:
{skeptic_prev_argument}

⚖️ Mediator:
{mediator_prev_synthesis}
---

당신의 역할에 따라 다음을 제출하세요:
1. **주장** (Argument): 현재 쟁점에 대한 당신의 입장
2. **반론** (Rebuttal): 상대 주장에 대한 응답
3. **동의 점수** (0-10): 현재 논의 방향에 대한 동의 정도
4. **코멘트**: 동의 점수의 이유

{라운드별 추가 지시 — 아래 참조}
```

### 3-2. 라운드별 추가 지시

각 라운드마다 Mediator에게 추가 지시를 포함한다:

- **Round 1-2**: (추가 지시 없음. 자유 토론.)
- **Round 3**: Mediator에게 추가: `"이번 라운드에서는 양측의 양보 가능 영역을 적극적으로 식별하고, 구체적인 수렴 방향을 제시하세요."`
- **Round 4**: Mediator에게 추가: `"이번 라운드에서는 조건부 합의안을 구체적으로 제시하세요. 실행 가능한 형태로 작성하고, 양측이 수용 가능한 조건을 명시하세요."`
- **Round 5**: 전원에게 추가: `"최종 라운드입니다. 합의에 도달하지 못하면 다수결로 진행되며, 소수 의견은 소수의견서로 기록됩니다. 최종 입장을 제출하세요."`

### 3-3. 메시지 전송 & 응답 수집

3개 에이전트에게 **동시에** SendMessage로 라운드 메시지를 전송한다.
각 에이전트의 응답을 수집한다 (자동 수신 대기).

### 3-4. 합의 판정

모든 응답이 수집되면:
1. 각 에이전트의 동의 점수를 추출한다.
2. **전원 8+ → CONSENSUS REACHED** → Phase 4로 이동.
3. **미달 → 사용자에게 라운드 요약 표시** → 다음 라운드.

### 3-5. 사용자에게 라운드 요약 표시

```markdown
## Round {N} / {max_rounds}

### 🔥 Advocate
{주장 요약}
> 동의: {점수}/10

### 🧊 Skeptic
{주장 요약}
> 동의: {점수}/10

### ⚖️ Mediator
{종합 요약}
> 동의: {점수}/10 | 합의 가능성: {높음/보통/낮음}
```

### 3-6. 사용자 개입 기회

라운드 요약 표시 후, `AskUserQuestion`으로:
- 옵션 1: "계속 진행" (Recommended)
- 옵션 2: "새로운 관점/정보 추가"
- 옵션 3: "토론 중단하고 현재까지 결과 정리"

"새로운 관점 추가" 선택 시: 사용자 입력을 다음 라운드 메시지에 `[사용자 추가 관점]`으로 포함.
"토론 중단" 선택 시: Phase 4로 즉시 이동.

---

## Phase 4: VERDICT (판결)

### 만장일치 도달 시
Mediator에게 SendMessage:
```
만장일치에 도달했습니다. 다음을 정리하여 제출하세요:
1. 최종 합의안 (1-3문장 핵심 결론)
2. 핵심 논거 요약 (양측)
3. 조건부 사항 (합의안이 유효하기 위한 전제 조건)
4. 잔존 리스크 (합의했지만 경계해야 할 것)
5. 후속 액션 제안 (3개)
```

### 최대 라운드 소진 시
Mediator에게 SendMessage:
```
최대 라운드가 소진되었습니다. 다음을 정리하여 제출하세요:
1. 다수 의견 (가장 높은 동의를 받은 방향)
2. 소수 의견서 (반대 입장의 핵심 논거)
3. 합의된 부분과 합의되지 않은 부분 분리
4. 조건부 사항
5. 잔존 리스크
6. 후속 액션 제안 (3개)
```

### 최종 결과 출력

Mediator의 정리를 바탕으로, 전체 토론 경과를 종합하여 다음 템플릿으로 사용자에게 출력한다:

```markdown
# 배심원단 브레인스토밍 결과

> **주제**: {topic}
> **일시**: {날짜}
> **라운드**: {완료 라운드}/{max_rounds} ({만장일치 도달 / 다수결})

---

## 최종 결론
{합의안 또는 다수 의견 1-3문장}

---

## 핵심 논거 요약

### 🔥 기회 & 가능성 (Advocate)
- {핵심 주장 1}
- {핵심 주장 2}

### 🧊 리스크 & 제약 (Skeptic)
- {핵심 반론 1}
- {핵심 반론 2}

### ⚖️ 종합 판단 (Mediator)
- {수렴점 1}
- {수렴점 2}

---

## 토론 경과
| Round | 쟁점 | 🔥 점수 | 🧊 점수 | ⚖️ 점수 | 결과 |
|-------|------|---------|---------|---------|------|
{각 라운드별 행}

---

## 조건부 사항
- {합의안이 유효하기 위한 전제 조건들}

## 잔존 리스크
- {합의했지만 여전히 경계해야 할 것들}

---

## 소수 의견서 (해당 시)
> {만장일치가 아닌 경우, 반대 의견의 핵심 논거}

---

## 후속 액션 제안
1. {다음 단계 1}
2. {다음 단계 2}
3. {다음 단계 3}
```

---

## Phase 5: CLEANUP

1. 3개 에이전트에게 `SendMessage`로 `shutdown_request` 전송:
   ```
   SendMessage(type: "shutdown_request", recipient: "advocate", content: "토론 종료. 수고했습니다.")
   SendMessage(type: "shutdown_request", recipient: "skeptic", content: "토론 종료. 수고했습니다.")
   SendMessage(type: "shutdown_request", recipient: "mediator", content: "토론 종료. 수고했습니다.")
   ```

2. `TeamDelete`로 팀 정리.

3. `--save` 옵션이 있었다면:
   - `brainstorms/` 디렉토리가 없으면 생성
   - 최종 결과를 `brainstorms/{YYYY-MM-DD}_{주제요약}.md`에 저장 (Write 도구 사용)
   - 사용자에게 저장 경로 안내

---

## 에러 처리

- **에이전트 응답 타임아웃**: 특정 에이전트가 응답하지 않으면, 해당 에이전트의 이전 라운드 입장을 유지하고 나머지로 라운드를 진행한다.
- **팀 생성 실패**: 사용자에게 에러를 보고하고 종료한다.
- **동의 점수 파싱 실패**: 해당 에이전트에게 재요청하되, 2회 실패 시 점수를 5/10으로 간주한다.
