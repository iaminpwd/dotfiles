# Justfile
# 인프라 엔지니어 로컬 환경 관리용 통합 태스크 런너

set shell := ["bash", "-euo", "pipefail", "-c"]
export ANSIBLE_HOME := env_var('HOME') + "/.cache/ansible"
export ANSIBLE_CONFIG := "ansible/ansible.cfg"

# -----------------------------------------------------------------------------
# Setup & Provisioning
# -----------------------------------------------------------------------------

# 기본 설치 진입점 (Ansible Playbook 실행)
setup:
    @echo "=> Running dotfiles setup via Ansible..."
    ansible-playbook -i localhost, -c local ansible/site.yml

# Ansible Dry-run (실제 변경 없이 어떤 작업이 이루어질지 확인)
setup-dryrun:
    @echo "=> Running Ansible Dry-run..."
    ansible-playbook -i localhost, -c local ansible/site.yml --check

# -----------------------------------------------------------------------------
# Validation & Testing
# -----------------------------------------------------------------------------

# Pre-flight Check (전체 검증)
check:
    @echo "=> Running Pre-flight Checks..."
    bash bin/hooks/pre-flight-check.sh --all

# 스크립트 멱등성 검사 (개별 테스트)
check-idempotency file:
    @echo "=> Checking Idempotency for {{file}}..."
    bash bin/linters/idempotency-check.sh {{file}}

# 단위 테스트 전체 실행 (contexts/ 하위 모든 스킬 자동 탐색, .archive 제외)
# 첫 실패 스킬에서 멈추면 뒤 스킬은 시도조차 안 되어, 무관한 스킬이 동시에 깨져 있어도
# 하나씩만 재커밋마다 드러난다. run-suite.sh가 이미 갖춘 병렬 실행 + "실패해도 끝까지
# 진행 후 요약" 로직을 그대로 재사용한다(Justfile에 순차 for 루프를 중복 구현하지 않음).
test:
    @echo "=> Running Unit Tests for all skills..."
    bash bin/hooks/run-suite.sh contexts/*/tests/run.sh

# 전체 회귀 검증 (check + test + prompt-lint 를 run-suite.sh 한 번으로 통합 실행)
# `check`/`test`는 각각 절반씩만 커버해 매번 둘 다 따로 요청해야 했다. 이 명령은 저장소
# 전체 스캔(pre-flight --all) + 전체 스킬 회귀 테스트 + prompt-lint 를 한 번에 묶어,
# AI를 거치지 않고 터미널에서 직접 돌려 토큰 소모 없이 검사 스크립트들의 정상 동작을 확인한다.
verify:
    @echo "=> Running Full Regression Verification (check + test + prompt-lint)..."
    bash bin/hooks/run-suite.sh --pfc-args=--all

# -----------------------------------------------------------------------------
# Documentation
# -----------------------------------------------------------------------------

# contexts/INDEX.md 재생성 (SKILL.md 라우팅 테이블이 바뀐 뒤 실행)
docs-index:
    @echo "=> Regenerating contexts/INDEX.md..."
    bash bin/utils/generate-context-index.sh > contexts/INDEX.md

# -----------------------------------------------------------------------------
# Utility
# -----------------------------------------------------------------------------

# 사용 가능한 명령어 목록 출력
help:
    @just --list
