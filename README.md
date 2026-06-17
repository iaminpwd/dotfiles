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

본 레포지토리의 핵심은 **"Shadow AI Architecture"**를 통해 개발자의 로컬 환경과 원격 Git 레포지토리를 철저히 분리하면서도, AI에게 완벽한 컨텍스트(Context)를 주입하는 것입니다. 이는 다음 4단계의 메커니즘을 거쳐 자동으로 구성됩니다.

### 1단계: 모듈화된 메타 프롬프트 병합 (Prompt Build)
거대한 단일 프롬프트 작성(Monolithic Prompting)을 지양하고, 관리의 복잡성을 낮추기 위해 생애주기 및 도메인별로 규칙을 분할하여 체계적인 폭포수(Waterfall) 구조를 확보합니다.
- `setup.sh` 스크립트 실행 시, `~/dotfiles/gemini/<env>/.gemini/` 하위에 번호순(예: `00-core.md`, `10-security.md`)으로 분할된 프롬프트 모듈들을 차례대로 읽어들입니다.
- 분할 관리된 이 모듈들을 하나로 합쳐서 환경별(예: AWS, K8s) `GEMINI.md`라는 단일 마스터 룰북 파일로 빌드(병합)합니다. 

### 2단계: 워크스페이스(Workspace) 동적 프로비저닝
각 환경의 코드가 섞이지 않도록 `setup.sh`가 `~/workspace/` 하위에 도메인별 작업 공간을 구성합니다.
- 예: `~/workspace/aws/`, `~/workspace/k8s/` 폴더가 자동 생성됩니다.
- 생성된 각 워크스페이스의 루트 경로에 1단계에서 빌드된 마스터 `GEMINI.md`와 AI 접근을 제어할 `.aiexclude` 파일이 심볼릭 링크(Symlink)로 연결됩니다.
- 실제 Git 프로젝트들이 위치할 안전 격리 구역인 `src/` 폴더(`~/workspace/<env>/src/`)를 별도로 생성합니다.

### 3단계: Zsh 훅 기반 자율 상속 (Auto-Symlink Hook)
개발자가 특정 작업을 위해 코드가 있는 디렉토리로 진입할 때 일어나는 마법입니다.
- 개발자가 터미널에서 `cd ~/workspace/aws/src/my-terraform-repo` 명령을 통해 Git 레포지토리 루트로 진입합니다.
- `.zshrc`에 등록된 Zsh 내장 훅(`chpwd`)이 디렉토리 이동 이벤트를 즉시 감지합니다.
- 현재 폴더가 Git 레포지토리(`.git` 폴더 존재)인지 확인한 후, 최대 4단계까지 부모 디렉토리를 탐색하여 부모의 `GEMINI.md` 마스터 룰북을 찾습니다.
- 마스터 룰북을 발견하면 현재 레포지토리 내부에 `.gemini/00-global-rules.md`라는 이름으로 심볼릭 링크를 자동 주입합니다.
- *결과적으로 AI는 해당 프로젝트를 열자마자 `00-global-rules.md`를 최상위 지침으로 인식하여 자율 주행의 기반을 다집니다.*

### 4단계: 컨텍스트 중복 차단 및 보안선 구축 (Context & Security Isolation)
AI가 불필요한 파일을 읽어 할루시네이션(Hallucination)을 일으키거나, AI 룰북이 협업 레포지토리에 커밋되는 것을 완벽히 차단합니다.
- **Git 오염 방지:** `setup.sh`가 초기 세팅 시 설치한 전역 `.gitignore_global` 규칙에 의해 `.gemini/` 폴더와 `GEMINI.md`는 철저히 무시됩니다. 동료의 PC나 원격 레포지토리에 절대 푸시되지 않습니다.
- **AI 컨텍스트 최적화 (`.aiexclude`):** 워크스페이스 루트에 주입된 `.aiexclude`가 파편화된 원본 모듈들이나 상위의 중복된 `GEMINI.md`를 읽지 못하게 차단합니다. AI 에이전트의 시야에는 오직 레포지토리 내부에 주입된 단 1개의 최적화된 마스터 룰북(`.gemini/00-global-rules.md`)만 들어오게 됩니다.

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
