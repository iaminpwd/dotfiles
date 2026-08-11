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
# 정책(tty_tickets)은 티켓을 세션별로 분리하므로, bootstrap.sh 0단계가 이 계정에
# !tty_tickets(세션 무관 티켓 공유) 드롭인을 설치해뒀을 때만 ansible의 setsid 분리
# 세션에서도 그 티켓이 그대로 유효하다. `sudo -n true`로는 이걸 판단할 수 없다 —
# bootstrap.sh와 같은 세션(tty)에서 도는 한 !tty_tickets 여부와 무관하게 항상 참으로
# 나와서, 정작 필요한 setsid 분리 세션에서 티켓이 안 보이는 경우(예: GNU sudo가 아닌
# sudo-rs — visudo-rs가 아직 !tty_tickets/사용자별 Defaults를 지원하지 않아 드롭인 설치가
# 실패한 환경)를 걸러내지 못하고, 설치 도중 예고 없이 비밀번호를 다시 묻게 만든다.
# 그래서 "지금 티켓이 있는가" 대신 "그 드롭인이 실제로 설치돼 있는가"를 직접 확인한다:
# 있으면 티켓 공유가 보장되니 그대로 진행, 없으면 setsid 세션에서 반드시 막힐 것이므로
# --ask-become-pass로 맨 처음에 한 번에 물어보고 넘어간다(중간에 끊기지 않도록).
SUDOERS_DROPIN := "/etc/sudoers.d/99-dotfiles-" + `whoami` + "-shared-timestamp"

setup:
    @echo "=> Running dotfiles setup via Ansible..."
    if [ -f "{{SUDOERS_DROPIN}}" ]; then \
        ansible-playbook -i localhost, -c local ansible/site.yml; \
    else \
        ansible-playbook -i localhost, -c local ansible/site.yml --ask-become-pass; \
    fi

# Ansible Dry-run (실제 변경 없이 어떤 작업이 이루어질지 확인) — become 관련 이유는 setup 참고
setup-dryrun:
    @echo "=> Running Ansible Dry-run..."
    if [ -f "{{SUDOERS_DROPIN}}" ]; then \
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
# 셸은 리다이렉트를 명령 실행보다 먼저 처리하므로 `생성기 > contexts/INDEX.md`로 쓰면
# 생성기가 실패한 경우 INDEX.md가 빈 파일로 날아간 채 끝난다(실측 재현). 임시 파일에 먼저
# 받아 성공했을 때만 제자리로 옮긴다.
docs-index:
    @echo "=> Regenerating contexts/INDEX.md..."
    tmp=$(mktemp) && \
    if bash bin/utils/generate-context-index.sh > "$tmp"; then \
        mv "$tmp" contexts/INDEX.md; \
    else \
        rm -f "$tmp"; \
        echo "❌ 색인 생성 실패 — contexts/INDEX.md를 그대로 보존했습니다." >&2; \
        exit 1; \
    fi

# -----------------------------------------------------------------------------
# Utility
# -----------------------------------------------------------------------------

# 사용 가능한 명령어 목록 출력
help:
    @just --list
