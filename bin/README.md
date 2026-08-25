# Bin Utilities & Hooks Catalog

`bin/` 디렉토리는 로컬 개발 환경 구성, 사전 안전성 검증(Pre-Flight Check), AI 에이전트 훅 및 프롬프트 자가 진화를 지원하는 **모듈화된 쉘 스크립트 도구함**입니다.

---

## 디렉토리 구조

```text
bin/
├── hooks/        # Git pre-commit 및 AI PostToolUse 이벤트 훅 스크립트
├── linters/      # 마크다운 룰북, 시맨틱 커밋, 멱등성 등 정적 분석 린터
├── utils/        # AI 이력 기록, 프롬프트 진화, 심볼릭 링크 백업 유틸리티
└── lib/          # 스크립트 공용 탐색 및 헬퍼 라이브러리
```

---

## 카테고리별 주요 스크립트 명세

### 1. `hooks/` (이벤트 훅 & 파이프라인)

| 스크립트 | 역할 및 핵심 기능 | 실행 예시 |
|---|---|---|
| **`pre-flight-check.sh`** | 스테이징/수정된 파일 종류에 맞춰 `shellcheck`, `tflint`, `checkov`, `ansible-lint`, `hadolint`, `trivy`, `infracost` 등을 통합 실행하는 고성능 검증 훅 | `bin/hooks/pre-flight-check.sh` |
| **`run-suite.sh`** | AI 에이전트의 토큰 폭주를 막기 위해 통과한 검증 항목을 `-> [✓] <경로>` 한 줄로 접고 실패 시 원형 로그를 보존하는 검증 래퍼 | `bin/hooks/run-suite.sh` |
| **`agent-edits-hook.sh`** | Claude Code 및 Antigravity가 파일을 변경할 때마다 `.agent-state/edits.log`에 편집 사유 및 목적을 기록하는 PostToolUse 훅 | (에이전트 훅 자동 호출) |
| **`plugins/`** | 워크스페이스 전용 린터(`kyverno`, `promtool` 등)를 자동 탐색하여 위임 실행하는 동적 플러그인 디렉토리 | (내부 위임 호출) |

---

### 2. `linters/` (정적 분석 & 컨벤션 검증)

| 스크립트 | 역할 및 핵심 기능 | 실행 예시 |
|---|---|---|
| **`prompt-lint.sh`** | 마크다운 룰북(`AGENTS.md`, `SKILL.md`) 및 프롬프트의 구조, YAML 린트, 필수 태그, `EXCEPTION APPLIED` 마커의 형식 준수 및 완화 대상 룰 실재성을 정적 분석 | `bin/linters/prompt-lint.sh` |
| **`semantic-commit-lint.sh`** | `feat:`, `fix:`, `docs:` 등 시맨틱 커밋 메시지 컨벤션을 검증하는 `commit-msg` 훅 | `bin/linters/semantic-commit-lint.sh .git/COMMIT_EDITMSG` |
| **`idempotency-check.sh`** | 셸 스크립트를 정적 분석해 가드 없는 append(`>>`/`tee -a`)를 경고 (재실행 시 설정이 중복 증식하는 비멱등 패턴 탐지). 파일 인자를 받으며, 인자가 없으면 아무것도 하지 않음 | `bin/linters/idempotency-check.sh <파일...>` 또는 `just check-idempotency <파일>` |
| **`container-hardening-gate.sh`** | 컨테이너 이미지 및 Dockerfile non-root/distroless 하드닝 검증 게이트 | `bin/linters/container-hardening-gate.sh` |
| **`db-sg-checker.sh`** | IaC 코드 내 DB 보안그룹 인바운드가 인터넷 전체(0.0.0.0/0·::/0)에 열렸는지 검증 (포트 범위·`protocol = "-1"` 로 DB 포트를 포함해 여는 형태 포함) | `bin/linters/db-sg-checker.sh` |
| **`test-coverage-check.sh`** | `bin/` 하위 검사 스크립트가 `contexts/*/tests`에서 최소 1개 이상 회귀 테스트로 참조되는지 게이트 (정적분석이 못 잡는 판정 로직 결함 대비) | `bin/linters/test-coverage-check.sh` |

---

### 3. `utils/` (운영 & AI 자율 관리 유틸리티)

| 스크립트 | 역할 및 핵심 기능 | 실행 예시 |
|---|---|---|
| **`record-provenance.sh`** | 파일 변경 시 근거 룰북 및 수정 목적 1줄을 `.agent-state/edits.log`에 기록 | `bin/utils/record-provenance.sh <file> <rule_source> <purpose>` |
| **`merge-agent-hooks.sh`** | Claude Code와 Antigravity의 PostToolUse 훅 설정을 안전하게 병합 | `bin/utils/merge-agent-hooks.sh` |
| **`stow-backup.sh`** | Stow 심볼릭 링크 생성 전 기존 파일 백업 | `bin/utils/stow-backup.sh` |
| **`broken-symlink-detector.sh`** | 홈 디렉토리(깊이 5)의 끊긴(Broken) 심볼릭 링크 탐지 — **수동 진단 전용**. 어떤 훅·게이트에서도 자동 호출하지 않는다: 판정 대상이 저장소가 아니라 `$HOME` 전체라, 이 저장소와 무관한 링크 하나가 임의 저장소의 커밋을 막게 된다. 스킬 정리(`prune-orphan-skills.sh`) 후 잔재 확인용으로 직접 실행할 것 | `bin/utils/broken-symlink-detector.sh` |
| **`check-agent-collision.sh`** | AI 에이전트 설정 간 충돌 여부 점검 | `bin/utils/check-agent-collision.sh` |

---

### 4. `lib/` (공통 라이브러리)

| 스크립트 | 역할 및 핵심 기능 |
|---|---|
| **`tool-probe.sh`** | 시스템 상에 필요한 CLI 도구의 존재 여부 탐색 및 실행 가능 경로 반환 |
| **`git-relpath.sh`** | 파일 경로를 realpath로 정규화하고 소속 git 저장소 루트를 조회 (agent-edits-hook.sh/record-provenance.sh 공용) |

---

## 설계 및 작동 원칙
1. **SSOT 검증 호출**: 개별 저장소에 훅 스크립트 복사본을 두지 않고 `~/dotfiles/bin/`의 정본 스크립트를 직접 실행합니다.
2. **AI 토큰 최적화**: 모든 실행 결과는 성공 시 출력을 최소화하고 실패 시 원형 블랙박스를 남기도록 구성됩니다.
3. **독립 실행 및 멱등성**: 각 스크립트는 `set -euo pipefail`로 보호되며 독립적인 CLI 툴체인 탐색을 지원합니다.
