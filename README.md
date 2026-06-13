# Cloud Infrastructure Engineer Dotfiles

클라우드 인프라 엔지니어를 위한 **통합 작업 환경** 및 **AI 브레인 연동**을 한 번에 구성하는 dotfiles 레포지토리입니다.

## 주요 기능

- **자동화된 환경 설정**: `stow`를 활용하여 zsh, vim, mise 등의 설정을 충돌 없이 홈 디렉토리에 심볼릭 링크로 연결하여 관리합니다.
- **인프라 도구 일괄 설치 (mise)**: `terraform`, `kubectl`, `ansible`, `awscli`, `k3d`, `node`, `k9s` 등 필수 인프라/데브옵스 도구들을 `mise`를 통해 선언적으로 설치하고 버전을 관리합니다.
- **Zsh & 플러그인**: Oh My Zsh와 필수 플러그인(`git`, `kubectl`, `terraform`, `zsh-autosuggestions`, `zsh-syntax-highlighting`)을 활성화하여 터미널 생산성을 극대화합니다.
- **AI 에이전트 연동 (Gemini Brain)**: `gemini` 폴더 내에 정의된 AI 브레인 가이드라인(`.md` 파편 파일들)을 동적으로 병합하여 `GEMINI.md`를 구성하고, 관련 작업용 워크스페이스(예: `~/cloud`)에 자동으로 심볼릭 링크를 생성하여 AI 컨텍스트를 주입합니다.

## 상세 설정 내용

### 1. Zsh 및 단축어 설정 (`zsh/.zshrc`)
Oh My Zsh의 `robbyrussell` 테마를 기반으로, 인프라 작업에 필수적인 단축어(Alias) 및 스크립트가 포함되어 있습니다.
- **인프라/K8s 단축어**: 
  - `k` (`kubectl`), `tf` (`terraform`)
  - `kgp` (get pod), `kgs` (get svc), `kga` (get all)
  - `knet` (netshoot 컨테이너를 이용한 네트워크 트러블슈팅 Pod 즉시 실행)
- **유틸리티 단축어**:
  - `ll` (`ls -alF`), `e` (`explorer.exe .` - WSL용), `c` (`code .` - VSCode 연동)
  - `src` (`source ~/.zshrc` - 쉘 설정 즉시 새로고침)
  - `catcode` (AI 프롬프트 컨텍스트용 단축어: `fdfind`를 사용해 하위 경로의 모든 코드(tf, yaml, py, sh 등)를 하나의 텍스트 파일(`all_code.txt`)로 병합하여 추출)
- **기타**: `mise` 환경 자동 활성화 및 `~/.local/bin` PATH 추가.

### 2. Vim 설정 (`vim/.vimrc`)
서버 환경에서의 인프라 코드 편집을 위해 직관성과 편의성을 높인 기본 설정이 적용됩니다.
- 줄 번호 표시 (`set number`)
- 자동 및 스마트 들여쓰기 (`set ai`, `set si`)
- 탭을 스페이스 2칸으로 변환 (`set ts=2`, `set sw=2`, `set expandtab`)
- 문법 강조 활성화 (`syntax on`)

### 3. 포함된 주요 도구 (`mise/.mise.toml`)

**IaC & Configuration Management**
- `terraform` (1.5.7)
- `ansible` (9.5.1)
- `terragrunt` (1.0.8)
- `tflint` (0.63.1)

**Cloud Services**
- `awscli` (2.15.30)

**Kubernetes & Containers**
- `kubectl` (1.30.1)
- `kubectx` (0.9.5)
- `k9s` (0.32.4)
- `docker-cli` (29.5.3)
- `helm` (4.2.1)

**Local Testing & Mocking**
- `localstack` (3.4.0)
- `k3d` (5.6.3)
- `act` (0.2.62)

**Runtimes / Programming Languages**
- `node` (20.12.2)
- `python` (3.14.6)

### 4. AI 에이전트 지침 및 프롬프트 컨텍스트 (`gemini/cloud/.gemini/`)
이 dotfiles는 단순 툴 설치를 넘어, AI 에이전트가 인프라 코드를 작성하거나 리뷰할 때 엄격히 준수하도록 설계된 **DevOps 아키텍처 행동 강령**을 파일 형태로 내장하고 있습니다.
- **00/10 (Core & Behavior)**: 수석 데브옵스 아키텍트 페르소나 부여, 환각(Hallucination) 엄격 금지, 에러 시 자율 복구(Self-Correction) 및 근거/원인 기반 트러블슈팅 원칙, 레포지토리 외부 산출물(Artifact) 자동 생성 규칙.
- **20 (Security & Compliance)**: GitOps(ArgoCD) 배포 지향, 자격 증명 하드코딩 영구 차단(Secrets Manager 활용), IAM 최소 권한 원칙(PoLP), 퍼블릭 접근 차단 등 보안/컴플라이언스 표준.
- **30 (IaC Standard)**: Terraform(인프라 프로비저닝)과 Ansible(OS/App 구성)의 엄격한 역할 분리, 로컬 State 금지(S3/DynamoDB 강제), 동적 인벤토리 사용 표준.
- **40 (Code Review)**: TFLint, Checkov 등 정적 분석 도구 기준 통과 여부 검토, CI 파이프라인(GitHub Actions) 연동 및 사전 검증(Dry-run, Terratest) 워크플로우 제안 기준.
- **`.aiexclude` (컨텍스트 최적화 및 `.gitignore` 템플릿)**: AI의 토큰 낭비 및 컨텍스트 오염을 막기 위한 전역 필터(`node_modules`, 대용량 로그, 민감한 키 파일 등 차단)이며, 파일 하단에는 **엔터프라이즈 모노레포 환경을 위한 `.gitignore` 권장 설정**이 백업 가이드로 내장되어 있어 즉시 활용 가능합니다.

## 사전 요구 사항 (Prerequisites)

- **OS**: Ubuntu / Debian 기반의 Linux (또는 WSL2 Ubuntu 환경)
  - 내부적으로 `apt` 패키지 매니저를 사용합니다.
- **권한**: 패키지 설치 및 쉘 변경을 위한 `sudo` 관리자 권한이 필요합니다.

## 설치 및 적용 방법

> **주의**: WSL(Windows Subsystem for Linux) 환경을 사용하는 경우 `/mnt/c/`와 같은 윈도우 마운트 경로가 아닌, 반드시 리눅스 네이티브 경로(예: `~/dotfiles`)에 레포지토리가 위치해야 합니다.

1. 레포지토리를 홈 디렉토리 하위의 `dotfiles` 폴더로 클론합니다.
   ```bash
   git clone <이_레포지토리_주소> ~/dotfiles
   cd ~/dotfiles
   ```

2. 세팅 스크립트를 실행합니다. (기존 설정 파일은 `.backup` 확장자로 자동 백업됩니다)
   ```bash
   ./setup.sh
   ```

3. 스크립트 실행이 완료되면 터미널을 닫았다 다시 열거나, 아래 명령어로 쉘을 다시 로드하여 변경 사항을 적용합니다.
   ```bash
   exec zsh
   ```

## 디렉토리 구조

```text
~/dotfiles
├── LICENSE          # 프로젝트 라이선스 파일
├── README.md        # 프로젝트 설명서
├── gemini/          # AI 에이전트(Gemini) 연동 가이드라인
│   └── cloud/       # 'cloud' 워크스페이스 환경
│       ├── .aiexclude       # AI 컨텍스트 주입 시 제외할 패턴 목록
│       ├── .gemini/         # 모듈화된 도메인별 AI 지침 (setup.sh에 의해 결합됨)
│       │   ├── 00-core.md
│       │   ├── 10-agent-behavior.md
│       │   ├── 20-security-compliance.md
│       │   ├── 30-iac-standard.md
│       │   └── 40-code-review.md
│       └── GEMINI.md        # 결합된 최종 AI 프롬프트 지침 (자동 생성)
├── mise/            # .mise.toml (인프라 도구 버전 관리 매니페스트)
├── vim/             # .vimrc (Vim 설정 파일)
├── zsh/             # .zshrc (Zsh 단축어 및 환경 변수 설정 파일)
└── setup.sh         # 환경 자동 구성 스크립트
```

## 스크립트 작동 흐름 (`setup.sh`)

1. 시스템 필수 패키지 및 터미널 생산성 유틸리티(`git`, `curl`, `wget`, `unzip`, `zsh`, `fzf`, `jq`, `stow`, `pipx`, `python3-venv`, `fd-find` 등)를 일괄 설치하고, Oh My Zsh 및 커스텀 플러그인들을 Github에서 클론하여 초기 세팅을 진행합니다.
2. 기존 설정 파일(`.zshrc`, `.vimrc`, `.mise.toml`)을 백업 후 삭제합니다.
3. GNU Stow를 사용해 `zsh`, `vim`, `mise` 디렉토리를 홈 디렉토리(`~`)로 맵핑(Symlink)합니다.
4. `mise`를 설치 및 환경을 신뢰(`mise trust`)하고, 설정된 인프라 툴체인 버전을 일괄 다운로드 및 활성화합니다.
5. `gemini/` 하위 폴더들을 스캔하여, 각 환경별(예: `cloud`)로 조각난 마크다운들을 결합해 `GEMINI.md`를 생성하고, 홈 디렉토리에 해당 작업 공간(예: `~/cloud/src` 하위 폴더 포함)을 구성한 뒤, `GEMINI.md` 가이드라인과 `.aiexclude` 파일(존재 시)을 동적으로 심볼릭 링크합니다.
6. 마지막으로 현재 사용자의 기본 쉘(Default Shell)을 `zsh`로 자동 변경합니다.

## 사용자 정의 (Customization) 및 유지보수

본인만의 환경으로 확장하고 관리하려면 다음 가이드를 참고하세요.

- **인프라 도구 및 버전 변경**: `mise/.mise.toml`을 열어 원하는 도구(예: `python`, `go` 등)를 추가/수정한 뒤, 터미널에서 `mise install`을 실행하세요.
- **단축어(Alias) 추가**: `zsh/.zshrc` 하단에 단축어를 추가한 후 터미널에서 `src`를 입력하면 설정이 즉시 새로고침됩니다.
- **AI 브레인 가이드라인 확장**: `gemini/cloud/.gemini/` 폴더 내에 새로운 지침(`.md`) 파일을 추가하고 `./setup.sh`를 다시 실행하면, 컨텍스트가 `GEMINI.md`로 자동 병합 및 갱신됩니다.