---
role: Senior Prompt Architect
priority: high
trigger: Apply these rules when adding, reviewing, or deleting any rule clause in this repository's rulebooks (contexts/*.md).
references:
  - contexts/dotfiles/references/050-prompt-engineering-standard.md
---
# 컨텍스트 모듈: 규칙의 근거와 승격 표준 (Rule Provenance & Promotion)

본 모듈은 룰북에 조항을 추가·검토·삭제할 때 적용됨. 규칙의 문체와 크기 제약은 `050-prompt-engineering-standard.md`를 참조할 것.

## 1. 핵심 설계 원칙
- **[MUST]** 룰북의 가치는 "에이전트가 스스로는 하지 않았을 행동"을 만드는 부분에서만 발생함. 에이전트가 이미 수행하는 일반론은 토큰을 소비하면서 남은 규칙의 어텐션을 희석시키므로, 조항 수를 늘리는 대신 근거 있는 조항의 밀도를 높이십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

- **[MUST] 고유 규칙 집중:** 에이전트가 수행할 도메인 특화 핵심 동작만 추가할 것.
- **[MUST] 삭제 판정:** 기존 조항을 검토할 때 "이 문장을 지우면 에이전트가 다르게 행동하는가"를 물으십시오. 답이 '아니오'인 조항은 삭제할 것.
- **[MUST] 참조 구현 준수:** `contexts/drawio-gen`이 기준 사례임. 검증기는 `~/dotfiles/contexts/drawio-gen/scripts/layout_toolkit.py`의 `validate()`, 픽스처는 `tests/fixtures/`, 기대 결과 대조는 `tests/run.sh`입니다. 새 검증 로직을 추가할 때는 이 구조를 그대로 따르십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good] 판정 대상이 특정되어 재발을 막는 조항 (사건 서술 없음)
```markdown
- **[MUST] 행 높이 불일치 시 `uniform_row()` 재적용**: `row_height()`로 계산한 값은
  각 컨테이너의 `height` 인자에 반영해야 바닥선이 맞습니다. 계산 후 반드시 적용을 완료할 것.
```
</example>
<example>
[Bad] 에이전트가 이미 수행하는 일반론 (삭제 대상)
```markdown
- **[MUST] 보안을 위해 최소 권한 원칙을 적용할 것.**
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 조항 본문에는 판정 기준만 남아 있어야 합니다.
- **[MUST] 검증 도구 매핑:** `contexts/dotfiles/scripts/prompt-lint.sh`로 코퍼스 정합성을 확인하고, 검증기를 수정한 경우 해당 스킬의 회귀 테스트(예: `~/dotfiles/contexts/drawio-gen/tests/run.sh`)를 실행할 것. 변경된 스킬의 회귀 테스트는 `pre-commit` 훅이 자동 선택 실행함.
- **[MUST] 조항 품질은 사람이 판정:** 조항 리뷰는 사람이 직접 수행할 것.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Rule Authored] 점검 기준 (절차는 000-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1: 스크립트로 pass/fail 판정이 가능한 조항인데 문서 규칙에만 머물러 있지는 않은가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 기존 검증 스크립트를 수정하면서 회귀 픽스처를 함께 갱신하지 않은 상태로 완료를 선언하려 하면 즉시 중단하고 픽스처를 먼저 추가할 것.
