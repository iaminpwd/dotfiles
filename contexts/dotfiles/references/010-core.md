---
role: Universal Cognitive Engine Architect
priority: high
trigger: dotfiles 워크스페이스에서 모든 스킬 공통으로 로드되는 최상위 인지/자율 행동 표준 (개별 도메인 모듈이 본 문서를 참조). base.AGENTS.md(전역, 항상 병행 로드)가 이미 적용되므로, 여기엔 그 문서에 없거나 그 문서를 완화·보강하는 dotfiles 고유 규칙만 정의한다.
---
<universal_meta_cognitive_engine>
# 000. dotfiles 전용 인지 엔진 보강분 (base.AGENTS.md 확장)

`base.AGENTS.md`(전역, 항상 병행 로드)에 없는 dotfiles 고유 규칙만 정의함. 공통 변경·검증·권한 규칙은 base.AGENTS.md를 따른다.

## 2. 자가 비판 절차 SSOT
- **[PREFER] 공통 자가 비판 절차 (전 dotfiles 모듈 SSOT):** 본 파일 및 하위 참조 모듈(020, 030, 040, 050, 060)의 점검 기준 중 현재 변경에 해당하는 항목을 확인할 것. 필수 검증의 실패는 해결하고, 관련 없는 항목의 점검이나 별도 자가비판 출력은 생략할 것.

## 3. 형제 인스턴스 점검 (base.AGENTS.md §3 보강)
- **[Trigger: Defect Fixed] Sibling Sweep:** 결함을 고쳤으면 그 결함을 한 문장으로 규정한 뒤, 고친 코드가 아니라 그 규정으로 같은 클래스의 다른 위치를 1회 검색할 것 (예: 한 표기를 막았으면 나머지 표기, 한 경로를 제외 목록에 넣었으면 같은 목록을 쓰는 다른 지점). 발견분의 처리는 base.AGENTS.md §3 Traceability의 매핑 단위를 따른다.

## 4. 실패 보고 양식 (base.AGENTS.md §6 Fast Fail & Halt 보강)
- **[Trigger: Validation Failed 3 times] 빠른 실패 및 중단:** base.AGENTS.md §6 Fast Fail & Halt가 발동되면(3회 재시도 실패), 해당 재시도를 멈추고 실패 단계, 원인, 필요한 개입을 보고할 것. 아래는 보고 예시임.
  ```markdown
  ### [문제 상황 요약]
  - **현재 단계**: [실패한 단계명]
  - **원인 분석**: [실패 원인 및 에러 로그]
  - **추천 대안**: [추천하는 해결책과 그 이유]
  ```
</universal_meta_cognitive_engine>
