#!/usr/bin/env bash
# setup.sh 멱등성 회귀 테스트
#
# setup.sh 는 $HOME 에 심볼릭 링크를 걸고 기존 설정 파일을 백업 후 삭제하며 에이전트
# 전역 설정(JSON)을 병합한다. 실패 시 피해가 가장 큰 스크립트인데 지금까지 회귀
# 테스트가 없었다. 020-shell-scripting-standard.md 가 요구하는 완료 조건("2회 연속
# 실행 시 동일한 결과")을 사람의 확인이 아니라 기계 판정으로 승격시킨다.
#
# 실제 시스템을 건드리지 않기 위해 저장소 사본과 임시 HOME 에 대고 실행한다.
# 네트워크·sudo·패키지 설치가 필요한 구간은 PATH 앞단의 목(mock)으로 차단하되,
# 검증 대상인 stow·jq·deploy.sh 는 진짜를 그대로 쓴다. 목이 실제로 호출되면
# (= 네트워크나 sudo 경로로 빠졌다면) 마커 파일이 남아 테스트가 실패한다.
#
# 이 스킬은 검증 대상이 둘이라 케이스가 파일로 나뉘어 있다. tests/run.sh 가 진입점이고
# 이 파일은 그중 setup.sh 담당 스위트다. 단독 실행도 가능하다.
#
# 사용: bash ~/dotfiles/contexts/dotfiles/tests/setup-idempotency.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../../.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

report() {
  local name=$1 ok=$2 detail=${3:-}
  if [ "$ok" -eq 0 ]; then
    echo "  PASS  $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "  FAIL  $name"
    [ -n "$detail" ] && echo "        $detail"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 && return 0
  echo "  FAIL  도구 미설치: $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  return 1
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

TMPHOME="$TMP/home"
TMPREPO="$TMP/repo"
MOCKBIN="$TMP/bin"
MARKERS="$TMP/markers"
mkdir -p "$TMPHOME" "$TMPREPO" "$MOCKBIN" "$MARKERS"

# 목 생성. 호출 사실을 남겨야 하는 것(sudo, curl, chsh)은 마커 파일에 기록한다.
make_mock() {
  local name=$1
  shift
  {
    echo '#!/bin/sh'
    printf '%s\n' "$@"
  } >"$MOCKBIN/$name"
  chmod +x "$MOCKBIN/$name"
}

make_mock dpkg 'exit 0'      # 패키지 설치 여부 검사 통과 처리
make_mock docker 'exit 0'    # command -v docker 성립용
make_mock systemctl 'exit 0' # 출력이 없어 docker.service 분기가 성립하지 않음
make_mock mise 'exit 0'
make_mock trufflehog 'exit 0'
# $1/$2 는 목 스크립트 안에서 평가되어야 하므로 여기서 확장되면 안 된다.
# shellcheck disable=SC2016
make_mock helm '[ "$1" = plugin ] && [ "$2" = list ] && echo "diff	3.9.0"' 'exit 0'
make_mock sudo "echo \"\$*\" >>\"$MARKERS/sudo\"" 'exit 0'
make_mock chsh "echo \"\$*\" >>\"$MARKERS/chsh\"" 'exit 0'
make_mock curl "echo \"\$*\" >>\"$MARKERS/curl\"" 'exit 1' # 네트워크 시도는 실패로 취급

# 저장소 사본. .git 은 필요 없고(setup.sh 는 저장소 조작을 하지 않는다) 복사 비용만 크다.
tar -cf - --exclude=.git --exclude=.agent-state -C "$REPO_ROOT" . | tar -xf - -C "$TMPREPO"

# 네트워크 설치 구간을 건너뛰기 위한 사전 상태. 이 디렉토리들이 이미 있으면 setup.sh 는
# oh-my-zsh 다운로드와 플러그인 git clone 을 시도하지 않는다.
mkdir -p "$TMPHOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
mkdir -p "$TMPHOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
mkdir -p "$TMPHOME/.local/bin"
cp "$MOCKBIN/mise" "$TMPHOME/.local/bin/mise" # setup.sh 는 ~/.local/bin/mise 를 절대 경로로 호출한다

# 백업 경로 검증용: stow 대상과 충돌하는 "사용자의 진짜 파일"을 미리 둔다.
printf 'user-owned zshrc\n' >"$TMPHOME/.zshrc"

# 병합 보존 검증용: 사용자가 이미 설정해둔 값과 무관한 훅을 미리 둔다.
mkdir -p "$TMPHOME/.claude"
cat >"$TMPHOME/.claude/settings.json" <<'JSON'
{
  "effortLevel": "high",
  "hooks": {
    "PostToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "/opt/user/own-hook.sh"}]}
    ]
  }
}
JSON

# 파일 목록 + 심볼릭 링크 타깃 + 일반 파일 해시. 두 실행의 결과를 비교하는 데 쓴다.
snapshot_tree() {
  local root=$1 p
  while IFS= read -r -d '' p; do
    if [ -L "$p" ]; then
      printf '%s -> %s\n' "${p#"$root"/}" "$(readlink "$p")"
    else
      printf '%s = %s\n' "${p#"$root"/}" "$(sha256sum "$p" | cut -d' ' -f1)"
    fi
  done < <(find "$root" \( -type f -o -type l \) -print0 2>/dev/null) | LC_ALL=C sort
}

ZSH_PATH=$(command -v zsh)

# HOME 과 추가 인자를 받는다. dry-run 케이스가 사전 상태 없는 별도 HOME 을 써야 하는데,
# 호출부마다 서브셸을 새로 여는 것보다 이 하나를 재사용하는 편이 환경 구성이 어긋나지 않는다.
run_setup() {
  local logfile=$1 home=$2
  shift 2
  (
    cd "$TMPREPO" || exit 1
    export HOME="$home"
    export PATH="$MOCKBIN:$PATH"
    export SHELL="$ZSH_PATH" # 값이 일치하면 setup.sh 가 chsh 를 호출하지 않는다
    export ZSH_CUSTOM="$home/.oh-my-zsh/custom"
    bash "$TMPREPO/setup.sh" "$@"
  ) >"$logfile" 2>&1 </dev/null
}

echo "=== setup.sh 멱등성 회귀 테스트 ==="

for t in stow jq zsh tar sha256sum; do require_tool "$t" || exit 1; done

echo "--- 1회차 실행 ---"
if run_setup "$TMP/run1.log" "$TMPHOME"; then
  report "1회차 exit 0" 0
else
  report "1회차 exit 0" 1 "마지막 출력: $(tail -3 "$TMP/run1.log" | tr '\n' ' ')"
  echo
  echo "$PASS_COUNT/$((PASS_COUNT + FAIL_COUNT)) 통과"
  exit 1
fi

HOME_SNAP1=$(snapshot_tree "$TMPHOME")
REPO_SNAP1=$(snapshot_tree "$TMPREPO")

echo "--- 2회차 실행 (멱등성) ---"
if run_setup "$TMP/run2.log" "$TMPHOME"; then
  report "2회차 exit 0" 0
else
  report "2회차 exit 0" 1 "마지막 출력: $(tail -3 "$TMP/run2.log" | tr '\n' ' ')"
fi

HOME_SNAP2=$(snapshot_tree "$TMPHOME")
REPO_SNAP2=$(snapshot_tree "$TMPREPO")

echo "--- 검증 ---"

if [ "$HOME_SNAP1" = "$HOME_SNAP2" ]; then
  report "HOME 상태가 2회 실행 후에도 동일" 0
else
  report "HOME 상태가 2회 실행 후에도 동일" 1 \
    "차이: $(diff <(echo "$HOME_SNAP1") <(echo "$HOME_SNAP2") | grep -E '^[<>]' | head -3 | tr '\n' ' ')"
fi

if [ "$REPO_SNAP1" = "$REPO_SNAP2" ]; then
  report "저장소 상태가 2회 실행 후에도 동일" 0
else
  report "저장소 상태가 2회 실행 후에도 동일" 1 \
    "차이: $(diff <(echo "$REPO_SNAP1") <(echo "$REPO_SNAP2") | grep -E '^[<>]' | head -3 | tr '\n' ' ')"
fi

# 과거 사고 재현 방지: stow 충돌 정리 루프가 대상이 아니라 소스 파일을 지운 적이 있다.
MISSING_SRC=$(comm -23 \
  <(cd "$REPO_ROOT" && find . -type f -not -path './.git/*' -not -path './.agent-state/*' -printf '%P\n' | LC_ALL=C sort) \
  <(cd "$TMPREPO" && find . -type f -printf '%P\n' | LC_ALL=C sort) | head -3 | tr '\n' ' ')
if [ -z "$MISSING_SRC" ]; then
  report "소스 트리 파일이 삭제되지 않음" 0
else
  report "소스 트리 파일이 삭제되지 않음" 1 "사라진 파일: $MISSING_SRC"
fi

# 사용자 실파일은 백업된 뒤 링크로 교체되어야 한다.
if [ -f "$TMPHOME/.zshrc.backup" ] && grep -q "user-owned zshrc" "$TMPHOME/.zshrc.backup" && [ -L "$TMPHOME/.zshrc" ]; then
  report "충돌하는 사용자 실파일을 백업 후 링크로 교체" 0
else
  report "충돌하는 사용자 실파일을 백업 후 링크로 교체" 1 \
    ".zshrc.backup 존재=$([ -f "$TMPHOME/.zshrc.backup" ] && echo Y || echo N), .zshrc 링크=$([ -L "$TMPHOME/.zshrc" ] && echo Y || echo N)"
fi

# stow 링크가 저장소 사본을 가리켜야 한다.
STOW_BAD=""
for f in .zshrc .vimrc .gitconfig .githooks; do
  [ -L "$TMPHOME/$f" ] && [[ "$(readlink -f "$TMPHOME/$f")" == "$TMPREPO"/* ]] || STOW_BAD="$STOW_BAD $f"
done
if [ -z "$STOW_BAD" ]; then
  report "stow 링크가 저장소를 가리킴" 0
else
  report "stow 링크가 저장소를 가리킴" 1 "미연결:$STOW_BAD"
fi

# JSON 병합은 여러 번 실행해도 훅이 중복 등록되지 않아야 한다(setup.sh 주석이 명시한 계약).
HOOK_CMD="$TMPREPO/contexts/dotfiles/scripts/agent-edits-hook.sh"
CLAUDE_DUP=$(jq --arg c "$HOOK_CMD" '[.hooks.PostToolUse[] | select(([.hooks[].command] | index($c)) != null)] | length' "$TMPHOME/.claude/settings.json")
if [ "$CLAUDE_DUP" = "1" ]; then
  report "클로드 편집 이력 훅이 중복 등록되지 않음" 0
else
  report "클로드 편집 이력 훅이 중복 등록되지 않음" 1 "동일 command 항목 ${CLAUDE_DUP}개"
fi

GEMINI_DUP=$(jq '[.["agent-edits-log"].PostToolUse[]?] | length' "$TMPHOME/.gemini/config/hooks.json")
if [ "$GEMINI_DUP" = "1" ]; then
  report "제미나이 편집 이력 훅이 중복 등록되지 않음" 0
else
  report "제미나이 편집 이력 훅이 중복 등록되지 않음" 1 "PostToolUse 항목 ${GEMINI_DUP}개"
fi

# 사용자가 이미 설정해둔 값과 훅은 병합 과정에서 보존되어야 한다.
KEPT=$(jq -r '[.effortLevel, ([.hooks.PostToolUse[] | select(([.hooks[].command] | index("/opt/user/own-hook.sh")) != null)] | length | tostring)] | join(",")' "$TMPHOME/.claude/settings.json")
if [ "$KEPT" = "high,1" ]; then
  report "사용자의 기존 설정과 훅이 보존됨" 0
else
  report "사용자의 기존 설정과 훅이 보존됨" 1 "기대 'high,1' / 실제 '$KEPT'"
fi

# 스킬 등록: dotfiles 는 글로벌 룰 오염 방지를 위해 제외되어야 한다.
EXPECTED_SKILLS=$(find "$TMPREPO/contexts" -mindepth 2 -maxdepth 2 -name SKILL.md -printf '%h\n' | xargs -r -n1 basename | grep -vx dotfiles | LC_ALL=C sort)
ACTUAL_SKILLS=$(find "$TMPHOME/.claude/skills" -mindepth 2 -maxdepth 2 -name SKILL.md -printf '%h\n' 2>/dev/null | xargs -r -n1 basename | LC_ALL=C sort)
if [ "$EXPECTED_SKILLS" = "$ACTUAL_SKILLS" ]; then
  report "클로드 글로벌 스킬 등록 (dotfiles 제외)" 0
else
  report "클로드 글로벌 스킬 등록 (dotfiles 제외)" 1 \
    "차이: $(diff <(echo "$EXPECTED_SKILLS") <(echo "$ACTUAL_SKILLS") | grep -E '^[<>]' | tr '\n' ' ')"
fi

# agent-handoff 만 링크가 아니라 역할별 복사본으로 배포된다. setup.sh 주석이 명시한
# 계약은 "상대 역할 지침이 배포본에 아예 존재하지 않는다"이므로, 자기 역할 헤더가 있고
# 상대 역할 헤더는 없어야 한다. '아키텍트' 같은 낱말은 실행자 지침에도 상대를 가리키며
# 등장하므로 판정 기준이 될 수 없다.
HANDOFF_CLAUDE="$TMPHOME/.claude/skills/agent-handoff/SKILL.md"
HANDOFF_GEMINI="$TMPHOME/.gemini/config/skills/agent-handoff/SKILL.md"
handoff_role_ok() {
  local file=$1 own=$2 other=$3
  [ -f "$file" ] && [ ! -L "$file" ] &&
    grep -q "\[역할: $own\]" "$file" && ! grep -q "\[역할: $other\]" "$file"
}
if handoff_role_ok "$HANDOFF_CLAUDE" architect executor &&
  handoff_role_ok "$HANDOFF_GEMINI" executor architect; then
  report "agent-handoff 가 역할별 복사본으로 분리 배포됨" 0
else
  report "agent-handoff 가 역할별 복사본으로 분리 배포됨" 1 \
    "클로드=$(handoff_role_ok "$HANDOFF_CLAUDE" architect executor && echo OK || echo NG), 제미나이=$(handoff_role_ok "$HANDOFF_GEMINI" executor architect && echo OK || echo NG)"
fi

# 네트워크·권한 상승 경로로 빠지지 않았는지 확인. 목이 호출되면 마커가 남는다.
LEAKED=""
for m in curl sudo chsh; do
  [ -s "$MARKERS/$m" ] && LEAKED="$LEAKED $m($(wc -l <"$MARKERS/$m")회)"
done
if [ -z "$LEAKED" ]; then
  report "네트워크·sudo 경로를 타지 않음" 0
else
  report "네트워크·sudo 경로를 타지 않음" 1 "호출됨:$LEAKED"
fi

# --dry-run 계약: 상태를 바꾸는 명령을 하나도 실행하지 않는다. 이 모드가 조용히 무언가를
# 쓰면 "실행 전에 무엇이 바뀌는지 본다"는 목적 자체가 무너지므로 기계 판정으로 고정한다.
# 앞선 두 실행과 달리 사전 상태를 전혀 만들지 않은 빈 HOME 을 쓴다. 설치 분기가 전부
# "아직 없음" 쪽으로 갈라져야 dry-run 이 실제로 막아내는지 확인할 수 있다.
echo "--- 3회차 실행 (--dry-run, 빈 HOME) ---"
DRYHOME="$TMP/dryhome"
mkdir -p "$DRYHOME"
REPO_SNAP_BEFORE_DRY=$(snapshot_tree "$TMPREPO")

if run_setup "$TMP/run3.log" "$DRYHOME" --dry-run; then
  report "--dry-run exit 0" 0
else
  report "--dry-run exit 0" 1 "마지막 출력: $(tail -3 "$TMP/run3.log" | tr '\n' ' ')"
fi

DRY_LEFTOVER=$(find "$DRYHOME" -mindepth 1 2>/dev/null | head -3 | tr '\n' ' ')
if [ -z "$DRY_LEFTOVER" ]; then
  report "--dry-run 이 HOME 에 아무것도 만들지 않음" 0
else
  report "--dry-run 이 HOME 에 아무것도 만들지 않음" 1 "생성됨: $DRY_LEFTOVER"
fi

if [ "$REPO_SNAP_BEFORE_DRY" = "$(snapshot_tree "$TMPREPO")" ]; then
  report "--dry-run 이 저장소를 변경하지 않음" 0
else
  report "--dry-run 이 저장소를 변경하지 않음" 1 \
    "차이: $(diff <(echo "$REPO_SNAP_BEFORE_DRY") <(snapshot_tree "$TMPREPO") | grep -E '^[<>]' | head -3 | tr '\n' ' ')"
fi

# 빈 HOME 이라 설치 분기가 전부 열리는데도 마커가 늘지 않아야 dry-run 이 성립한다.
DRY_LEAKED=""
for m in curl sudo chsh; do
  [ -s "$MARKERS/$m" ] && DRY_LEAKED="$DRY_LEAKED $m($(wc -l <"$MARKERS/$m")회)"
done
if [ -z "$DRY_LEAKED" ]; then
  report "--dry-run 이 네트워크·sudo 를 호출하지 않음" 0
else
  report "--dry-run 이 네트워크·sudo 를 호출하지 않음" 1 "호출됨:$DRY_LEAKED"
fi

# 부트스트랩 이식성 계약: setup.sh 는 macOS 기본 bash(3.2)에서 실행 가능해야 한다.
# 이 스크립트가 설치해 주는 bash 4 를 스스로 요구하면 사용자가 손으로 brew install bash 를
# 먼저 쳐야 하는 닭-달걀이 된다. 조항으로만 두면 나중에 mapfile 한 줄로 조용히 깨지므로
# 기계 판정으로 승격시킨다. 검증기와 훅은 대상이 아니다(bash 설치 이후에 실행된다).
# 주석 줄은 제외한다: 계약 자체를 설명하는 주석에 금지 문법의 이름이 등장한다.
# `|| true` 가 필수다: 지적이 0건이면(= 통과 조건) grep 이 1 을 반환하고, pipefail 아래에서
# 그 실패가 파이프라인 전체의 실패로 올라와 set -e 가 스위트를 통째로 중단시킨다.
BASH4_HITS=$(grep -nE '^[^#]*(mapfile|readarray|declare -A|local -n|\[\[ -v |\$\{[A-Za-z_]+(\^\^|,,))' \
  "$REPO_ROOT/setup.sh" | head -3 | tr '\n' ' ' || true)
if [ -z "$BASH4_HITS" ]; then
  report "setup.sh 가 bash 4 전용 문법을 쓰지 않음" 0
else
  report "setup.sh 가 bash 4 전용 문법을 쓰지 않음" 1 "발견: $BASH4_HITS"
fi

# 같은 계약의 나머지 절반: GNU 전용 도구는 gnubin 을 PATH 에 얹기 전에 쓰면 안 된다.
# macOS 의 BSD 판은 readlink 에 -f 가 없고 mktemp 는 템플릿 인자를 요구하므로, 주입 지점
# 위쪽에서 호출하면 첫 실행이 그대로 실패한다.
GNUBIN_LINE=$(grep -nm1 'libexec/gnubin' "$REPO_ROOT/setup.sh" | cut -d: -f1 || true)
if [ -n "$GNUBIN_LINE" ]; then
  EARLY_GNU=$(head -n "$((GNUBIN_LINE - 1))" "$REPO_ROOT/setup.sh" |
    grep -nE '^[^#]*(readlink -f|mktemp|-printf|sha256sum)' | head -3 | tr '\n' ' ' || true)
  if [ -z "$EARLY_GNU" ]; then
    report "GNU 전용 도구를 gnubin 주입 이전에 쓰지 않음" 0
  else
    report "GNU 전용 도구를 gnubin 주입 이전에 쓰지 않음" 1 "발견: $EARLY_GNU"
  fi
else
  report "GNU 전용 도구를 gnubin 주입 이전에 쓰지 않음" 1 "gnubin 주입 블록을 찾지 못했습니다"
fi

# 알 수 없는 옵션은 조용히 무시되면 안 된다(오타로 --dry-runn 을 치면 실제 실행된다).
# 옵션 파싱은 스크립트의 첫 실행 구문이라 여기서 exit 하면 어떤 상태도 건드리지 않는다.
# 그래서 이 케이스만은 목이나 임시 HOME 없이 그대로 호출해도 안전하다.
if bash "$TMPREPO/setup.sh" --nonexistent-option >/dev/null 2>&1; then
  report "알 수 없는 옵션에 대해 실행을 거부" 1 "exit 0 으로 통과했습니다"
else
  report "알 수 없는 옵션에 대해 실행을 거부" 0
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
echo
echo "$PASS_COUNT/$TOTAL 통과"
[ "$FAIL_COUNT" -eq 0 ] || exit 1
