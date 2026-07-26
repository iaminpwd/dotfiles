#!/usr/bin/env bash
# 스킬 라우팅 eval
#
# on-demand 스킬은 SKILL.md 의 description 만 보고 로드된다. description 이
# 겹치면 불필요한 스킬이 함께 로드되어(오탐) 세션마다 토큰을 낭비하고,
# 반대로 좁으면 필요한 스킬이 안 뜬다(미탐).
#
# 두 가지를 수행한다.
#   1. description 용어 중복 분석 — 정적, 항상 실행
#      라우터가 보는 텍스트에서 여러 스킬이 공유하는 용어를 찾는다.
#      공유 용어가 많을수록 그 주제의 입력은 라우팅이 흔들린다.
#   2. 라우팅 정확도 채점 — observed.tsv 가 있을 때만 실행
#      cases.tsv 의 정답과 실제 로드된 스킬을 대조한다.
#
# observed.tsv 만드는 법 (헤드리스 CLI 필요):
#   각 케이스의 입력을 에이전트에 넣고, 실제 로드된 스킬을 아래 형식으로 기록.
#     <id> <TAB> <로드된 스킬 쉼표구분 또는 none>
#   예:  S01	aws
#        A03	observability,k8s
#
# 사용: bash ~/dotfiles/contexts/dotfiles/evals/routing/run.sh

set -euo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTEXTS_DIR="$(cd "$EVAL_DIR/../../.." && pwd)"
CASES="$EVAL_DIR/cases.tsv"
OBSERVED="$EVAL_DIR/observed.tsv"

[ -f "$CASES" ] || {
  echo "[ERROR] 케이스 파일이 없습니다: $CASES" >&2
  exit 1
}

echo "======================================================"
echo "=== 스킬 라우팅 eval ==="
echo "======================================================"

# -----------------------------------------------------------------------------
# 1. description 용어 중복 분석 (정적)
# -----------------------------------------------------------------------------
echo "--- Step: Description 용어 중복 (라우팅 모호성 후보) ---"
python3 - "$CONTEXTS_DIR" <<'PY'
import re, sys, glob, os
from collections import defaultdict

contexts = sys.argv[1]
# 라우팅 판단에 기여하지 않는 일반어. 이 목록에 없는 토큰만 신호로 본다.
STOP = {
    "스킬", "작업", "전반", "등", "및", "또는", "구성", "관리", "설계", "지원",
    "가이드", "자동", "생성", "분석", "적용", "사용", "위한", "모든", "공통",
    "코드", "파일", "환경", "시스템", "통합", "운영", "기반", "각종", "관련",
    # 거의 모든 description 에 등장하는 분류 명사. 변별력이 없어 신호로 쓰면
    # 의도된 겹침까지 경고가 된다(2026-07-26 실측: 이 셋을 빼면 경고 9건 -> 6건,
    # 남는 건 전부 실제 검토가 필요한 항목).
    "엔지니어링", "인프라", "클라우드",
}


def tokens(text):
    # 영문 서비스명(EKS, OpenTelemetry)과 한글 명사를 함께 뽑는다.
    raw = re.findall(r"[A-Za-z][A-Za-z0-9.+-]{1,}|[가-힣]{2,}", text)
    out = set()
    for t in raw:
        t = t.strip(".,")
        if len(t) < 2 or t in STOP:
            continue
        out.add(t if not t.isascii() else t.lower())
    return out


# dotfiles 는 setup.sh:163 이 글로벌 스킬 등록에서 제외한다(글로벌 룰 오염 방지).
# 프로젝트 CLAUDE.md 심볼릭 링크로 무조건 로드되므로 description 라우팅을 거치지
# 않는다. 분석에 넣으면 존재하지 않는 경합을 보고하게 된다.
NOT_ROUTED = {"dotfiles"}

desc = {}
for path in sorted(glob.glob(os.path.join(contexts, "*", "SKILL.md"))):
    skill = os.path.basename(os.path.dirname(path))
    if skill in NOT_ROUTED:
        continue
    text = open(path, encoding="utf-8").read()
    m = re.search(r"^description:(.*?)^[a-z_]+:", text, re.M | re.S)
    if m:
        desc[skill] = tokens(m.group(1))

owners = defaultdict(list)
for skill, toks in desc.items():
    for t in toks:
        owners[t].append(skill)

# 2개 스킬만 공유하는 용어는 대부분 의도된 것이다. drawio-gen 이 description 에
# eks/cloudformation 을 예시로 적은 것이 대표적이고, 벤더명이 함께 등장하면
# 입력에서 자연히 구분된다. 3개 이상이 공유할 때만 실제로 구분 신호가 사라진다.
# 세 벤더 클라우드 스킬끼리만 겹치는 용어는 의도된 미러링이다(prompt-lint.sh 9번
# 검사와 동일한 판단). 입력에 벤더명이 함께 등장하므로 실제로는 구분된다.
VENDOR_MIRROR = {"aws", "azure", "openstack"}
shared = {
    t: s for t, s in owners.items()
    if len(s) >= 3 and not set(s) <= VENDOR_MIRROR
}
if not shared:
    print("[INFO] 3개 이상 스킬이 공유하는 용어 없음.")
else:
    for t, skills in sorted(shared.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        print(f"[WARNING] '{t}' 를 {len(skills)}개 스킬이 공유: {', '.join(sorted(skills))}")

# 스킬 쌍별 중복도. aws/azure 미러링은 의도된 구조이므로(prompt-lint.sh 9번 검사와
# 동일한 판단) 제외한다. 벤더명이 입력에 등장하면 구분되기 때문이다.
pairs = []
names = sorted(desc)
for i, a in enumerate(names):
    for b in names[i + 1:]:
        if {a, b} == {"aws", "azure"}:
            continue
        common = desc[a] & desc[b]
        if len(common) >= 3:
            pairs.append((len(common), a, b, sorted(common)))
if pairs:
    print()
    for n, a, b, common in sorted(pairs, reverse=True):
        print(f"[WARNING] {a} <-> {b} 공유 {n}건: {', '.join(common)}")

# 공유 구절. 토큰 개수만 세면 "AI 에이전트"처럼 두 description 에 통째로 같은
# 표현이 들어간 경우를 놓친다(2026-07-26: aiops/dotfiles 가 이 사유로 임계값
# 아래에 숨었다). 연속 2어절이 그대로 겹치면 개수와 무관하게 보고한다.
raw = {}
for path in sorted(glob.glob(os.path.join(contexts, "*", "SKILL.md"))):
    skill = os.path.basename(os.path.dirname(path))
    if skill in NOT_ROUTED:
        continue
    text = open(path, encoding="utf-8").read()
    m = re.search(r"^description:(.*?)^[a-z_]+:", text, re.M | re.S)
    if m:
        words = [w.strip(".,()") for w in m.group(1).split()]
        raw[skill] = {
            f"{a} {b}" for a, b in zip(words, words[1:])
            if len(a) > 1 and len(b) > 1 and a not in STOP and b not in STOP
        }

phrase_owners = defaultdict(list)
for skill, phrases in raw.items():
    for p in phrases:
        phrase_owners[p].append(skill)
dup_phrases = {
    p: s for p, s in phrase_owners.items()
    if len(s) >= 2 and not set(s) <= VENDOR_MIRROR
}
if dup_phrases:
    print()
    for p, skills in sorted(dup_phrases.items()):
        print(f"[WARNING] 구절 '{p}' 가 {len(skills)}개 description 에 동일하게 등장: {', '.join(sorted(skills))}")

print()
print("[INFO] description 중복 분석 완료.")
PY

# -----------------------------------------------------------------------------
# 2. 라우팅 정확도 채점 (observed.tsv 존재 시에만)
# -----------------------------------------------------------------------------
echo "--- Step: 라우팅 정확도 ---"
if [ ! -f "$OBSERVED" ]; then
  # 종료 코드 0으로 끝내면 "라우팅 정확도가 검증됐다"는 초록불로 오해된다. 실제로는
  # 한 건도 채점하지 않은 미측정 상태이므로 별도 코드(2)로 구분해 반환한다
  # (1=오라우팅 발견, 2=미측정, 0=전부 일치).
  echo "[UNMEASURED] $OBSERVED 가 없어 채점하지 못했습니다. 정확도는 '미측정'입니다."
  echo "             실제 라우팅을 관측하려면 헤드리스 CLI 로 각 케이스를 실행한 뒤"
  echo "             '<id><TAB><로드된 스킬>' 형식으로 observed.tsv 를 만드십시오."
  echo "======================================================"
  exit 2
fi

python3 - "$CASES" "$OBSERVED" <<'PY'
import sys
from collections import defaultdict


def load(path):
    rows = {}
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        cid = parts[0].strip()
        val = parts[1].strip()
        rows[cid] = set() if val == "none" else {s.strip() for s in val.split(",") if s.strip()}
    return rows


cases_path, obs_path = sys.argv[1], sys.argv[2]
expected = load(cases_path)
observed = load(obs_path)

missing = sorted(set(expected) - set(observed))
exact = 0
tp = defaultdict(int)
fp = defaultdict(int)
fn = defaultdict(int)
misroutes = []

scored = [c for c in expected if c in observed]
for cid in sorted(scored):
    want, got = expected[cid], observed[cid]
    if want == got:
        exact += 1
    else:
        extra = sorted(got - want)
        absent = sorted(want - got)
        misroutes.append((cid, sorted(want), sorted(got), extra, absent))
    for s in want & got:
        tp[s] += 1
    for s in got - want:
        fp[s] += 1
    for s in want - got:
        fn[s] += 1

n = len(scored)
if n == 0:
    print("[ERROR] 채점 가능한 케이스가 없습니다.")
    sys.exit(1)

print(f"완전 일치: {exact}/{n} ({exact * 100 // n}%)")
if missing:
    print(f"[WARNING] 관측 결과가 없는 케이스 {len(missing)}건: {', '.join(missing)}")

print()
print(f"{'스킬':<18}{'정밀도':>8}{'재현율':>8}   (오탐/미탐)")
for s in sorted(set(tp) | set(fp) | set(fn)):
    p = tp[s] / (tp[s] + fp[s]) if (tp[s] + fp[s]) else 1.0
    r = tp[s] / (tp[s] + fn[s]) if (tp[s] + fn[s]) else 1.0
    print(f"{s:<18}{p:>7.0%}{r:>8.0%}   ({fp[s]}/{fn[s]})")

if misroutes:
    print()
    print("오라우팅:")
    for cid, want, got, extra, absent in misroutes:
        detail = []
        if extra:
            detail.append(f"오탐 +{','.join(extra)}")
        if absent:
            detail.append(f"미탐 -{','.join(absent)}")
        print(f"  {cid}  기대[{','.join(want)}] 실제[{','.join(got) or 'none'}]  {' '.join(detail)}")

sys.exit(1 if misroutes else 0)
PY
echo "======================================================"
