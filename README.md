# Cloud Infrastructure Engineer Dotfiles & AI Brain

클라우드 인프라 엔지니어(Principal DevOps/SRE)를 위한 **로컬 작업 환경 자동 구성**과 **AI 자율 주행 프롬프트 아키텍처**를 하나의 레포지토리로 통합한 올인원 Dotfiles입니다.

단순 터미널 꾸미기를 넘어, **Zero-Trust 보안**, **도구 선언적 버전 관리**, 그리고 **AI(LLM)가 자율적으로 코드를 검증하고 인프라를 진단하는 에이전트 파이프라인**을 로컬 환경에 구축하는 것을 목표로 합니다.

---

## 목차

1. [핵심 기능](#핵심-기능)
2. [설치 가이드](#설치-가이드)
3. [디렉토리 구조](#디렉토리-구조)
4. [작동 논리 및 아키텍처](#작동-논리-및-아키텍처)
5. [포함된 도구 및 생산성 설정](#포함된-도구-및-생산성-설정)
6. [커스터마이징 및 확장](#커스터마이징-및-확장)

---

## 핵심 기능

### 1. Zero-Trust 보안 및 격리
- **글로벌 `.gitignore_global` 강제 적용:** `terraform.tfstate`, `.env`, `.pem` 키가 원격 저장소로 유출되는 사고를 시스템 전역에서 원천 차단합니다.
- **도구 완전 격리:** `mise` 하나로 런타임/CLI 도구는 물론 Python 기반 도구(`pipx:` 백엔드, 내부적으로 `uv` 사용)까지 시스템 전역을 오염시키지 않고 선언적으로 버전을 관리합니다.
- **버전 자동 최신화:** `Renovate`(`.github/renovate.json`)가 `mise` 도구·GitHub Actions·Ansible Galaxy 컬렉션의 뒤처진 버전을 주기적으로 스캔해 PR로 자동 제안하므로, 명시적 버전 고정이 시간이 지나며 방치되어 구버전에 고착되는 걸 막습니다.
- **시크릿 히스토리 차단:** `HIST_IGNORE_SPACE` 설정으로 공백으로 시작하는 커맨드는 터미널 히스토리에 기록되지 않습니다.
- **로컬 시크릿 파일 분리:** API 키와 토큰은 Git이 추적하지 않는 `~/.zshrc.local`, `~/.gitconfig.local`에만 보관하도록 아키텍처를 강제합니다.

### 2. 고성능 사전 안전성 검증 파이프라인 (DX 최적화)
- **정적 분석 및 문법 검증:** `bin/hooks/pre-flight-check.sh`가 스테이징된 변경 파일 종류에 맞춰 `shellcheck`/`shfmt`(쉘), `terraform fmt`/`tflint`/`checkov`(IaC 문법+보안 오구성), `ansible-lint`, `hadolint`(Dockerfile), `conftest`(OPA 정책) 등을 자동 실행합니다. K8s처럼 워크스페이스 전용 도구(`kyverno`, `promtool` 등)가 필요하면 `bin/hooks/plugins/` 디렉토리를 자동 탐색해 위임 호출하므로, 그 디렉토리에 새 검증 스크립트를 넣는 것만으로 파이프라인이 확장됩니다. 위임 대상을 파일 이름이 아니라 위치로 판정하므로, 위임 대상이 아닌 스크립트가 이름만으로 딸려 들어가지 않습니다.
- **의존성 취약점 스캔 (소스 레벨):** `trivy fs --scanners vuln`이 저장소 내 의존성 매니페스트(requirements.txt 등)를 빌드 없이 스캔합니다. 매 커밋마다 이미지를 빌드해 스캔하면 속도 목표와 충돌하므로 소스 레벨로 제한했으며, 취약점은 경고만 남기고 커밋을 막지는 않습니다. 이미지 레이어 자체의 SBOM/취약점/서명은 커밋이 아니라 릴리즈 단계의 책임이며 `syft`/`grype`/`cosign`이 담당합니다.
- **FinOps 비용 게이트:** 커밋 전 `infracost breakdown` 결과에서 Extended Support/LTS(연장 지원) 추가 요금 항목을 탐지하면 커밋 자체를 차단하여, 의도치 않은 예산 초과를 소스에서 원천 방어합니다.
- **시맨틱 커밋 컨벤션 강제:** `commit-msg` 훅이 `feat/fix/docs/chore/...(scope): subject` 형식을 검사하여, 컨벤션을 지키지 않은 커밋 메시지는 자체적으로 차단합니다.
- **글로벌 훅:** `core.hooksPath`로 등록된 전역 훅이 `TruffleHog` 시크릿 스캔 후 위 검증을 실행합니다. 검증 스크립트는 저장소마다 링크를 두지 않고 `~/dotfiles`의 정본을 절대 경로로 직접 호출하므로, 개별 저장소에 훅이나 링크를 챙길 필요가 없습니다. 검증 대상은 `~/workspace` 하위 저장소와 `~/dotfiles` 자신이며, 그 밖의 저장소는 루트에 `bin/hooks/pre-flight-check.sh` 링크를 둔 경우에만 검증합니다.
- **고속 DX 튜닝:** `Trivy` DB를 24시간 주기로 캐싱(`--skip-db-update`)하여 커밋 지연을 단축했습니다(직접 재현 실측: DB 캐시 미스 10.56초 → 캐시 적중 1.17초, 약 89% 단축). 파일 대상 수집은 `find` 전체 탐색이 아니라 `git diff --cached`/`git ls-files` 기반이라 `.git/`, `.terraform/` 등은 애초에 스캔 대상에 들어오지 않습니다. 성공 시 출력 노이즈를 완벽히 제거(`--quiet`)하여 AI가 소모하는 문맥(Context) 토큰도 최소화했습니다.

### 3. SOTA 에이전트 워크플로우 및 프롬프트 아키텍처
로컬 프롬프트 아키텍처에는 Andrew Ng의 Agentic Workflow 디자인 패턴, ReAct/ToT 등의 추론 아키텍처, 그리고 벤더별 공식 가이드를 반영한 고급 프롬프트 설계가 반영되어 있습니다.
이에 대한 상세한 설계 철학 및 기술적 배경은 [Agentic Workflow & Prompt Architecture](contexts/README.md) 문서를 참고하십시오.

### 4. AI Customization Architecture (AI 스킬 동적 주입)
개발자의 로컬 환경 편의성과 팀 Git 협업 순수성을 완전히 분리하면서 최신 AI 에이전트의 Customization Elements(Skills & Rules)를 완벽히 지원하는 독자적 아키텍처입니다.
- **글로벌 룰 자동 주입:** `bootstrap.sh` 실행 시 코어 룰(`base.AGENTS.md`)이 제미나이 Customizations Root(`~/.gemini/config/AGENTS.md`)와 클로드 글로벌 룰(`~/.claude/CLAUDE.md`) 양쪽에 심볼릭 링크로 주입되고, 전역 무시 룰(`.base.aiexclude`)도 함께 배치됩니다.
- **도메인 스킬 글로벌 등록:** 환경별 특화 룰(`contexts/`)은 `~/.gemini/config/skills/<도메인>/SKILL.md` 및 `~/.claude/skills/<도메인>/SKILL.md` 심볼릭 링크로 글로벌 스킬 등록됩니다. AI는 폴더 이동 없이도 작업 맥락을 파악하여 최적의 도메인 스킬(예: aws, azure)을 스스로 호출합니다.
- **프로젝트 루트 단독 매핑:** 워크스페이스 최상단 루트에 `AGENTS.md`와 `CLAUDE.md` 심볼릭 링크를 단독 생성 및 전역 이그노어하여, 로컬 저장소 오염 없이 제미나이와 클로드 에이전트가 100% 무인식 룰 로딩을 지원합니다.
- **AI 편집 이력 자동 기록:** `bin/hooks/agent-edits-hook.sh`가 두 에이전트의 `PostToolUse` 훅으로 등록되어, AI가 파일을 변경할 때마다 `<ISO8601> | <파일경로> | <출처> | <목적> | <결과>` 1줄을 그 프로젝트 루트의 `.agent-state/edits.log`에 누적합니다. 페이로드 스키마가 서로 다른 Claude Code(`tool_name`/`file_path`)와 Antigravity(`toolCall.name`/`TargetFile`)를 한 스크립트가 함께 처리하며, 로그 파일은 전역 이그노어 대상이라 어느 저장소도 오염시키지 않습니다. 이 기록은 프롬프트 자가 진화(`base.AGENTS.md` 9장)의 입력으로 사용됩니다.
- **실시간 사전 검증 훅:** `bin/hooks/pre-flight-live-hook.sh`가 Claude Code `PostToolUse`(`Edit|Write|MultiEdit`)에 등록되어, AI가 파일을 편집한 직후 그 파일 1개만 대상으로 `pre-flight-check.sh`를 `run-suite.sh` 경유로 즉시 실행합니다(`--pfc-args="<파일>"`로 explicit 모드 패스스루, `contexts/*/tests/run.sh` 12개가 딸려오는 기본 전체 수집 분기는 안 탐). 최종 하드 게이트인 `stow/git/.githooks/pre-commit`은 여전히 커밋 시점에만 발동하므로, 이 훅은 그 이전 — "AI가 코드를 짜고 완료를 선언하는 시점" — 의 시차를 좁히는 2차 방어선입니다. 통과 시엔 `decision` 없이 `run-suite.sh`의 압축된 `-> [✓]` 한 줄만 `additionalContext`로 조용히 실어(대화 메시지로는 안 보임) "통과했다"와 "훅이 애초에 안 돌았다"를 구분 가능하게 하고, 실패 시엔 `decision:block` JSON으로 AI에게 즉시 피드백을 줍니다. 훅 자신은 fail-open이라 실패해도 에이전트 루프를 막지 않습니다(최종 판정은 계속 커밋 게이트 몫). `terraform init` 등 네트워크·빌드 의존 검증이 걸리는 `.tf`/`.tfvars`/`.bicep`은 편집마다 돌면 지연이 커서 이 훅에서 제외하고, 커밋 시점 게이트에서만 검증합니다.
- **완료 선언 직전 게이트 훅:** `bin/hooks/pre-flight-gate-hook.sh`가 Claude Code `Stop`(턴 종료 시점)에 등록되어, `base.AGENTS.md`가 명시하던 완료 선언 직전 통합 검증을 프롬프트 문구가 아니라 기계적으로 강제합니다(해당 조항은 훅으로 완전히 대체되어 삭제됨). 범위는 의도적으로 `pre-flight-check.sh --changed` + (dotfiles 저장소일 때만) `prompt-lint.sh` + `test-coverage-check.sh` 3종으로 한정합니다(`contexts/*/tests/run.sh` 12개 스킬 회귀 스위트는 여기 없음 — "검증기 자체가 여전히 맞는가"를 확인하는 것이라 매턴 재확인은 낭비이고, `stow/git/.githooks/pre-push`가 건드린 스킬만 골라 push 시점에 이미 담당합니다. 코어 로직 `bin/lib/*`·`pre-flight-check.sh` 변경 시 전체 스킬을 트리거하는 케이스도 pre-push에 있어 사각지대가 없습니다). 이 3개는 `run-suite.sh`에 명시적 스크립트 경로로 넘겨서 돌립니다. 통과 시엔 `decision` 없이 `run-suite.sh`의 압축된 `-> [✓]` 로그(스크립트당 한 줄)만 `additionalContext`로 조용히 실어 훅이 실제로 검증을 시도했다는 증거를 남기고("통과"와 "애초에 안 돎"을 구분), 실패 시엔 `decision:block` + 압축 없는 원본 로그를 넘깁니다. 커밋되지 않은 변경이 전혀 없는 순수 대화 턴에는 아무것도 실행하지 않고, 무한 재실패 루프 방지를 위해 `stop_hook_active`가 true면 실패해도 조용히 통과시킵니다.
- **AI 토큰 최적화 (범용 압축 래퍼):** AI가 테스트를 구동할 때 장황한 정상 통과(PASS) 로그로 인해 발생하는 토큰 폭주를 막기 위해, 통과한 스크립트를 `-> [✓] <경로>` 한 줄로 접는 `bin/hooks/run-suite.sh`를 전역 룰북의 검증 게이트로 탑재했습니다. 합격 판정은 출력 패턴이 아니라 **각 스크립트의 종료 코드**로만 내리며, 실패 시에는 압축 없이 원형 로그를 보존하여 디버깅 블랙박스를 방지합니다. 실패해도 남은 검증을 끝까지 실행한 뒤 `검증 실패 N/M` 요약으로 차단하고, 통과 항목이라도 `[WARNING]`(도구 미설치로 인한 검증 스킵 등)은 접지 않아 가짜 초록불을 차단합니다. 이 판정 계약은 `contexts/dotfiles/tests/test-run-suite.sh`의 회귀 테스트 8건이 고정합니다(`run-suite.sh`는 `pre-flight-check.sh` 전용이 아니라 저장소 전역 러너라 dotfiles 스킬 소속입니다).

### 5. 엔터프라이즈 AI 프롬프트 세트 내장 (`contexts/` 폴더)
워크스페이스별 특화 룰북과 메타 프롬프트에 적용된 구체적인 프롬프트 엔지니어링 기법(XML 격리, 계급제 우선순위 등)은 [Agentic Workflow & Prompt Architecture](contexts/README.md)에 상세히 명세되어 있습니다.

**워크스페이스별 특화 모듈 (🟢 Production만 표시):**

| 워크스페이스 | 모듈 수 | 주요 커버리지 |
|---|---|---|
| **AWS** (`aws/`) | 12개 (`005`~`100`) | 제로트러스트 보안, 자격증명 격리, FinOps, IaC(Terraform), EKS, Serverless, RDS, Day2 운영 및 사고 대응 |
| **Azure** (`azure/`) | 12개 (`005`~`100`) | 제로트러스트 보안, 자격증명 격리, FinOps, IaC(Terraform), AKS, Serverless, Database, Day2 운영 및 사고 대응 |
| **Dotfiles** (`dotfiles/`) | 10개 (`000`~`060`) | 인지 엔진, 계획서·핸드오프 설계도 작성 표준, 셸 스크립팅 표준, 툴체인 관리, 보안, 메타/범용 프롬프팅, 규칙 근거·승격 표준, 트러블슈팅 |

> K8s, Multi-Cloud, AIOps, Containers, Observability, Drawio-gen은 아직 튜닝 중인 🟡 Draft 워크스페이스입니다. 상세 커버리지는 [contexts/README.md](contexts/README.md)를 참고하십시오.

---

## 설치 가이드

> [!WARNING]
> **지원 OS**: Debian 계열(`apt-get`) · RHEL 계열(`dnf`) · macOS(`brew`)
> `bootstrap.sh`가 실행 시점에 패키지 매니저를 판별해 분기하며, 지원 목록에 없는 환경에서는 즉시 중단됩니다.
>
> **macOS**: 선행 조건은 Homebrew 하나뿐이며 별도 준비물은 없습니다. `bootstrap.sh`는 macOS 기본 bash(3.2)에서 그대로 실행되도록 유지되고(회귀 테스트로 강제), 실행 중에 필수 런타임과 `mise`·`just`·`ansible`을 구성합니다.
> WSL2 사용 시, 반드시 Linux 네이티브 홈 디렉토리(`~/`) 하위에 클론하십시오. `/mnt/c/` 경로에서 실행하면 권한 오류가 발생하며 스크립트가 즉시 종료됩니다.

### Step 1. 저장소 클론
```bash
git clone https://github.com/iaminpwd/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

### Step 2. 자동 셋업 스크립트 실행
```bash
# 실제 적용 (경량 bootstrap.sh 실행 -> mise install 및 just setup / Ansible 자동 실행)
./bootstrap.sh

# 만약 Ansible 변경 사항을 미리 확인하고 싶을 때 (Dry-run)
just setup-dryrun
```

`bootstrap.sh`는 경량 진입점으로서 필수 패키지 및 `mise`, `just`, `ansible`을 준비한 후 제어권을 `Justfile` 및 Ansible Playbook(`ansible/site.yml`)으로 넘겨 모듈화된 셋업을 완료합니다.

`just setup`(Ansible Playbook)은 아래 6개 역할을 순차적으로 실행합니다:

| 역할 (Ansible Role) | 작업 내용 |
|---|---|
| **`packages`** | OS 패키지 매니저(`apt`/`dnf`/`brew`)로 git, zsh, stow 등 필수 툴체인 및 개발 유틸리티 일괄 설치 |
| **`docker`** | Docker Engine을 공식 저장소에 등록해 설치하고 사용자 그룹 권한 구성 (macOS는 Docker Desktop 설치 안내) |
| **`stow`** | 기존 설정 파일 안전 백업 후, `zsh`, `vim`, `git`, `tflint`, `mise` 설정을 홈 디렉토리(`~/`)로 symlink 구성 (`mise`는 `mise install`이 이 단계보다 먼저 필요해 `bootstrap.sh`가 동일한 `stow` 명령으로 한 번 더 앞서 실행 — 멱등이라 안전) |
| **`zsh`** | Oh My Zsh 및 `zsh-autosuggestions`, `zsh-syntax-highlighting` 플러그인 구성 |
| **`ai_agent`** | 글로벌 룰(`base.AGENTS.md`) 주입, `AGENTS.md`/`CLAUDE.md` 링킹, AI 편집 이력 훅(`bin/hooks/agent-edits-hook.sh`, Claude Code·Antigravity 양쪽)과 실시간 사전 검증 훅(`bin/hooks/pre-flight-live-hook.sh`, `PostToolUse`)·완료 선언 직전 게이트 훅(`bin/hooks/pre-flight-gate-hook.sh`, `Stop`)을 Claude Code에 병합 등록 |
| **`tflint`** | IaC 전역 `tflint` 설정(`stow/tflint/.tflint.hcl`)의 플러그인 초기화(`tflint --init`)만 담당 — `~/.tflint.hcl` 배포 자체는 위 `stow` 역할이 수행 |

### Step 3. 터미널 재시작
```bash
exec zsh
# 또는 기존 터미널에서: src
```

### 성공 검증 커맨드
```bash
# mise 도구 설치 확인
mise ls

# Stow symlink 확인
ls -la ~/.zshrc ~/.gitconfig ~/.vimrc ~/.tflint.hcl ~/.config/mise/config.toml

# AI 글로벌 룰 및 스킬 레지스트리 등록 확인
cat ~/.gemini/config/AGENTS.md | head -5
ls ~/.gemini/config/skills/

# 통합 사전 검증 및 테스트 통과 확인 (Justfile 활용)
just check     # pre-flight-check.sh --all: 저장소 전체 파일에 shellcheck/tflint/checkov 등 정적 분석
just test      # contexts/*/tests/run.sh 전체: 각 검사 스크립트가 ok/fail 픽스처를 올바르게 판정하는지 회귀 테스트
just verify    # 위 두 개 + prompt-lint.sh + 커버리지 게이트를 run-suite.sh로 한 번에 실행 (가장 종합적인 검증, 코드 수정 후 최종 확인용)
```

마지막 줄에 `❌`가 하나도 없고 `-> [✓] <경로>`만 쌓여 있으면 통과입니다. 실패한 항목만 원형 로그가 그대로 남으므로 그 부분만 읽으면 됩니다.

---

## 디렉토리 구조

```text
~/dotfiles
├── ansible/              # Ansible 기반 셋업 아키텍처
│   ├── ansible.cfg            # Ansible 글로벌 설정
│   ├── site.yml               # 메인 플레이북 진입점
│   └── roles/                 # 셋업 모듈 (packages, docker, stow, zsh, ai_agent, tflint)
│
├── assets/               # 아키텍처 다이어그램 및 문서용 이미지 자산
│
├── bin/                  # 모듈화된 실행 스크립트 및 훅/린터
│   ├── hooks/                 # pre-flight-check.sh, run-suite.sh, agent-edits-hook.sh 및 plugins/
│   ├── linters/               # semantic-commit-lint.sh, idempotency-check.sh, prompt-lint.sh, test-coverage-check.sh 등
│   ├── utils/                 # record-provenance.sh, stow-backup.sh 등
│   └── lib/                   # tool-probe.sh, git-relpath.sh 등 공용 탐색/헬퍼 라이브러리
│
├── contexts/             # AI 컨텍스트 룰북 단일 진실 공급원 (SSOT)
│   ├── base.AGENTS.md         # 전 워크스페이스 공통 마스터 엔진 (SSOT)
│   ├── base.hooks.json        # Antigravity PostToolUse 훅 정의 템플릿
│   ├── .base.aiexclude        # 글로벌 AI 오염 방지 전역 무시 룰 원본
│   ├── README.md              # 프롬프트 아키텍처 백과사전
│   ├── aws/, azure/, dotfiles/            # 🟢 Production 워크스페이스 룰북
│   └── aiops/, containers/, drawio-gen/, k8s/,
│       multi-cloud/, observability/,
│       openstack/, pre-flight-check/,
│       prompt-architect/                  # 🟡 Draft / 스킬 워크스페이스 룰북
│
├── stow/                 # GNU Stow 대상 패키지 모음 (이 하위 폴더만 심볼릭 링크 대상 — 화이트리스트 방식)
│   ├── git/                  # [배포: ansible stow 역할이 자동 심볼릭 링크]
│   │   ├── .gitconfig             # 글로벌 Git 설정 (alias, pull.rebase=true, hooksPath)
│   │   ├── .githooks/              # 전역 pre-commit·commit-msg 훅 원본 (Stow로 ~/.githooks/에 symlink)
│   │   └── .gitignore_global      # 시스템 전역 Git 무시 규칙 (tfstate, .env 등)
│   │
│   ├── mise/                 # [배포: ansible stow 역할이 자동 심볼릭 링크 (단, mise install이 ansible보다 먼저 필요해 bootstrap.sh가 동일한 stow 명령을 한 번 더 앞서 실행)]
│   │   └── .config/mise/
│   │       └── config.toml   # 인프라 도구 버전 선언 매니페스트 (SSOT, mise 전역 설정 위치)
│   │
│   ├── tflint/                # [배포: ansible stow 역할이 자동 심볼릭 링크]
│   │   └── .tflint.hcl       # IaC 전역 TFLint 규칙 구성
│   │
│   ├── vim/                  # [배포: ansible stow 역할이 자동 심볼릭 링크]
│   │   └── .vimrc            # Vim 설정 (클립보드 연동, YAML 2칸 탭)
│   │
│   └── zsh/                  # [배포: ansible stow 역할이 자동 심볼릭 링크]
│       ├── .zshenv           # Zsh 환경변수 설정 (PATH 등 비대화형 세션 포함)
│       └── .zshrc            # Zsh 설정 (Oh My Zsh, 단축어)
│
├── bootstrap.sh          # 경량 셋업 진입점 스크립트 (set -euo pipefail)
├── Justfile              # 통합 태스크 런너 (just setup, just check, just test)
├── README.md             # 본 문서
└── LICENSE
```

---

## 작동 논리 및 아키텍처

### bootstrap.sh & Ansible 설치 파이프라인
![bootstrap.sh & Ansible Installation Pipeline](assets/setup-pipeline.png)

### GNU Stow 심볼릭 링크 구조
![GNU Stow Symlink Architecture](assets/stow-symlinks.png)

**글로벌 스킬 적용**
모든 도메인 스킬은 `~/.gemini/config/skills/`, `~/.claude/skills/` 심볼릭 링크 레지스트리를 통해 AI 에이전트에게 직접 라우팅되므로, **로컬 소스코드 저장소가 100% 깔끔하게 유지**됩니다.

### AI 컨텍스트 빌드 파이프라인
![AI Context Build Pipeline](assets/ai-context-pipeline.png)

> `bin/hooks/pre-flight-check.sh`의 검증 항목 및 DX 튜닝 상세는 [핵심 기능 §2](#핵심-기능)를 참고하십시오.

---

## 포함된 도구 및 생산성 설정

### 1. `config.toml` 선언 도구 목록 (버전 고정, 40개 이상)
시스템 전역을 오염시키지 않고 `mise`를 통해 안전하게 격리 설치됩니다(Python 기반 도구는 `pipx:` 백엔드가 내부적으로 `uv`를 사용).

**보안 & 정책 검증**
`trivy` · `conftest` · `cosign` · `trufflehog` · `shellcheck` · `shfmt` · `checkov` · `yamllint`

**컨테이너 이미지 공급망 (SBOM/취약점/레이어 분석)**
`syft` · `grype` · `dive`

**관측성 (Observability)**
`loki-logcli`

**IaC & 구성 관리**
`terraform` · `terragrunt` · `tflint` · `terraform-docs` · `infracost` · `ansible` · `ansible-lint`

**클라우드 CLI**
`awscli` · `azure-cli` · `aws-sam-cli` · `bicep` (Ubuntu glibc 호환을 위해 `github:` 백엔드로 고정 설치)

**Kubernetes & 컨테이너**
`kubectl` · `kubectx` · `k9s` · `helm` · `kustomize` · `kube-linter` · `hadolint` · `helm-docs` · `kyverno` · `pluto` · `promtool` · `yq`

**로컬 테스트**
`k3d` · `act`

**런타임**
`node` · `python` · `go`

**CLI 유틸리티**
`fzf` · `jq` · `bat` · `fd`

> 버전 고정 정보는 [`stow/mise/.config/mise/config.toml`](stow/mise/.config/mise/config.toml)에서 확인하십시오.

### 2. 생산성 단축어 (Alias)
자주 사용하는 인프라 명령어 단축 별칭(`k` -> `kubectl`, `tf` -> `terraform`, `ap` -> `ansible-playbook` 등)이 `stow/zsh/.zshrc`와 `stow/git/.gitconfig`에 구성되어 개발자 생산성을 극대화합니다.

### 3. 로컬 시크릿 파일 (`~/.zshrc.local`)
API 키, 토큰 등 민감 정보는 `.zshrc` 대신 `bootstrap.sh` 실행 후 자동 생성되는 `~/.zshrc.local`에 물리적으로 격리하여 보관하십시오. 이 파일은 저장소 트리 밖(홈 디렉토리)에 위치하므로 `.gitignore` 규칙에 기대지 않고 구조적으로 커밋 대상에서 벗어나며, 추적 대상인 `stow/zsh/.zshrc`는 이 파일을 `source`하기만 합니다.

```bash
# ~/.zshrc.local 예시
export GITHUB_TOKEN="ghp_..."
export AWS_ACCESS_KEY_ID="AKIA..."
export OPENAI_API_KEY="sk-..."
```

### 4. Vim 생산성 최적화 (`.vimrc`)
- **클립보드 연동:** `set clipboard=unnamedplus` — 브라우저, Slack과 양방향 복사/붙여넣기
- **YAML 최적화:** 탭 간격 2칸 고정 (`tabstop=2`, `shiftwidth=2`)

---

## 커스터마이징 및 확장

### 도구 추가 / 버전 변경
`stow/mise/.config/mise/config.toml` 파일에서 버전을 수정한 후 아래 커맨드를 실행하십시오.
```bash
# 사용 가능한 버전 목록 조회
mise ls-remote terraform

# config.toml 수정 후 일괄 설치
mise install

# 설치 결과 확인
mise ls
```

### 단축어 추가
`stow/zsh/.zshrc`에 alias를 추가한 후 `src`를 실행하면 즉시 적용됩니다.
```bash
echo "alias myalias='my-command'" >> ~/dotfiles/stow/zsh/.zshrc
src
```

### AI 룰셋 핫 리로드 (Zero-Config)
이미 셋업된 도메인 스킬의 세부 규칙을 수정하거나 확장할 경우, `bootstrap.sh` 재실행 없이 `contexts/` 하위의 마크다운 파일을 수정하는 즉시 실시간으로 에이전트에 반영됩니다.

> [!NOTE]
> `bootstrap.sh`(Ansible `ai_agent` 역할)는 `contexts/` 하위의 모든 도메인 디렉토리를 자동 순회합니다. 새 도메인 디렉토리를 추가하고 스크립트를 재실행하기만 하면, AI 에이전트의 글로벌 레지스트리(`~/.gemini/config/skills/`, `~/.claude/skills/`)에 스킬이 자동으로 등록되어 모든 로컬 환경에서 즉시 활용 가능해집니다.

---

## 보류 중인 후보 도구 (미적용)

지금 당장 필요하다고 확인된 게 아니라서 아직 `stow/mise/.config/mise/config.toml`에 넣지 않은 도구들입니다. 아래 조건에 실제로 부딪히면 그때 해당 도구만 추가하십시오.

| 도구 | 역할 | 추가할 조건 |
|---|---|---|
| `aws-vault` (또는 `granted`) | AWS SSO/역할별 자격증명 격리 | 여러 AWS 계정·역할을 자주 오가며 프로필 전환이 번거로워질 때 |
| `session-manager-plugin` | 베스천/SSH 없이 `aws ssm start-session`으로 EC2 접속 | 프라이빗 서브넷 EC2에 SSH로 직접 접속하는 일이 반복될 때 |
| `cloud-nuke` | 샌드박스 계정에 방치된 리소스 일괄 정리 | 테스트용으로 띄운 리소스를 지우는 걸 깜빡해 비용이 새기 시작할 때 |
| `stern` | K8s 파드 로그 다중 tail | `k9s`로는 부족할 만큼 로그 스트리밍/디버깅을 자주 할 때 |

> LocalStack은 후보에서 제외했습니다. IaC 검증은 이미 `terraform plan` + `checkov`/`conftest`로 커밋 전에 걸러지고, 실제 apply는 로컬 에뮬레이션보다 격리된 샌드박스 AWS 계정에서 하는 쪽이 현업에서 더 신뢰받는 방식이기 때문입니다.
