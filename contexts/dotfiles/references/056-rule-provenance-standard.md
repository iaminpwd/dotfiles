---
role: Senior Prompt Architect
priority: high
trigger: Apply these rules when adding, reviewing, or deleting any rule clause in this repository's rulebooks (contexts/*.md).
references:
  - contexts/dotfiles/references/050-prompt-engineering-standard.md
reviewed: 2026-07-26
---
# 컨텍스트 모듈: 규칙의 근거와 승격 표준 (Rule Provenance & Promotion)

본 모듈은 룰북에 조항을 추가·검토·삭제할 때 적용됩니다. 규칙의 문체와 크기 제약은 `050-prompt-engineering-standard.md`를 참조하십시오.

## 1. 핵심 설계 원칙
- **[MUST]** 룰북의 가치는 "에이전트가 스스로는 하지 않았을 행동"을 만드는 부분에서만 발생합니다. 에이전트가 이미 수행하는 일반론은 토큰을 소비하면서 남은 규칙의 어텐션을 희석시키므로, 조항 수를 늘리는 대신 근거 있는 조항의 밀도를 높이십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

- **[MUST] 근거 병기:** 새 규칙에는 그 규칙을 만들게 한 구체적 사건(발생 일자, 대상, 증상)을 조항 안에 함께 적으십시오. 근거를 적을 수 없다면 추가하지 말고 에이전트의 기본 동작에 맡기십시오.
- **[MUST] 삭제 판정:** 기존 조항을 검토할 때 "이 문장을 지우면 에이전트가 다르게 행동하는가"를 물으십시오. 답이 '아니오'인 조항은 삭제하십시오.
- **[MUST] 4단계 승격:** 관찰된 실패는 아래 순서로 올릴 수 있는 단계까지 올리십시오. 규칙보다 검증기가, 검증기보다 회귀 픽스처가 재발을 확실히 막습니다.
  1. **실패 관찰** — 증상·대상·일자를 기록
  2. **규칙 추가** — 근거를 조항에 명시
  3. **기계 검증** — pass/fail 판정이 가능하면 검증 스크립트로 이관
  4. **회귀 픽스처** — 실패를 재현하는 입력을 고정하고 기대 결과를 등록
- **[MUST] 참조 구현 준수:** `contexts/drawio-gen`이 4단계를 모두 갖춘 기준 사례입니다. 검증기는 `~/dotfiles/contexts/drawio-gen/scripts/layout_toolkit.py`의 `validate()`, 픽스처는 `tests/fixtures/`, 기대 결과 대조는 `tests/run.sh`입니다. 새 검증 로직을 추가할 때는 이 구조를 그대로 따르십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good] 근거가 붙어 재발을 막는 조항
```markdown
- **[MUST] 행 높이 불일치 시 `uniform_row()` 재적용**: 통일 높이를 계산해놓고 컨테이너
  `height` 인자에 반영하지 않아 바닥선이 어긋난 회귀가 있었다(2026-07-22, his-infra).
```
</example>
<example>
[Bad] 에이전트가 이미 수행하는 일반론 (삭제 대상)
```markdown
- **[MUST] 보안을 위해 최소 권한 원칙을 적용하십시오.**
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 추가한 조항마다 근거(일자·대상·증상)가 본문에 기재되어 있고, 3~4단계로 승격 가능한 항목은 검증 스크립트와 회귀 픽스처까지 반영되어야 합니다.
- **[MUST] 검증 도구 매핑:** `contexts/dotfiles/scripts/prompt-lint.sh`로 코퍼스 정합성을 확인하고, 검증기를 수정한 경우 해당 스킬의 회귀 테스트(예: `~/dotfiles/contexts/drawio-gen/tests/run.sh`)를 실행하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Rule Authored] 점검 기준 (절차는 000-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (근거): 추가한 조항에 그 규칙을 만들게 한 구체적 사건이 명시되었는가?
  - 기준 2 (승격): 스크립트로 pass/fail 판정이 가능한 조항인데 문서 규칙에만 머물러 있지는 않은가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 근거를 제시할 수 없는 조항을 추가하려는 패턴이 감지되면 즉시 중단하고, 해당 동작을 에이전트 기본 동작에 맡길지 사용자에게 확인하십시오.
  - 기존 검증 스크립트를 수정하면서 회귀 픽스처를 함께 갱신하지 않은 상태로 완료를 선언하려 하면 즉시 중단하고 픽스처를 먼저 추가하십시오.
