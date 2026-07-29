---
role: Senior Dotfiles Architect
priority: high
trigger: Apply these rules when writing a plan or handoff blueprint for work inside this dotfiles repository (setup.sh, shell configs, rulebooks, skills).
references:
  - contexts/dotfiles/references/000-core.md
  - contexts/dotfiles/references/020-shell-scripting-standard.md
  - contexts/dotfiles/references/050-prompt-engineering-standard.md
  - contexts/dotfiles/references/056-rule-provenance-standard.md
---
# 컨텍스트 모듈: dotfiles 작업 계획서(설계도) 작성 표준

본 모듈은 이 저장소의 작업을 직접 수행하지 않고 계획서나 핸드오프 설계도(`Claude-to-Gemini.md`)로 위임할 때 적용됨. 위임 시 실행자는 저장소의 배포 구조와 린터 연쇄 제약을 모르는 상태에서 지시만 보고 움직이므로, 그 두 가지를 설계도에 명시적으로 실어 보내는 것이 이 표준의 목적임.

## 1. 핵심 설계 원칙
- **[MUST] 6개 목차 준수:** 계획서는 아래 6개 섹션을 한국어 제목으로 구성할 것. 타 에이전트 위임용 설계도로 발행할 때는 3~5번이 각각 `## 3. Action Plan` / `## 4. Verification` 에 대응됨.
  1. 목표 및 성공 기준 (Goal & Success Criteria)
  2. 영향 파일 및 배포 반영 경로 (Impact & Deployment Path)
  3. 룰북 정합성 연쇄 영향 (Corpus Consistency Impact)
  4. 실행 계획 (Action Plan)
  5. 검증 (Verification)
  6. 롤백 (Rollback)

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 영향 파일 및 배포 반영 경로
- **[MUST] 링크 배포와 복사본 배포를 구분해 기재:** 각 수정 대상이 `setup.sh` 에 의해 심볼릭 링크로 노출되는지, 복사본으로 생성되는지 2번 섹션에 명시할 것. 링크 대상은 저장소 수정이 곧 런타임 반영이지만, 복사본 대상(`contexts/agent-handoff/`)은 `setup.sh` 재실행 전까지 반영되지 않습니다. 이를 적지 않아 개정 직후 턴의 에이전트가 구버전 조항으로 동작한 사례가 있습니다.
- **[MUST] 재배포 필요 여부를 성공 기준에 포함:** 복사본 배포 대상을 수정하는 계획이면 `setup.sh` 재실행과 배포본 대조(`diff`)를 5번 섹션의 검증 항목으로 반드시 넣으십시오.

### 2.2 룰북 정합성 연쇄 영향
- **[MUST] `references/` 신설 시 3개 파일을 한 묶음으로 지시:** 새 `NNN-*.md` 를 추가하는 계획은 아래 세 가지를 모두 4번 섹션에 포함해야 합니다. 하나라도 빠지면 `contexts/dotfiles/scripts/prompt-lint.sh` 가 실패하거나 경고를 냅니다.
  1. 새 모듈 파일 자체
  2. 같은 스킬 `SKILL.md` 의 라우팅 테이블 행 (누락 시 `check_orphaned_files()` WARNING)
  3. 해당 스킬 코어 모듈의 자가 비판 SSOT 모듈 번호 목록 (누락 시 `check_ssot_module_lists()` ERROR)
- **[MUST] 인용 경로는 실재하는 것만:** 계획서에 적는 모든 파일 경로는 작성 직전 `test -f` 로 확인할 것. `prompt-lint.sh` 의 `check_reference_links()` 는 `contexts/<스킬>/references/<NNN>-*.md` 형태의 리터럴 경로만 실재 검증하므로, `<도메인>` 같은 플레이스홀더로 적은 경로는 검사망을 통과함.

### 2.3 실행 계획 및 검증
- **[MUST] 검증은 대상 파일을 직접 조회:** 5번 섹션의 명령은 수정 대상 파일에서 반영 여부를 읽는 명령(`grep -c`, `sed -n`, `diff`)이어야 합니다. 계획서에 옮겨 적은 코드를 실행하는 명령은 대상이 아니라 계획서 자신을 검증하므로 지시 누락을 통과시킵니다.
- **[MUST] 스크립트 수정 시 검증 3종 고정:** `.sh`/`.zsh` 를 수정하는 계획이면 `shellcheck`, `pre-flight-check.sh`, 2회 연속 실행 멱등성 확인을 5번 섹션에 반드시 기재할 것.
- **[MUST] 롤백 경로 명시:** 6번 섹션에 원상 복구 방법을 적으십시오. 커밋 전이면 대상 파일에 한정한 `git checkout --`, 배포본까지 반영된 뒤면 되돌린 원본으로 `setup.sh` 재실행임.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good] 배포 경로와 연쇄 영향을 명시한 2·3번 섹션
```markdown
## 2. 영향 파일 및 배포 반영 경로
- `contexts/example-skill/custom-role.md` — 복사본 배포. setup.sh 재실행 필요.
- `contexts/dotfiles/SKILL.md` — 링크 배포. 저장소 수정이 곧 반영.

## 3. 룰북 정합성 연쇄 영향
- `005-` 신설 → `contexts/dotfiles/SKILL.md` 라우팅 행 + `000-core.md` SSOT 목록에 005 추가 필요.
```
</example>
<example>
[Bad] 배포 방식과 연쇄 영향이 빠져 실행자가 반영 실패를 감지할 수 없음
```markdown
## 2. 영향 파일
- contexts/agent-handoff/ 아래 스킬 문서
- 관련 룰북 몇 개
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** 6개 섹션이 모두 채워져 있고, 2번 섹션의 모든 경로가 `test -f` 로 확인되었으며, 5번 섹션의 명령이 계획서가 아닌 대상 파일을 조회함.
- **[MUST] 검증 도구 매핑:** 지정된 린터 도구 또는 `pre-flight-check.sh`로 일괄 검증할 것. (이유: 구문 검증 강제)
## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Before Publishing Plan] 점검 기준 (절차는 000-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (경로 실재): 계획서에 등장하는 모든 파일 경로를 실제로 조회해 확인했는가?
  - 기준 2 (연쇄 누락): 룰북·스크립트 수정이 유발하는 린터 연쇄 제약을 4번 섹션에 지시로 포함했는가?
  - 기준 3 (검증 독립성): 5번 섹션의 명령이 계획서 본문이 아니라 대상 파일을 조회하는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 계획서에 적으려는 경로가 실재하지 않는 것으로 확인되면 즉시 발행을 멈추고, 그 경로를 신규 생성 지시로 바꿀지 삭제할지 결정한 뒤 다시 작성할 것.
