---
name: dotfiles
description: |
  이 저장소의 bootstrap, Ansible, Stow, mise, shell 설정, hooks와 회귀 검증을 변경할 때 사용하는 로컬 스킬.
---
# dotfiles Skill

이 저장소의 로컬 지침이다. 글로벌 스킬로 등록하지 않으며 루트 AGENTS.md·CLAUDE.md가 이 파일에 연결된다.

## 저장소 구조와 실행 경로

- 설정 원본은 `stow/`, 초기 설치는 `bootstrap.sh`와 `ansible/`, 실행·훅 도구는 `bin/`, 지침·회귀 자산 원본은 `contexts/`다.
- 도구 버전과 mise 선언은 `stow/mise/.config/mise/config.toml`이 원본이다. 상세 계약은 `references/040-toolchain-management-standard.md`를 따른다.
- 자격 증명·SSH 키·로컬 시크릿은 저장소 밖에 두며, 상세 경계와 스캔 기준은 `references/050-dotfiles-security-standard.md`를 따른다.
- 변경 근거 기록이나 승인된 예외를 다룰 때만 `references/010-core.md`를 읽는다.

## 변경 계약

- 링크로 노출된 파일은 실제 원본을 확인한 뒤 수정한다. 사용자 파일을 일괄 덮어쓰거나 기존 링크 대상을 무조건 삭제하지 않는다.
- 배포 경로·등록·복사본을 바꾸는 작업은 `ansible/roles/ai_agent/tasks/main.yml` 등 실제 배포 코드를 확인하고, 단순 원본 내용 변경과 구분한다.
- 새 context reference를 추가·삭제·이름 변경하면 SKILL 라우팅/인용 호출부를 함께 갱신하고 `just docs-index`로 색인을 재생성한다.
- 셋업·파일 조작 변경은 fresh install과 재실행 멱등성을 고려한다. 기존 Alias·PATH·함수, OS·권한·선행 도구 조건과 충돌하지 않아야 한다.
- PATH/셸 오류는 현재 PATH, `command -v`, 실제 로드 순서를 먼저 확인한다. 원인 확인 없이 경로를 중복 추가하지 않는다.
- Stow 충돌은 기존 파일을 보존 가능한 백업 경로로 옮긴 뒤 링크를 재시도하고, 연결 후 symlink가 끊어지지 않았는지 확인한다.
- 디버그 추적(`bash -x`, `zsh -x`)은 로컬 시크릿을 출력할 수 있으므로 필요한 범위에만 사용한다.
- 복구는 이번 변경에 한정하고 사용자 변경을 보존한다. 배포 경로를 바꾼 경우에는 원본 롤백뿐 아니라 연결 복구 방법도 확인한다.

## 검증 계약

- 변경 파일 선별 검사: `bash bin/hooks/pre-flight-check.sh --changed`
- 변경 영역 회귀: `just check-changed`
- 전체 회귀: `just test`
- 전체 검증: `just verify`
- 프롬프트 변경: `bash bin/linters/prompt-lint.sh`
- context 라우팅 변경: `just docs-index`
- dotfiles 회귀 묶음은 `bash contexts/dotfiles/tests/run.sh`로 실행한다.
- tests·evals는 런타임 스킬에 배포되지 않는다. 원본 저장소에서 실행하고 종료 코드와 WARNING/SKIP을 확인한다.

## 사전 검증 실행 및 해석

- `bin/hooks/pre-flight-check.sh`는 기본적으로 staged 파일을 검사한다. `--changed`는 unstaged/untracked도 포함하고, `--all`은 전체 대상이다. 의도적 위반 fixture는 전역 대상에서 제외한다.
- `PFC_PROFILE=quick`은 가벼운 문법 검사, `stop`은 Ansible 검사 및 변경된 Terraform root의 fmt/validate/TFLint/Checkov 검사, `full`은 문법·보안 기본 검사다. full의 추가 Terraform/SAM/Helm/Kubernetes/Conftest/FinOps 정책은 `PFC_DOMAIN_CHECKS=1`을 명시해야 한다.
- 검사 종료 코드와 마지막 요약을 함께 확인한다. `[WARNING]`, `[SKIP]`, 도구 미설치는 검사 축소 가능성을 나타낸다. quick/stop 통과를 full/domain 통과로 보고하지 않는다.
- 실패 시 훅이나 검증기를 우회하지 말고 원인 수정 후 같은 대상·프로필로 재실행한다.

## 도메인별 검증 스크립트

- 다음 폴더는 글로벌 AI 스킬이 아닌 **테스트·실행 자산**이다. `SKILL.md`가 없어도 `just test`·`just verify`·CI에서 기존 `tests/run.sh`를 호출한다. Git/Stop 훅은 변경 범위별 필수 검사만 선택하며, 모든 도메인 테스트를 실행하지는 않는다.
- AWS: `contexts/aws/tests/run.sh` (tflint, Checkov, SAM).
- Kubernetes: `contexts/k8s/tests/run.sh` (kube-linter, promtool, Pluto, Kyverno, Helm, Conftest).
- 컨테이너: `contexts/containers/tests/run.sh` (hadolint, Trivy, 컨테이너 하드닝 게이트).
- 관측성: `contexts/observability/tests/run.sh` (PrometheusRule 및 알람 규칙 검증).
- AIOps: `contexts/aiops/tests/run.sh` (텔레메트리 시크릿 검사, 이상 임계치, PII 마스킹).
- Pre-flight: `contexts/pre-flight-check/tests/run.sh` (공용 검증 로직 회귀).
- 프롬프트: `contexts/prompt-architect/tests/run.sh` 및 `bash bin/linters/prompt-lint.sh` (규칙·참조·색인 검증). 라우팅 정답지는 `contexts/prompt-architect/evals/routing/run.sh --check-cases-only`로 확인하고, 유료 실측은 별도 요청 시에만 실행한다.
- 위 명령의 요구 도구가 없으면 일부 회귀 테스트가 실패할 수 있으므로 실패·미실행을 구분한다. 파괴적 클라우드/Kubernetes 작업은 대상 리소스와 계획을 먼저 검증한다.
