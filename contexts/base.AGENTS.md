# 공통 작업 지침

## 1. 판단과 질문
- **[PREFER] Explicit Assumptions:** 결과에 영향을 주는 가정은 짧게 밝히고 진행할 것. 필수 정보가 없거나 사용자만 결정할 수 있는 경우에 질문할 것.
- **[MUST] Halt on Confusion:** 기존 요청과 승인 범위에서 진행하되, 안전하게 다음 행동을 결정할 수 없으면 필요한 정보를 구체적으로 질문할 것.

## 2. 구현 범위
- **[PREFER] 단순성:** 요청을 충족하는 가장 단순한 변경을 선택할 것. 추가 아키텍처 변경은 필요성과 영향을 설명할 것.

## 3. 변경 관리
- **[MUST] Strict Scope Isolation:** 요청 범위 밖의 코드·포매팅·주석과 사용자의 기존 변경을 보존하고, 새 코드는 파일의 기존 스타일을 따를 것.
- **[MUST] Traceability:** 지정된 위치의 수정은 그 위치에 한정하고, 결함 클래스의 수정 요청은 같은 클래스의 인스턴스까지 조사할 것. 범위 밖 발견 사항은 보고할 것.

## 4. 검증
- **[MUST] Eval-Driven Testing:** 변경한 동작에 해당하는 기존 검사와 회귀 테스트를 실행하고, 통과·실패·미실행을 구분해 보고할 것. 검증되지 않은 새 핵심 동작에는 필요한 테스트를 추가할 것.
- **[MUST] Scoped & Safe Verification:** 변경 영향에 맞는 최소 검증 단위를 선택하고, 자동 수정 없는 검사를 우선할 것. 자동 수정은 사용자가 승인한 변경 범위 안에서만 수행할 것.
- 테스트(`tests/`)와 평가(`evals/`)는 런타임 스킬 폴더에 동기화되지 않으므로 원본 저장소의 `contexts/<skill>/tests/` 등을 사용할 것.
- 완료 시 변경 내용과 검증 결과, 재현에 필요한 명령을 간결하게 제공할 것.

## 5. 문서와 환경 조회
- **[PREFER] Proactive Skill Verification:** 작업에 해당하는 스킬과 필요한 참조 문서를 읽을 것. 추가 참조는 현재 판단에 필요한 경우에만 읽을 것.
- **[MUST] Strict Fact-Based Verification:** 불확실하거나 버전에 따라 달라지는 명령·설정은 로컬 도움말 또는 공식 문서로 확인할 것.
- **[PREFER] Context Budget Optimization:** 검색으로 관련 위치를 좁힌 뒤 필요한 부분을 조회할 것.
- **[MUST] Korean as Primary Language:** 답변과 새 문서는 한국어를 기본으로 하고, 코드 주석은 해당 파일의 기존 언어와 스타일을 따를 것.

## 6. 실행과 권한
- **[PREFER] Tool Availability Gate:** 도구가 없으면 설치된 대체 도구를 확인할 것. 동등한 검증이나 작업이 불가능할 때 필요한 도구와 미완료 사항을 보고할 것.
- **[MUST] Permission Boundary:** 관리자 권한은 작업에 필요한 최소 범위로 요청할 것.
- **[Trigger: `/learn` Command Executed] Prompt Architect Loading:** 룰 수정 제안서를 작성하기 전에 `prompt-architect` 스킬을 읽을 것.
- **[Trigger: After Code Change] Autonomous Self-Healing:** 검증 실패 원인을 확인해 요청 범위 안에서 수정하고 재검증할 것. 파괴적 변경에 대한 승인은 별도로 확인할 것.
- **[Trigger: Validation Failed 3 Times] Fast Fail & Halt:** 같은 검증 실패가 수정 시도 3회 후에도 지속되면 해당 재시도를 멈추고 원인과 필요한 개입을 보고할 것.
- **[MUST] Break-Glass:** 사용자가 보안·아키텍처 규칙의 예외를 명시적으로 승인하면 `tech-debt-log.md`에 일자, 위반 규칙, 승인 이유, 상환 계획을 기록할 것.

## 7. 보안
- **[MUST] Local Separation:** 자격 증명과 민감 변수는 Git 추적 제외된 `.env` 또는 `.local`에 분리할 것.
- **[MUST] Explicit Permission for Private Keys:** 프라이빗 키를 읽기 전에 목적을 설명하고 승인을 받을 것.
- **[MUST] No Hardcoded Secrets:** 시크릿은 환경 변수 또는 시크릿 매니저로 주입할 것.
- **[Trigger: Security Vulnerability Found] Hard Block:** 취약점을 악화시키거나 시크릿을 노출하는 실행을 중단하고 보고할 것. 요청 범위의 안전한 조사와 취약점 수정은 계속할 것.
- **[MUST] Sensitive Data Masking:** 로그·대화·예시에서 실제 민감 값은 `***`로 마스킹할 것.

## 8. Git
- **[MUST] Semantic Commits in Korean:** 커밋 메시지는 `feat:`, `fix:` 등의 접두사와 한국어 설명·본문을 사용할 것.
- **[MUST] Explicit Atomic Commits:** 커밋 요청 시 변경을 논리적 단위로 나눌 것.
- **[MUST] Pre-Commit Gate:** 커밋 전 해당 변경의 필수 검증을 통과하고 검증 훅을 우회하지 않을 것.

## 9. 변경 근거
- **[Trigger: After Code Change Guided by a Specific Rule] Provenance Logging:** 특정 `contexts/` 룰을 근거로 코드를 수정했으면 `record-provenance.sh <file_path> <rule_source> <purpose>`로 기록할 것. `rule_source`는 `<스킬>/<파일명>` 형식이며 여러 근거는 콤마로 구분할 것. 직접 지시·오타 수정처럼 매핑되는 룰이 없으면 생략할 것.
- **[Trigger: Ask for Code Provenance] Audit Edits Log:** 변경 근거를 질문받으면 `.agent-state/edits.log`의 해당 이력을 확인하고 답할 것.
- **[Trigger: Repeated Rule-Related Failure] Quality Flywheel:** 룰로 인한 실패가 반복되면 `.agent-state/edits.log` 최근 20줄과 해당 룰을 확인해 개정안을 제안할 것.
