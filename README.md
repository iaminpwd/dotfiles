# Cloud Infrastructure Engineer Dotfiles & AI Brain

클라우드 인프라 엔지니어(Principal DevOps/SRE)를 위한 **로컬 작업 환경**과 **AI 자율 주행 프롬프트**를 한 번에 구성하는 올인원(All-in-one) Dotfiles 레포지토리입니다.

단순히 터미널을 예쁘게 꾸미는 것을 넘어, **보안, 생산성, 그리고 AI(LLM)가 스스로 코드를 검증하고 테스트하는 파이프라인**을 로컬 환경에 구축하는 것을 목표로 합니다.

---

## 핵심 철학 (Why this dotfiles?)

1. **보안 최우선 (Security First):** `terraform.tfstate`, `.env`, `.pem` 키가 깃허브에 유출되는 사고를 막기 위한 전역(Global) `.gitignore` 강제 적용 및 터미널 시크릿 타이핑 기록 방지.
2. **도구의 격리 및 선언적 관리:** `apt` 패키지의 얽힘을 방지하기 위해 `mise`와 `pipx`를 활용하여 데브옵스 도구들의 버전을 선언적으로 관리.
3. **AI 자율 주행 (Closed-Loop AI):** AI 에이전트가 코드를 짜고 끝나는 것이 아니라, 로컬에 설치된 `tflint`, `checkov`, `terraform plan`, `act`, `k3d` 등을 **스스로 백그라운드에서 실행해 보고(Dry-run) 에러를 스스로 고친 뒤 완벽한 코드를 반환**하도록 설계된 프롬프트 세트 내장.

---

## 포함된 데브옵스 도구 모음 (`mise` & `pipx`)

시스템 전역을 더럽히지 않고 `mise`와 `pipx`를 통해 안전하게 격리 설치되는 핵심 도구들입니다.

### 1. `mise` (버전 매니저) 관리 도구
- **IaC (인프라 프로비저닝):** `terraform`, `ansible`, `terragrunt`, `tflint`
- **보안 및 규정 준수:** `trivy` (컨테이너/IaC 취약점 스캐너), `conftest` (OPA 정책 검증)
- **Kubernetes & 컨테이너:** `kubectl`, `kubectx`, `k9s`, `helm`, `docker-cli`
- **클라우드 CLI:** `awscli`
- **로컬 시뮬레이션 (Testing):** `k3d` (로컬 K8s 클러스터), `act` (로컬 GitHub Actions 실행기)
- **런타임 언어:** `node`, `python`

### 2. `pipx` & 커스텀 바이너리 도구
- **보안 스캐닝:** `checkov` (IaC 취약점 정적 분석), `trufflehog` (하드코딩된 시크릿 검출)
- **Git Hook & 린팅:** `pre-commit`, `yamllint`

---

## 사용 가이드 및 단축어 (Aliases)

작업 효율을 높여주는 필수 단축어와 유틸리티 설정입니다.

### 1. ZSH 주요 단축어 (`.zshrc`)
- **Terraform:**
  - `tf` (terraform), `tfi` (init), `tfp` (plan), `tfa` (apply), `tfd` (destroy)
  - `tff` (`terraform fmt -recursive`): 코드 포맷 자동 정렬
  - `tfv` (`terraform validate`): 문법 검사
- **Kubernetes:**
  - `k` (kubectl), `kx` (kubectx - 클러스터 전환), `kn` (kubens - 네임스페이스 전환)
  - `kgp` (get pod), `kgs` (get svc), `kga` (get all)
  - `kex` (`kubectl exec -i -t`): 파드 접속
  - `klogs` (`kubectl logs -f`): 로그 실시간 추적
  - `knet`: 트러블슈팅용 netshoot 컨테이너 즉시 실행
- **Docker & Helm:** `d` (docker), `dc` (docker-compose), `h` (helm)
- **AI 프롬프트용:** `catcode` (현재 폴더 하위의 모든 인프라 코드를 하나의 `all_code.txt`로 병합)
- **시스템:** `src` (`source ~/.zshrc`), `ll` (`ls -alF`)

### 2. Git 단축어 및 보안 (`.gitconfig`)
- **보안 1순위 글로벌 `.gitignore`:** `terraform.tfstate`, `.env`, `.pem` 키 파일 시스템 전역 커밋 차단.
- **단축어:**
  - `git lg`: 직관적이고 아름다운 커밋 히스토리 그래프 출력.
  - `git amend` (`commit --amend --no-edit`): 직전 커밋에 오타를 빠르게 덮어쓰기.
  - `st` (status), `co` (checkout), `cb` (checkout -b), `br` (branch), `ci` (commit)

### 3. 로컬 시크릿 파일 (비밀번호 관리)
API 키나 토큰을 절대 `.zshrc`에 적지 마세요!
설치가 끝나면 `~/.zshrc.local` 파일이 생성되어 있습니다. 이 파일은 GitHub에 올라가지 않는 여러분만의 로컬 비밀 금고입니다. 
GitHub Token, OpenAI API Key, 테라폼 민감 변수(`TF_VAR_xxx`) 등은 모두 `~/.zshrc.local` 안에 `export TOKEN="..."` 형태로 선언해 두시면 터미널 시작 시 자동으로 안전하게 로드됩니다. (단, AWS 인증은 `aws configure`나 `aws sso login`을 사용하는 것이 표준이므로 여기에 적지 마세요.)

### 4. Vim 생산성 최적화 (`.vimrc`)
- **시스템 클립보드 연동 (`set clipboard=unnamedplus`):** 터미널 밖의 크롬/슬랙과 양방향 복사/붙여넣기 완벽 지원.
- **YAML 최적화:** 탭 간격 2칸 고정 (`set ts=2 sts=2 sw=2 expandtab`).
- **가이드라인:** 80자 옅은 세로줄 표시 (`set colorcolumn=80`).

---

## AI 에이전트 연동 (Gemini Brain)

이 레포지토리의 진정한 가치는 `gemini/` 폴더에 내장된 **AI 아키텍트 가이드라인**입니다. AI 에이전트는 이 룰북을 바탕으로 코드를 작성하고 "스스로 로컬에서 검증"합니다.

- **`00-core.md` (자율 검증 강제):** 코드를 작성하면 AI가 무조건 터미널에서 `terraform validate`를 백그라운드로 돌려 무결성을 1차 교정합니다. 단, 전체 디렉토리 대상 `terraform fmt`는 금지하여 의도치 않은 파일 수정을 막습니다. (ClickOps 절대 금지)
- **`10-iac-standard.md` (아키텍처 표준):** Terraform은 프로비저닝, Ansible은 OS 구성으로 엄격히 분리합니다. `ansible-playbook --syntax-check` 및 `conftest`를 통한 로컬 정책 검증을 수행합니다.
- **`20-security-compliance.md` (보안 및 권한):** IAM 최소 권한 원칙(PoLP) 준수, OIDC 기반 인증 설계, 그리고 터미널의 `trivy`를 호출하여 컨테이너/IaC 취약점을 스스로 스캔합니다.
- **`30-day2-operations.md` (운영 및 FinOps):** GitOps 선언적 배포, 리소스 생성 전 비용 최적화(Cost Impact) 분석, 무중단 DB 마이그레이션(Expand & Contract) 전략을 수립합니다.
- **`40-code-review.md` (자율 시뮬레이션 검증):** 핵심적인 프롬프트입니다. 머릿속으로만 시뮬레이션하지 않고, AI가 **직접 터미널을 제어하여 `tflint`, `checkov`, `trufflehog`, `terraform plan(Dry-run)`, `k3d(로컬 클러스터)`, `act(로컬 CI/CD)`를 실행**합니다. 에러 시 사용자에게 묻지 않고 혼자 로그를 읽어 수정(Self-Correction)한 뒤 완벽한 코드를 반환합니다.
- **`50-incident-response.md` (SRE 장애 대응):** 사용자가 장애 로그를 던지면, 1단계로 서비스 복구를 위한 '임시 우회 조치(Mitigation)'를 최우선으로 제안합니다. 이후 2단계로 근본 원인(RCA)을 분석하고, 마지막에 항상 **Blameless Post-Mortem(사후 분석 양식)**을 작성하여 재발 방지책을 구조화합니다.

---

## 디렉토리 구조 (Folder Structure)

```text
~/dotfiles
├── README.md        # 프로젝트 설명서 (본 문서)
├── setup.sh         # 전체 환경 자동 구성 스크립트
├── gemini/          # AI 에이전트(Gemini) 연동 자율 주행 가이드라인
│   ├── aws/         # AWS 워크스페이스 환경
│   │   ├── .aiexclude
│   │   ├── .gemini/
│   │   │   ├── 00-core.md
│   │   │   ├── 10-iac-standard.md
│   │   │   ├── 20-security-compliance.md
│   │   │   ├── 30-day2-operations.md
│   │   │   ├── 40-code-review.md
│   │   │   └── 50-incident-response.md
│   │   └── GEMINI.md        # 결합된 최종 AI 프롬프트 지침 (자동 생성)
│   └── aws-azure/  # 멀티 클라우드(AWS+Azure) 워크스페이스
│       └── ...
├── git/             # Git 글로벌 설정 (.gitconfig) 및 전역 보안 (.gitignore_global)
├── mise/            # 인프라 도구 버전 관리 매니페스트 (.mise.toml)
├── vim/             # Vim 에디터 최적화 설정 (.vimrc)
└── zsh/             # Zsh 환경 및 단축어 설정 (.zshrc)
```

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
설치 스크립트는 다음 작업을 자동으로 수행합니다:
1. `apt` 필수 패키지 설치 (`zsh`, `curl`, `pipx`, `stow` 등)
2. `pipx`와 `curl`을 이용한 보안 도구(`checkov`, `trufflehog` 등) 격리 설치
3. 기존 홈 디렉토리의 설정 파일들(`.zshrc` 등)을 `.backup`으로 안전하게 백업
4. `stow`를 이용해 dotfiles의 설정들을 홈 디렉토리에 심볼릭 링크로 연결
5. `mise` 패키지 매니저를 설치하고 `.mise.toml`에 명시된 테라폼, K8s 툴들을 한 번에 다운로드
6. AI 프롬프트(`.gemini`)를 결합하여 워크스페이스를 생성
7. **(사용자 입력)** Git 커밋에 사용할 이름(Name)과 이메일(Email)을 묻고, 안전한 로컬 파일에 분리 저장

### Step 3. 쉘 재시작 및 적용
```bash
exec zsh
```

---

## 커스터마이징 및 유지보수

본인만의 환경으로 확장하고 싶다면 아래를 참고하세요.

- **도구 추가/버전 변경:** `mise/.mise.toml` 파일을 열어 버전을 바꾸고 터미널에서 `mise install`을 치면 끝입니다.
- **단축키 추가:** `zsh/.zshrc`에 단축키를 적고 터미널에 `src`를 치면 즉시 적용됩니다.
- **AI 룰 수정:** `gemini/aws/.gemini/` 폴더 안의 마크다운 파일을 수정한 뒤 `~/dotfiles/setup.sh`를 한 번 더 실행하시면 프롬프트 룰북이 자동 갱신됩니다.
