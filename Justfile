# Justfile
# 인프라 엔지니어 로컬 환경 관리용 통합 태스크 런너

set shell := ["bash", "-euo", "pipefail", "-c"]
export ANSIBLE_HOME := env_var('HOME') + "/.cache/ansible"
export ANSIBLE_CONFIG := "ansible/ansible.cfg"

# -----------------------------------------------------------------------------
# Setup & Provisioning
# -----------------------------------------------------------------------------

# 기본 설치 진입점 (권한 처리는 이번 실행에만 적용)
setup:
    bash bin/utils/run-setup.sh

# Ansible Dry-run
setup-dryrun:
    bash bin/utils/run-setup.sh --check

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

# [test 배경] 첫 실패 스킬에서 멈추면 뒤 스킬은 시도조차 안 되어, 무관한 스킬이 동시에
# 깨져 있어도 하나씩만 재커밋마다 드러난다. run-suite.sh가 이미 갖춘 병렬 실행 + "실패해도
# 끝까지 진행 후 요약" 로직을 그대로 재사용한다(Justfile에 순차 for 루프를 중복 구현하지 않음).
#
# just는 레시피 직전 "마지막" 주석 줄만 --list 설명으로 쓴다. 그래서 배경 설명을 위에 두고
# 한 줄 요약을 맨 아래에 붙인다(순서를 바꾸면 --list에 문장 조각이 잘려 나온다).
# 단위 테스트 전체 실행 (contexts/ 하위 모든 스킬 자동 탐색, 숨김 디렉토리 제외)
test:
    @echo "=> Running Unit Tests for all skills..."
    bash bin/hooks/run-suite.sh contexts/*/tests/run.sh

# [verify 배경] `check`/`test`는 각각 절반씩만 커버해 매번 둘 다 따로 요청해야 했다. 이
# 명령은 저장소 전체 스캔(pre-flight --all) + 전체 스킬 회귀 테스트 + prompt-lint 를 한 번에
# 묶어, AI를 거치지 않고 터미널에서 직접 돌려 토큰 소모 없이 검사 스크립트들의 정상 동작을 확인한다.
# 전체 회귀 검증 (check + test + prompt-lint 를 run-suite.sh 한 번으로 통합 실행)
verify:
    @echo "=> Running Full Regression Verification (check + test + prompt-lint)..."
    bash bin/hooks/run-suite.sh --pfc-args=--all

# -----------------------------------------------------------------------------
# Documentation
# -----------------------------------------------------------------------------

# [docs-index 배경] 셸은 리다이렉트를 명령 실행보다 먼저 처리하므로 `생성기 > contexts/INDEX.md`로
# 쓰면 생성기가 실패한 경우 INDEX.md가 빈 파일로 날아간 채 끝난다(실측 재현). 임시 파일에
# 먼저 받아 성공했을 때만 제자리로 옮긴다.
# contexts/INDEX.md 재생성 (SKILL.md 라우팅 테이블이 바뀐 뒤 실행)
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
