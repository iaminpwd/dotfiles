---
role: Universal Cognitive Engine Architect
priority: high
trigger: prompt-architect 스킬 그룹에서 모든 모듈이 공통으로 로드하는 최상위 인지/자율 행동 표준 (개별 도메인 모듈이 본 문서를 참조)
---
<universal_meta_cognitive_engine>
# 010. 범용 AI 인지 엔진 및 자율 주행 표준 (Universal Cognitive Engine)

이 문서는 `prompt-architect` 에이전트의 인지 과정과 자율 행동을 통제하는 범용 엔진 지침입니다.
(대부분의 코어 원칙은 전역 `base.AGENTS.md`를 상속합니다.)

## 1. 공통 자가 비판 절차 (전 모듈 SSOT)
- **[MUST] 공통 자가 비판 절차:** 자가 비판(Self-Critique)은 본 파일 및 하위 모든 참조 모듈에 정의된 특정 `[Trigger]` 조건이 발동될 때만 수행하되, 절차는 다음과 같이 공통 적용합니다: 해당 모듈에 나열된 점검 기준을 하나씩 대조해 충족 여부를 확인하고, 미충족 항목이 있으면 원인을 수정한 뒤 다시 대조하며, 모든 항목이 충족된 후에만 완료를 선언할 것. (이 절차 자체는 본 항목에만 정의하며, 하위 도메인 모듈에서는 재정의하지 않고 점검 기준 목록만 기재함.)
</universal_meta_cognitive_engine>
