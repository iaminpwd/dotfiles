# Justfile
# 인프라 엔지니어 로컬 환경 관리용 통합 태스크 런너

set shell := ["bash", "-euo", "pipefail", "-c"]
export ANSIBLE_HOME := env_var('HOME') + "/.cache/ansible"
export ANSIBLE_CONFIG := "ansible/ansible.cfg"

# -----------------------------------------------------------------------------
# Setup & Provisioning
# -----------------------------------------------------------------------------

# 기본 설치 진입점 (Ansible Playbook 실행)
# ansible-core 2.19부터 become(sudo) 워커 프로세스를 setsid()로 부모 TTY와 분리된
# 별도 세션에서 실행한다(ansible/ansible#86149, #85536 — 의도된 사양 변경). sudo 기본
# 정책(tty_tickets)은 티켓을 세션별로 분리하지만, bootstrap.sh 0단계에서 이 계정에
# !tty_tickets(세션 무관 티켓 공유)를 미리 설정해두므로 sudo -n true 판정이 ansible의
# setsid 분리 세션에도 그대로 유효하다. 그 설정이 안 된 채로(예: bootstrap.sh를 거치지
# 않고 just setup만 단독 실행) 티켓이 없으면 --ask-become-pass로 최초 1회 직접 물어본다.
setup:
    @echo "=> Running dotfiles setup via Ansible..."
    if sudo -n true 2>/dev/null; then \
        ansible-playbook -i localhost, -c local ansible/site.yml; \
    else \
        ansible-playbook -i localhost, -c local ansible/site.yml --ask-become-pass; \
    fi

# Ansible Dry-run (실제 변경 없이 어떤 작업이 이루어질지 확인) — become 관련 이유는 setup 참고
setup-dryrun:
    @echo "=> Running Ansible Dry-run..."
    if sudo -n true 2>/dev/null; then \
        ansible-playbook -i localhost, -c local ansible/site.yml --check; \
    else \
        ansible-playbook -i localhost, -c local ansible/site.yml --check --ask-become-pass; \
    fi

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
