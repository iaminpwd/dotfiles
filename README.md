# Cloud Infrastructure Engineer Dotfiles & AI Brain

클라우드 인프라 엔지니어(Principal DevOps/SRE)를 위한 **로컬 작업 환경**과 **AI 자율 주행 프롬프트**를 한 번에 구성하는 올인원(All-in-one) Dotfiles 레포지토리입니다.

단순히 터미널을 예쁘게 꾸미는 것을 넘어, **보안, 생산성, 그리고 AI(LLM)가 스스로 코드를 검증하고 테스트하는 파이프라인**을 로컬 환경에 구축하는 것을 목표로 합니다.

---

## 핵심 기능 (Core Features)

이 레포지토리의 진정한 가치는 단순 툴 설치가 아닌, 강력한 **"보안"**과 내장된 **"AI 아키텍트 가이드라인"**에 있습니다.

### 1. Zero-Trust 보안 및 격리
- **글로벌 `.gitignore` 강제 적용:** `terraform.tfstate`, `.env`, `.pem` 키가 깃허브에 유출되는 사고를 시스템 전역에서 원천 차단합니다.
- **도구의 격리:** 시스템 파이프라인 얽힘을 방지하기 위해 `mise`와 `pipx`를 활용하여 데브옵스 도구들을 샌드박스 형태로 격리하여 선언적으로 관리합니다.
- **시크릿 기록 방지:** 터미널 히스토리 설정(`HIST_IGNORE_SPACE`)을 통해 비밀번호나 API 키가 터미널 히스토리에 남는 것을 방지합니다.

### 2. AI 자율 주행 (Closed-Loop AI)
AI 에이전트가 코드를 짜고 끝나는 것이 아니라, "스스로 로컬에서 검증" 하도록 설계된 룰북이 내장되어 있습니다. 머릿속으로만 시뮬레이션하지 않고, AI가 **직접 터미널을 제어하여 `tflint`, `checkov`, `trufflehog`, `terraform plan`, `k3d`, `act` 등을 백그라운드에서 실행해 보고 에러를 혼자 고친 뒤 완벽한 코드를 반환**합니다.

### 3. Shadow AI Architecture (프롬프트 상속 및 격리)
로컬 개발 환경의 편의성과 팀 협업(Git)의 순수성을 완벽하게 분리하는 독자적인 아키텍처입니다.
- **프롬프트 자동 상속:** 사용자가 어떤 레포지토리에 진입(`cd`)하든, 눈에 보이지 않게 해당 워크스페이스의 공통 AI 룰북(`GEMINI.md`)과 차단선(`.aiexclude`)을 심볼릭 링크로 꽂아줍니다.
- **Git 커밋 완전 차단:** 자동 생성된 AI 컨텍스트 파일들은 전역 `.gitignore`에 의해 완벽하게 무시되어 원격 저장소나 팀원의 PC를 절대 오염시키지 않습니다 (Shadow AI).

### 4. 엔터프라이즈 AI 프롬프트 세트 내장 (`gemini/` 폴더)
> **Prompt Engineering Note:** 모든 프롬프트는 현업 최고 수준의 Principal SRE/DevOps 아키텍트 페르소나를 부여하며, 감정적 표현이 배제된 가장 엄격한 형태의 명령어조(`~하십시오`)와 명시적 제약 태그(`[MUST]`, `[NEVER]`)를 사용합니다.

- **`00-core.md` ~ `50-incident-response.md`**: 인프라 표준, IAM PoLP 준수 전략, FinOps, SRE 장애 대응(Blameless Post-Mortem) 가이드 포함.
- **K8s 마스터 가이드 (`k8s/`):** Ingress 표준화, GitOps 배포 전 편차(Drift) 검증, 혼합 인스턴스 오토스케일링 등 클라우드 네이티브 전 생애주기를 관장하는 폭포수 아키텍처.

---

## 작동 논리 및 아키텍처 (How it Works)

본 레포지토리의 AI 프롬프트 연동 시스템은 다음의 시간 순서로 완벽하게 자동화되어 작동합니다.

1. **프롬프트 빌드 (`setup.sh`):** 설치 스크립트를 실행하면 `~/dotfiles/gemini/` 내부의 모듈화된 원본 프롬프트(00~40)들이 `GEMINI.md` 단일 파일로 병합됩니다.
2. **워크스페이스 분리 및 글로벌 격리:** `setup.sh`가 통합 작업 공간(`~/workspace/aws`, `~/workspace/k8s`)을 생성하고, 안전하게 소스를 격리할 수 있도록 하위에 `src/` 폴더를 구성한 뒤 `GEMINI.md`를 심볼릭 링크합니다. 동시에 글로벌 `.gitignore`가 설정되어 보안선이 구축됩니다.
3. **레포지토리 진입 (Trigger):** 터미널에서 작업용 Git 레포지토리(예: `cd ~/workspace/aws/src/my-repo`)로 진입합니다.
4. **Zsh 훅 자동 상속 (Auto-Symlink):** 
   - Zsh에 심어진 백그라운드 훅(`chpwd`)이 이를 감지하고 해당 레포지토리 내부에 `.gemini/00-global-rules.md` 링크를 0.1초 만에 자동 생성합니다.
   - **주의사항:** 만약 `.zshrc`의 훅 코드를 처음 추가했거나 수정했다면, 열려있는 터미널에 `src` (`source ~/.zshrc`) 명령어를 입력하거나 새 터미널 창을 열어야 이 훅이 활성화됩니다!
5. **루트 컨텍스트 이중 차단:** 최상단의 `.aiexclude` 설정 덕분에 AI 에이전트는 원본 폴더와 복제본 폴더를 중복으로 읽지 않고 오직 최적화된 빌드 파일(`GEMINI.md`) 하나만 깔끔하게 인식합니다.

---

## 설치 가이드 (Installation)

초보자도 단 3번의 명령어로 환경을 구축할 수 있습니다.

> [!WARNING]
> **지원 OS**: Ubuntu / Debian 기반의 Linux (또는 Windows WSL2 Ubuntu 환경)
> Windows WSL 사용 시, 저장소를 반드시 `/mnt/c/`가 아닌 리눅스 네이티브 홈 디렉토리(`~/`) 하위에 클론해야 권한 문제가 발생하지 않습니다.

### Step 1. 저장소 클론
```bash
git clone https://github.com/iaminpwd/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

### Step 2. 자동 설치 스크립트 실행
```bash
./setup.sh
```
설치 스크립트는 필수 패키지 설치(`apt`), 도구 격리 설치(`pipx`), 파일 백업 및 심볼릭 링크 연결(`stow`), 프롬프트 병합 등을 일괄 수행합니다.

### Step 3. 터미널 재시작 및 훅 활성화
```bash
exec zsh
# (또는 기존 터미널에서 `src` 입력)
```

---

## 디렉토리 구조 (Folder Structure)

```text
~/dotfiles
├── .aiexclude       # 루트 컨텍스트 중복 방지 (원본 .gemini 소스 대신 빌드된 GEMINI.md만 읽도록 AI 강제)
├── .gemini/         # Dotfiles 레포지토리 자체 관리를 위한 메타 AI 프롬프트 (00~40)
├── GEMINI.md        # 병합된 Dotfiles 메인테이너 AI 프롬프트 지침 (setup.sh 자동 생성)
├── README.md        # 프로젝트 설명서 (본 문서)
├── setup.sh         # 전체 환경 자동 구성 스크립트
├── gemini/          # AI 에이전트 연동 자율 주행 가이드라인 (각 워크스페이스별)
│   ├── aiops/       # AIOps (운영 자동화 AI) 워크스페이스
│   │   ├── .aiexclude
│   │   └── .gemini/ # 전사적 장애 대응, 복원력 설계, FinOps, SRE 봇을 위한 아키텍처 프롬프트
│   ├── aws/         # AWS 인프라(Terraform) 워크스페이스 환경
│   │   ├── .aiexclude
│   │   ├── .gemini/
│   │   │   └── 00-core.md ~ 80-finops-optimization.md
│   │   └── GEMINI.md        # 결합된 최종 AI 프롬프트 지침 (자동 생성)
│   ├── k8s/         # Kubernetes & Cloud Native 워크스페이스
│   │   ├── .aiexclude
│   │   ├── .gemini/
│   │   │   └── 00-core.md ~ 70-platform-engineering-standard.md
│   │   └── GEMINI.md        # 결합된 최종 AI 프롬프트 지침
│   └── aws-azure/  # 멀티 클라우드(AWS+Azure) 워크스페이스
│       └── ...
├── git/             # Git 글로벌 설정 (.gitconfig) 및 전역 보안 (.gitignore_global)
├── mise/            # 인프라 도구 버전 관리 매니페스트 (.mise.toml)
├── vim/             # Vim 에디터 최적화 설정 (.vimrc)
└── zsh/             # Zsh 환경 및 단축어 설정 (.zshrc)
```

---

## 포함된 데브옵스 도구 및 단축어 (Tools & Aliases)

시스템 전역을 더럽히지 않고 `mise`와 `pipx`를 통해 안전하게 격리 설치되는 핵심 도구들입니다.

### 1. `mise` & `pipx` 관리 도구
- **IaC & 설정:** `terraform`, `ansible`, `terragrunt`, `tflint`, `terraform-docs`
- **보안 & 규정 준수:** `trivy`, `conftest`, `cosign`, `checkov`, `trufflehog`, `pre-commit`, `yamllint`
- **Kubernetes & 시뮬레이션:** `kubectl`, `kubectx`, `k9s`, `helm`, `helm-diff`, `kube-linter`, `k3d`, `act`
- **클라우드 CLI:** `awscli`, `azure-cli`

### 2. 주요 단축어 (`.zshrc` & `.gitconfig`)
- **Terraform:** `tf` (terraform), `tfi` (init), `tfp` (plan), `tfv` (validate), `tff` (fmt -recursive)
- **Kubernetes:** `k` (kubectl), `kx` (kubectx), `kn` (kubens), `kgp`/`kgs`/`kga`/`kdp`, `klogs`, `kex`, `knet` (트러블슈팅 컨테이너)
- **Docker & Helm:** `d` (docker), `dc` (docker-compose), `h` (helm)
- **Git:** `git lg` (히스토리 그래프), `git amend` (커밋 덮어쓰기), `st/co/cb/br/ci/cm/df`
- **시스템 편의성:** `src` (`source ~/.zshrc`), `ll` (`ls -alF`), `fd` (`fdfind`), `bat` (`batcat`), `c` (`code .`), `e` (`explorer.exe .`), `catcode` (인프라 코드 통째로 병합)

### 3. 로컬 시크릿 파일 (비밀번호 관리)
API 키나 토큰을 절대 `.zshrc`에 적지 마세요! 설치가 끝나면 `~/.zshrc.local` 파일이 생성됩니다. 이 파일은 GitHub에 올라가지 않는 여러분만의 로컬 비밀 금고입니다.

### 4. Vim 생산성 최적화 (`.vimrc`)
- **클립보드 연동:** `set clipboard=unnamedplus` (크롬/슬랙과 양방향 복사)
- **YAML 최적화:** 탭 간격 2칸 고정

---

## 커스터마이징 (Customization)

본인만의 환경으로 확장하고 싶다면 아래를 참고하세요.

- **도구 추가/버전 변경:** `mise/.mise.toml` 파일을 열어 버전을 바꾸고 터미널에서 `mise install`을 치면 끝입니다.
- **단축키 추가:** `zsh/.zshrc`에 단축키를 적고 터미널에 `src`를 치면 즉시 적용됩니다.
- **AI 룰 수정:** `gemini/aws/.gemini/` 폴더 안의 마크다운 파일을 수정한 뒤 `~/dotfiles/setup.sh`를 한 번 더 실행하시면 프롬프트 룰북이 자동 갱신됩니다.
