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

### 2. SOTA 에이전트 워크플로우 (Agentic Workflow 4대 원칙 내재화)
단순한 챗봇을 넘어, 최신 AI 연구소(OpenAI, Anthropic, Andrew Ng 백서)에서 권장하는 **자율 주행 에이전트 4대 원칙**이 프롬프트 아키텍처에 완벽히 구현되어 있습니다.
- **도구 사용 (Tool Use):** 머릿속으로만 시뮬레이션하지 않고, AI가 `run_command`를 통해 직접 터미널을 제어하여 `tflint`, `checkov`, `terraform plan`, `k3d` 등을 백그라운드에서 실행하고 검증합니다.
- **반성 및 자가 치유 (Reflection):** 코드 출력 전 의무적으로 `<self_critique>` 태그를 열어 멱등성과 보안 결함을 스스로 비판합니다. 에러 발생 시 최대 3번 혼자 고치고 실패하면 중단하는 Fail-Fast 서킷 브레이커가 동작합니다.
- **계획 수립 (Planning):** 복잡한 인프라 작업 지시 시 곧바로 코드를 쏟아내지 않습니다. 반드시 하위 작업으로 분할(Task Breakdown)하고 `implementation_plan.md` 사전 계획서를 통해 승인을 얻은 후 실행합니다.
- **전문성 락킹 (Persona/Multi-agent):** 15년 차 '수석 데브옵스 아키텍트'라는 가장 강력한 페르소나를 부여받아, 단순 조수 역할을 넘어 주도적으로 아키텍처를 설계하는 페어 프로그래밍 협업을 이룹니다.

### 3. Shadow AI Architecture (프롬프트 상속 및 격리)
로컬 개발 환경의 편의성과 팀 협업(Git)의 순수성을 완벽하게 분리하는 독자적인 아키텍처입니다.
- **프롬프트 자동 상속:** 사용자가 어떤 레포지토리에 진입(`cd`)하든, 눈에 보이지 않게 해당 워크스페이스의 공통 AI 룰북(`GEMINI.md`)과 차단선(`.aiexclude`)을 심볼릭 링크로 꽂아줍니다.
- **Git 커밋 완전 차단:** 자동 생성된 AI 컨텍스트 파일들은 전역 `.gitignore`에 의해 완벽하게 무시되어 원격 저장소나 팀원의 PC를 절대 오염시키지 않습니다 (Shadow AI).

### 4. 엔터프라이즈 AI 프롬프트 세트 내장 (`gemini/` 폴더)
> **Prompt Engineering Note:** 모든 프롬프트는 현업 최고 수준의 Principal SRE/DevOps 아키텍트 페르소나를 부여하며, 감정적 표현이 배제된 가장 엄격한 형태의 명령어조(`~하십시오`)와 명시적 제약 태그(`[MUST]`, `[NEVER]`)를 사용합니다.

- **에이전트 인지 구조 및 파싱 최적화 (AI-Friendly Cognitive Architecture):**
  - **다국어 최적화 (English Core Directive):** 제목과 설명은 한글로 작성하되, AI가 반드시 지켜야 하는 핵심 행동 강령(Blockquote `>`)은 영문 명령문(Imperative)으로 작성했습니다. 대형 언어 모델의 학습 데이터 구조를 활용하여 지시 수행률(Instruction Following)을 극대화한 백서 수준의 기법입니다.
  - **상태 기계(State-Machine) 트리거 로직:** 줄글 형태의 조건을 배제하고 `[Trigger: Validation Failed 3 times]`와 같은 명시적 상태 트리거를 도입했습니다. 이를 통해 AI의 무한 루프 에러를 방지하는 강력한 서킷 브레이커(Fail-Fast) 회로를 내장했습니다.
  - **시각적 어텐션 분리 (Action Badges):** `[MUST]`, `[PREFER]`, `[NEVER]` 뱃지를 문두에 배치하여 AI의 어텐션(Attention) 가중치를 즉각적으로 분배하고 환각(Hallucination)을 최소화합니다.
- **고급 프롬프트 엔지니어링 (Advanced Prompt Architecture) 적용:**
  - **XML 캡슐화 (Domain Isolation):** `aws`, `k8s` 등 각 도메인 규칙이 섞이는 할루시네이션(Bleeding)을 막기 위해 모든 마크다운을 `<aws_core_guidelines>` 등의 고유 XML 태그로 캡슐화했습니다.
  - **사고 과정 강제화 (Chain-of-Thought):** 파괴적 명령어 실행 전이나 장애 원인 분석 시, 즉시 행동하지 않고 `<thinking>` 태그 내에서 3-Why 기법과 파급 효과를 분석하도록 설계되었습니다.
  - **원칙 기반 퓨샷 프롬프팅 (Principle-Driven Few-Shot):** 각 워크스페이스의 마지막 모듈(`100-few-shot-examples.md` 등)에 Bad/Good 예시를 주입하여, 추상적인 규칙이 실제 터미널 도구 명령(`run_command`)으로 완벽하게 교정(Self-Correction)되도록 보장합니다.
  - **엔터프라이즈 마인드셋 락킹 (Enterprise Focus):** 모든 워크스페이스 프롬프트에 Zero-Trust 보안, 장애 복원력(Day-2/SRE), 비용 최적화(FinOps) 철학을 강제로 탑재하여 아키텍처 결함을 사전 차단합니다.

- **워크스페이스별 특화 모듈:**
  - **AWS (`aws/`):** 대규모 엔터프라이즈 환경을 가정한 AWS 전 생애주기 폭포수 아키텍처 (`000` ~ `110`)
    - `000-universal-core`: 수석 데브옵스 아키텍트 페르소나 및 핵심 행동 표준
    - `010-aws-core`: AWS 워크스페이스 핵심 행동 강령
    - `020-security-compliance`: 자격 증명(Secrets) 격리 및 컴플라이언스
    - `030-finops-optimization`: 비용 최적화 (FinOps)
    - `040-automation-scripting`: 셸 스크립트 및 자동화 표준
    - `050-iac-standard`: Terraform 프로비저닝 표준
    - `060-kubernetes-standard`: EKS 보안 및 클라우드 네이티브 표준
    - `070-serverless-standard`: Event-driven 및 비동기 아키텍처
    - `080-database-standard`: 데이터베이스 보호 및 보안
    - `090-day2-operations`: 운영 파이프라인 및 배포
    - `100-incident-response`: 장애 우회 조치 및 사후 분석
    - `110-few-shot-examples`: 지시 수행률 극대화를 위한 행동 예시
  - **K8s (`k8s/`):** GitOps(ArgoCD) 배포 편차(Drift) 검증, mTLS, External Secrets, eBPF 런타임 보안 (`000` ~ `090`)
  - **AIOps (`aiops/`):** Blameless Post-Mortem, SRE 에러 분석 워크플로우, SLI/SLO 지표 기반 진단 (`00` ~ `60`)

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
├── .gemini/         # Dotfiles 레포지토리 자체 관리를 위한 메타 AI 프롬프트 (000~050)
├── GEMINI.md        # 병합된 Dotfiles 메인테이너 AI 프롬프트 지침 (setup.sh 자동 생성)
├── README.md        # 프로젝트 설명서 (본 문서)
├── setup.sh         # 전체 환경 자동 구성 스크립트
├── gemini/          # AI 에이전트 연동 자율 주행 가이드라인 (각 워크스페이스별)
│   ├── aiops/       # AIOps (운영 자동화 AI) 워크스페이스
│   │   ├── .aiexclude
│   │   ├── .gemini/
│   │   │   └── 00-core.md ~ 60-few-shot-examples.md
│   │   └── GEMINI.md        # 결합된 최종 AI 프롬프트 지침
│   ├── aws/         # AWS 인프라(Terraform) 워크스페이스 환경
│   │   ├── .aiexclude
│   │   ├── .gemini/
│   │   │   └── 000-universal-core.md ~ 110-few-shot-examples.md
│   │   └── GEMINI.md        # 결합된 최종 AI 프롬프트 지침 (자동 생성)
│   └── k8s/         # Kubernetes & Cloud Native 워크스페이스
│       ├── .aiexclude
│       ├── .gemini/
│       │   └── 000-universal-core.md ~ 090-few-shot-examples.md
│       └── GEMINI.md        # 결합된 최종 AI 프롬프트 지침
├── git/             # Git 글로벌 설정 (.gitconfig) 및 전역 보안 (.gitignore_global)
├── mise/            # 인프라 도구 버전 관리 매니페스트 (.mise.toml)
├── vim/             # Vim 에디터 최적화 설정 (.vimrc)
└── zsh/             # Zsh 환경 및 단축어 설정 (.zshrc)
```

---

## 포함된 데브옵스 도구 및 단축어 (Tools & Aliases)

시스템 전역을 더럽히지 않고 `mise`와 `pipx`를 통해 안전하게 격리 설치되는 핵심 도구들입니다.

### 1. `mise` & `pipx` 관리 도구
- **IaC & 설정:** `terraform`, `ansible`, `terragrunt`, `tflint`, `terraform-docs`, `cfn-lint`, `ansible-lint`, `infracost`
- **보안 & 규정 준수:** `trivy`, `conftest`, `cosign`, `checkov`, `trufflehog`, `pre-commit`, `yamllint`
- **Kubernetes & 시뮬레이션:** `kubectl`, `kubectx`, `k9s`, `docker-cli`, `helm`, `helm-diff`, `helm-docs`, `kustomize`, `kube-linter`, `k3d`, `act`
- **클라우드 CLI:** `awscli`, `aws-sam-cli`, `azure-cli`
- **런타임 (Runtimes):** `python`, `node`, `go`

### 2. 주요 단축어 (`.zshrc` & `.gitconfig`)
- **Terraform:** `tf` (terraform), `tfi` (init), `tfp` (plan), `tfv` (validate), `tff` (fmt -recursive)
- **Kubernetes:** `k` (kubectl), `kx` (kubectx), `kn` (kubens), `kgp`/`kgs`/`kga`/`kdp`, `klogs`, `kex`, `knet` (트러블슈팅 컨테이너)
- **Docker & Helm:** `d` (docker), `dc` (docker-compose), `h` (helm)
- **Git:** `git lg` (히스토리 그래프), `git amend` (커밋 덮어쓰기), `st/co/cb/br/ci/cm/df`, `pull.rebase = true` (안전한 병합)
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
