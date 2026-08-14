---
role: Universal Cognitive Engine Architect
priority: high
trigger: dotfiles 워크스페이스에서 모든 스킬 공통으로 로드되는 최상위 인지/자율 행동 표준 (개별 도메인 모듈이 본 문서를 참조). base.AGENTS.md(전역, 항상 병행 로드)가 이미 적용되므로, 여기엔 그 문서에 없거나 그 문서를 완화·보강하는 dotfiles 고유 규칙만 정의한다.
---
<universal_meta_cognitive_engine>
# 000. dotfiles 전용 인지 엔진 보강분 (base.AGENTS.md 확장)

`base.AGENTS.md`(전역, 항상 병행 로드)에 없는 dotfiles 고유 규칙만 정의함. 그 외 전역 규칙(가정 명시, 대안 제시, 성공 기준, 권한 경계, 자가 치유, Break-Glass 등)은 base.AGENTS.md를 그대로 따른다.

## 1. 검토 강도 완화 (Exhaustive Review Downgrade)
- **[PREFER] Exhaustive Review:** base.AGENTS.md §5.2는 [MUST]이나, `pre-flight-check.sh`/`run-suite.sh` 자동 검증이 대체하므로 이 워크스페이스에서는 [PREFER]로 낮춘다. 에러나 아키텍처 분석 시 관련된 모든 파일을 전수 조사할 것을 권장하되, 수정 대상과 영향 범위가 명확하게 제한된 단순 수정 작업은 전수 조사를 생략하고 즉시 진행할 것.

## 2. 자가 비판 절차 SSOT
- **[MUST] 공통 자가 비판 절차 (전 dotfiles 모듈 SSOT):** 자가 비판(Self-Critique)은 본 파일 및 하위 모든 참조 모듈(020, 030, 040, 050, 060)에 정의된 특정 `[Trigger]` 조건이 발동될 때만 수행하되, 절차는 다음과 같이 공통 적용합니다: 해당 모듈에 나열된 점검 기준을 하나씩 대조해 충족 여부를 확인하고, 미충족 항목이 있으면 원인을 수정한 뒤 다시 대조하며, 모든 항목이 충족된 후에만 완료를 선언할 것. (이 절차 자체는 본 항목에만 정의하며, 하위 도메인 모듈에서는 재정의하지 않고 점검 기준 목록만 기재함.)

## 3. 형제 인스턴스 점검 (base.AGENTS.md §3 보강)
- **[Trigger: Defect Fixed] Sibling Sweep:** 결함을 고쳤으면 그 결함을 한 문장으로 규정한 뒤, 고친 코드가 아니라 그 규정으로 같은 클래스의 다른 위치를 1회 검색할 것 (예: 한 표기를 막았으면 나머지 표기, 한 경로를 제외 목록에 넣었으면 같은 목록을 쓰는 다른 지점). 발견분의 처리는 base.AGENTS.md §3 Traceability의 매핑 단위를 따른다.

## 4. 실패 보고 양식 (base.AGENTS.md §6 Fast Fail & Halt 보강)
- **[Trigger: Validation Failed 3 times] 빠른 실패 및 중단:** base.AGENTS.md §6 Fast Fail & Halt가 발동되면(3회 재시도 실패), 도구 호출을 즉시 멈추고 아래 구조로 사용자 개입을 요청할 것.
  ```markdown
  ### [문제 상황 요약]
  - **현재 단계**: [실패한 단계명]
  - **원인 분석**: [실패 원인 및 에러 로그]
  - **추천 대안**: [추천하는 해결책과 그 이유]
  ```
</universal_meta_cognitive_engine>
