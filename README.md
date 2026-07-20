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
- **도구 완전 격리:** `mise`(런타임/CLI 도구)와 `pipx`(Python 기반 도구)를 통해 시스템 전역을 오염시키지 않고 선언적으로 버전을 관리합니다.
- **시크릿 히스토리 차단:** `HIST_IGNORE_SPACE` 설정으로 공백으로 시작하는 커맨드는 터미널 히스토리에 기록되지 않습니다.
- **로컬 시크릿 파일 분리:** API 키와 토큰은 Git이 추적하지 않는 `~/.zshrc.local`, `~/.gitconfig.local`에만 보관하도록 아키텍처를 강제합니다.

### 2. 고성능 사전 안전성 검증 파이프라인 (DX 최적화)
- **글로벌 pre-commit 훅 통합:** Git의 `core.hooksPath` 설정을 통해 `TruffleHog`와 `Trivy` 기반의 검증 파이프라인을 전역 연동합니다. 사용자의 모든 로컬 Git 저장소에서 시크릿 노출 및 설정 오류를 사전 방어하며, 개별 저장소마다 훅 파일을 복사해 넣는 번거로움을 완전히 제거했습니다.
- **24시간 DB 캐싱 마커:** `Trivy` 취약점 DB 업데이트 조회를 실행할 때, 저장소 루트의 로컬 마커 파일(`.trivy-db-update.timestamp`)을 참조합니다. 마지막 갱신으로부터 24시간 이내인 경우 원격 DB 업데이트 요청을 생략하는 `--skip-db-update` 플래그를 동적으로 결합하여, 커밋 지연을 20초에서 0.5초 수준으로 대폭 단축하고 쉘 프리징을 차단합니다.
- **디스크 I/O Pruning 스캔:** 쉘 스크립트 내부에서 `find` 명령 실행 시 캐시 및 메타데이터가 집중된 대규모 디렉토리(`.git/`, `.terraform/` 등)를 `-prune` 옵션으로 통과 경로에서 제외합니다. 이를 통해 무분별한 파일 전체 스캔으로 인한 디스크 I/O 부하를 예방하고, 파일명 공백 등으로 인한 파싱 예외는 NUL(`\0`) 구분값 기반 파서(`while read -r -d ''`)를 적용하여 안전하게 처리합니다.

### 3. SOTA 에이전트 워크플로우 및 프롬프트 아키텍처
로컬 프롬프트 아키텍처에는 Andrew Ng의 Agentic Workflow 디자인 패턴, ReAct/ToT 등의 추론 아키텍처, 그리고 벤더별 공식 가이드를 반영한 고급 프롬프트 설계가 반영되어 있습니다.
이에 대한 상세한 설계 철학 및 기술적 배경은 [Agentic Workflow & Prompt Architecture](contexts/README.md) 문서를 참고하십시오.

### 4. AI Customization Architecture (AI 스킬 동적 주입)
개발자의 로컬 환경 편의성과 팀 Git 협업 순수성을 완전히 분리하면서 최신 AI 에이전트의 Customization Elements(Skills & Rules)를 완벽히 지원하는 독자적 아키텍처입니다.
- **글로벌 룰 자동 주입:** `setup.sh` 실행 시 코어 룰(`base.AGENTS.md`)과 전역 무시 룰(`.base.aiexclude`)이 글로벌 Customizations Root(`~/.gemini/config/`)로 동적 주입됩니다.
- **도메인 스킬 글로벌 등록:** 환경별 특화 룰(`contexts/`)은 `~/.gemini/config/skills/<도메인>/SKILL.md` (Claude/Codex는 각각 `~/.claude/rules/`, `~/.codex/skills/`) 심볼릭 링크로 글로벌 스킬 등록됩니다. AI는 폴더 이동 없이도 작업 맥락을 파악하여 최적의 도메인 스킬(예: aws, azure)을 스스로 호출합니다.
- **프로젝트 루트 단독 매핑:** 워크스페이스 최상단 루트에 `AGENTS.md`와 `CLAUDE.md` 심볼릭 링크를 단독 생성 및 전역 이그노어하여, 로컬 저장소 오염 없이 제미나이와 클로드 에이전트가 100% 무인식 룰 로딩을 지원합니다.

### 5. 엔터프라이즈 AI 프롬프트 세트 내장 (`contexts/` 폴더)
워크스페이스별 특화 룰북과 메타 프롬프트에 적용된 구체적인 프롬프트 엔지니어링 기법(XML 격리, 계급제 우선순위 등)은 [Agentic Workflow & Prompt Architecture](contexts/README.md)에 상세히 명세되어 있습니다.

**워크스페이스별 특화 모듈:**

| 워크스페이스 | 상태 | 모듈 수 | 주요 커버리지 |
|---|---|---|---|
| **AWS** (`aws/`) | 🟢 **Production** | 12개 (`005`~`100`) | 제로트러스트 보안, 자격증명 격리, FinOps, IaC(Terraform), EKS, Serverless, RDS, Day2 운영 및 사고 대응 |
| **Azure** (`azure/`) | 🟢 **Production** | 12개 (`005`~`100`) | 제로트러스트 보안, 자격증명 격리, FinOps, IaC(Terraform), AKS, Serverless, Database, Day2 운영 및 사고 대응 |
| **K8s** (`k8s/`) | 🟡 **Draft** | 9개 (`010`~`100`) | GitOps/ArgoCD, mTLS, External Secrets, eBPF 런타임 보안, KEDA, 장애 사후 분석(RCA) |
| **Multi-Cloud** (`multi-cloud/`) | 🟡 **Draft** | 1개 (`010`) | AWS/Azure 하이브리드 통합, 네트워크 연동(VPN/DX), 이그레스 비용 자가 비판 및 동적 라우팅 |
| **AIOps** (`aiops/`) | 🟡 **Draft** | 8개 (`005`~`100`) | 자동화 플랜(005), 멱등성 및 장애 복원력, DORA 연동, 장애 사후 분석(RCA), LLM-as-a-Judge 가혹한 자가 비판 |
| **Dotfiles** (`dotfiles/`) | 🟢 **Production** | 8개 (`000`~`060`) | 인지 엔진, 셸 스크립팅 표준, 툴체인 관리, 보안, 메타/범용 프롬프팅, 트러블슈팅 |

---

## 설치 가이드

> [!WARNING]
> **지원 OS**: Ubuntu / Debian 기반 Linux (또는 Windows WSL2 Ubuntu 환경)
> WSL2 사용 시, 반드시 Linux 네이티브 홈 디렉토리(`~/`) 하위에 클론하십시오. `/mnt/c/` 경로에서 실행하면 권한 오류가 발생하며 스크립트가 즉시 종료됩니다.

### Step 1. 저장소 클론
```bash
git clone https://github.com/iaminpwd/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

### Step 2. 자동 설치 스크립트 실행
```bash
./setup.sh
```

스크립트는 다음 6단계를 순차적으로 실행합니다.

| 단계 | 작업 내용 |
|---|---|
| **[1/6]** 필수 패키지 설치 | `apt`로 git, zsh, stow, pipx, fd-find, dnsutils, tree 등 설치 |
| **[2/6]** Oh My Zsh 구성 | Oh My Zsh + `zsh-autosuggestions`, `zsh-syntax-highlighting` 플러그인 설치 |
| **[3/6]** Stow 심볼릭 링크 | 기존 설정 파일 백업 후, `zsh/vim/mise/git` 설정을 홈 디렉토리로 symlink |
| **[4/6]** mise 인프라 도구 설치 | `mise install`로 `mise.toml`에 선언된 40+ 데브옵스 도구 일괄 설치 |
| **[5/6]** AI 커스터마이징 구조 주입 | 글로벌 마스터 룰(`base.AGENTS.md`) 셋업 및 프로젝트 최상단 루트에 `AGENTS.md`/`CLAUDE.md` 단독 링킹을 통한 AI 무인식 룰 로딩 및 Git 트리 클린 아키텍처 |
| **[6/6]** 시크릿 보안 훅 | Trufflehog 전역 시크릿 스캔 및 `core.hooksPath` 기반 글로벌 훅 연동, 24시간 취약점 DB 스킵 캐싱 및 Pruning 최적화를 적용한 고속 사전 안전성 검증 |

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
ls -la ~/.zshrc ~/.gitconfig ~/.mise.toml

# AI 글로벌 룰 및 스킬 레지스트리 등록 확인
cat ~/.gemini/config/AGENTS.md | head -5
ls ~/.gemini/config/skills/
```

---

## 디렉토리 구조

```text
~/dotfiles
├── contexts/             # AI 컨텍스트 룰북 단일 진실 공급원 (SSOT)
│   ├── base.AGENTS.md         # 전 워크스페이스 공통 마스터 엔진 (SSOT)
│   ├── .base.aiexclude        # 글로벌 AI 오염 방지 전역 무시 룰 원본
│   ├── README.md              # 프롬프트 아키텍처 백과사전
│   ├── aws/              # AWS 인프라 워크스페이스 룰북 🟢 Production
│   ├── azure/            # Azure 인프라 워크스페이스 룰북 🟢 Production
│   ├── k8s/              # Kubernetes & Cloud Native 워크스페이스 🟡 Draft
│   ├── multi-cloud/      # 멀티 클라우드(하이브리드) 워크스페이스 라우터 🟡 Draft
│   ├── aiops/            # AIOps (운영 자동화) 워크스페이스 🟡 Draft
│   ├── pre-flight-check/ # 사전 안전성 검증 룰북 및 스크립트 🟡 Draft
│   ├── dotfiles/         # dotfiles 레포 자체 관리용 메타 프롬프트 🟢 Production
│
├── git/
│   ├── .gitconfig             # 글로벌 Git 설정 (alias, pull.rebase=true, hooksPath)
│   └── .gitignore_global      # 시스템 전역 Git 무시 규칙 (tfstate, .env 등)
│
├── mise/
│   └── .mise.toml        # 인프라 도구 버전 선언 매니페스트 (SSOT)
│
├── vim/
│   └── .vimrc            # Vim 설정 (클립보드 연동, YAML 2칸 탭)
│
├── zsh/
│   ├── .zshenv           # Zsh 환경변수 설정 (PATH 등 비대화형 세션 포함)
│   └── .zshrc            # Zsh 설정 (Oh My Zsh, 단축어)
│
├── .gitignore            # dotfiles 레포 자체 Git 무시 규칙
├── README.md             # 본 문서
└── setup.sh              # 전체 환경 자동 구성 스크립트 (set -euo pipefail)
```

---

## 작동 논리 및 아키텍처

### setup.sh 설치 파이프라인
![setup.sh Installation Pipeline](assets/setup-pipeline.png)

### GNU Stow 심볼릭 링크 구조
![GNU Stow Symlink Architecture](assets/stow-symlinks.png)

**글로벌 스킬 적용**
모든 도메인 스킬은 `~/.gemini/config/skills/`, `~/.claude/rules/`, `~/.codex/skills/` 심볼릭 링크 레지스트리를 통해 AI 에이전트에게 직접 라우팅되므로, **로컬 소스코드 저장소가 100% 깔끔하게 유지**됩니다.

### AI 컨텍스트 빌드 파이프라인
![AI Context Build Pipeline](assets/ai-context-pipeline.png)

### 전역 검증 파이프라인 및 고속 DX 튜닝 설계
개발 흐름의 지연을 막으면서 완벽한 보안/규약 통제를 실현하기 위해 `pre-flight-check.sh`에 다음 튜닝 기법을 적용했습니다.
- **시간 기반 DB 캐시(TTL)**: Trivy DB 원격 조회를 24시간 주기로 캐싱하여 커밋 대기 시간을 20초에서 0.5초 수준으로 대폭 단축했습니다.
- **디스크 I/O Pruning**: `.git/`, `.terraform/` 등 무거운 시스템 폴더 탐색을 `-prune`으로 차단하여 디스크 소모를 최소화했습니다.

---

## 포함된 도구 및 생산성 설정

### 1. `mise.toml` 선언 도구 목록 (버전 고정)
시스템 전역을 오염시키지 않고 `mise`와 `pipx`를 통해 안전하게 격리 설치됩니다.

**보안 & 정책 검증**
`trivy` · `conftest` · `cosign` · `trufflehog` · `checkov` · `pre-commit` · `yamllint` · `cfn-lint` · `hadolint`

**IaC & 구성 관리**
`terraform` · `terragrunt` · `tflint` · `terraform-docs` · `infracost` · `ansible` · `ansible-lint`

**클라우드 CLI**
`awscli` · `azure-cli` · `aws-sam-cli`

**Kubernetes & 컨테이너**
`kubectl` · `kubectx` · `k9s` · `docker-cli` · `helm` · `helm-docs` · `kustomize` · `kube-linter`

**로컬 테스트**
`k3d` · `act`

**런타임**
`node` · `python` · `go`

**CLI 유틸리티**
`fzf` · `jq` · `bat`

> 버전 고정 정보는 [`mise/.mise.toml`](mise/.mise.toml)에서 확인하십시오.

### 2. 생산성 단축어 (Alias)
자주 사용하는 인프라 명령어 단축 별칭(`k` -> `kubectl`, `tf` -> `terraform`, `ap` -> `ansible-playbook` 등)이 `zsh/.zshrc`와 `git/.gitconfig`에 구성되어 개발자 생산성을 극대화합니다.

### 3. 로컬 시크릿 파일 (`~/.zshrc.local`)
API 키, 토큰 등 민감 정보는 `.zshrc` 대신 `setup.sh` 실행 후 자동 생성되는 `~/.zshrc.local`에 물리적으로 격리하여 보관하십시오. 이 파일은 `.gitignore`에 의해 원격 저장소에 절대 커밋되지 않습니다.

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
`mise/.mise.toml` 파일에서 버전을 수정한 후 아래 커맨드를 실행하십시오.
```bash
# 사용 가능한 버전 목록 조회
mise ls-remote terraform

# mise.toml 수정 후 일괄 설치
mise install

# 설치 결과 확인
mise ls
```

### 단축어 추가
`zsh/.zshrc`에 alias를 추가한 후 `src`를 실행하면 즉시 적용됩니다.
```bash
echo "alias myalias='my-command'" >> ~/dotfiles/zsh/.zshrc
src
```

### AI 룰셋 핫 리로드 (Zero-Config)
이미 셋업된 도메인 스킬의 세부 규칙을 수정하거나 확장할 경우, `setup.sh` 재실행 없이 `contexts/` 하위의 마크다운 파일을 수정하는 즉시 실시간으로 에이전트에 반영됩니다.

> [!NOTE]
> `setup.sh`는 `contexts/` 하위의 모든 디렉토리를 자동 순회합니다. 새 도메인 디렉토리를 추가하고 스크립트를 재실행하기만 하면, AI 에이전트의 글로벌 레지스트리(`~/.gemini/config/skills/`, `~/.claude/rules/`, `~/.codex/skills/`)에 스킬이 자동으로 등록되어 모든 로컬 환경에서 즉시 활용 가능해집니다.
