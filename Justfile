# Justfile
# 인프라 엔지니어 로컬 환경 관리용 통합 태스크 런너

set shell := ["bash", "-c"]
export ANSIBLE_HOME := env_var('HOME') + "/.cache/ansible"

# -----------------------------------------------------------------------------
# Setup & Provisioning
# -----------------------------------------------------------------------------

# 기본 설치 진입점 (Ansible Playbook 실행)
setup:
    @echo "=> Running dotfiles setup via Ansible..."
    ansible-playbook -i localhost, -c local ansible/site.yml -K

# Ansible Dry-run (실제 변경 없이 어떤 작업이 이루어질지 확인)
setup-dryrun:
    @echo "=> Running Ansible Dry-run..."
    ansible-playbook -i localhost, -c local ansible/site.yml -K --check

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

# 단위 테스트 전체 실행
test:
    @echo "=> Running Unit Tests..."
    bash contexts/k8s/tests/run.sh

# -----------------------------------------------------------------------------
# Utility
# -----------------------------------------------------------------------------

# 사용 가능한 명령어 목록 출력
help:
    @just --list
