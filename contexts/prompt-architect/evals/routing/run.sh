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
# observed.tsv 만드는 법:
#   같은 폴더의 measure.sh 가 자동 생성한다. 별도 CLI 설치는 필요 없고, Claude Code
#   IDE 확장이 번들한 네이티브 바이너리를 자동 탐색해 쓴다.
#     bash ~/dotfiles/contexts/prompt-architect/evals/routing/measure.sh
#   기록 형식은 '<id> <TAB> <로드된 스킬 쉼표구분 또는 none>' 이다.
#   예:  S01	aws
#        A03	observability,k8s
#
# 사용: bash ~/dotfiles/contexts/prompt-architect/evals/routing/run.sh

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
# 이 단계가 실패해도 즉시 죽이지 않고 종료 코드만 붙잡아 둔다. 채점(2단계)은 이 분석과
# 독립적으로 유용한 정보이므로, 어느 항목이 실패했는지 전부 보여준 뒤 마지막에 한 번
# 중단한다(compact-runner.sh 와 동일한 규범).
DESC_RC=0
python3 - "$CONTEXTS_DIR" <<'PY' || DESC_RC=$?
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
    # description 에 "언제 이 스킬을 쓰라"는 안내 문장을 넣으면 서술어와 조사 결합형이
    # 토큰으로 잡힌다. 도메인 신호가 0이라 위 분류 명사와 같은 이유로 제외한다
    # (토크나이저가 한국어 조사를 분리하지 않아 '스킬'과 '스킬도'가 별개 토큰이 된다).
    "스킬입니다", "스킬도", "사용하십시오", "로드하십시오", "필요합니다", "가능하며",
    "포함하며", "다룹니다", "산출합니다", "같이", "함께", "이때는", "여기서", "요청",
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


# dotfiles 는 Ansible 셋업의 글로벌 스킬 등록 루프가 제외한다(글로벌 룰 순수성 보장).
# 프로젝트 CLAUDE.md 심볼릭 링크로 무조건 로드되므로 description 라우팅을 거치지
# 않는다. 분석에 넣으면 존재하지 않는 경합을 보고하게 된다.
NOT_ROUTED = {"dotfiles"}

desc = {}
for path in sorted(glob.glob(os.path.join(contexts, "*", "SKILL.md"))):
    skill = os.path.basename(os.path.dirname(path))
    if skill in NOT_ROUTED:
        continue
    text = open(path, encoding="utf-8").read()
    # 종료 경계에 frontmatter 구분자('---')를 포함시킨다. 예전 패턴은 description 뒤에
    # 또 다른 '필드:' 가 오는 것만 전제해서, reviewed: 필드가 제거되어 description 이
    # frontmatter 의 마지막 항목이 된 순간 12개 스킬 전부 파싱에 실패했다(2026-07-28 실측).
    m = re.search(r"^description:(.*?)(?=^[a-z_]+:|^---\s*$)", text, re.M | re.S)
    if m:
        desc[skill] = tokens(m.group(1))

# 파싱 0건은 "겹치는 용어가 없다"가 아니라 "검사를 한 건도 못 했다"이다. 그 둘을 구분하지
# 않았던 탓에, frontmatter 에서 description 뒤 필드가 사라져 정규식이 전부 빗나가는 동안에도
# "[INFO] 3개 이상 스킬이 공유하는 용어 없음" 이라는 초록불이 그대로 출력됐다(2026-07-28
# 실측: 12개 중 0개 파싱). 이 분석은 CLAUDE.md 의 Paid Eval Gate 가 유료 측정의 무료
# 대체재로 지정한 경로라, 조용히 죽으면 "토큰을 아끼려고 이쪽을 썼다"는 판단이 근거를 잃는다.
if not desc:
    print("[ERROR] SKILL.md 에서 description 을 하나도 파싱하지 못했습니다.")
    print("        frontmatter 형식이 바뀌었을 수 있습니다. 현재 정규식은 description 다음에")
    print("        다른 '필드:' 또는 frontmatter 종료 구분자 '---' 가 오는 것을 전제합니다.")
    sys.exit(1)

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
    # 종료 경계에 frontmatter 구분자('---')를 포함시킨다. 예전 패턴은 description 뒤에
    # 또 다른 '필드:' 가 오는 것만 전제해서, reviewed: 필드가 제거되어 description 이
    # frontmatter 의 마지막 항목이 된 순간 12개 스킬 전부 파싱에 실패했다(2026-07-28 실측).
    m = re.search(r"^description:(.*?)(?=^[a-z_]+:|^---\s*$)", text, re.M | re.S)
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
  # (1=오라우팅 발견 또는 description 분석 실패, 2=미측정, 0=전부 일치).
  echo "[UNMEASURED] $OBSERVED 가 없어 채점하지 못했습니다. 정확도는 '미측정'입니다."
  echo "             측정하려면 아래를 실행하십시오 (별도 CLI 설치 불필요 —"
  echo "             Claude Code IDE 확장의 번들 바이너리를 자동 탐색합니다):"
  echo "               bash $EVAL_DIR/measure.sh"
  echo "======================================================"
  # 검사기가 고장난 상태는 미측정보다 심각하므로 그쪽을 우선 보고한다.
  [ "$DESC_RC" -eq 0 ] || exit 1
  exit 2
fi

# 채점기는 오라우팅이 있으면 exit 1 을 반환한다. set -e 하에서 그대로 두면 이 지점에서
# 스크립트가 죽어 아래 안정성 리포트가 영영 출력되지 않으므로, 종료 코드를 붙잡아 두고
# 마지막에 그대로 반환한다(2026-07-27 실측: 안정성 섹션이 조용히 누락됨).
SCORE_RC=0
python3 - "$CASES" "$OBSERVED" <<'PY' || SCORE_RC=$?
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

# -----------------------------------------------------------------------------
# 3. 측정 안정성 (measure.sh 가 남긴 회차별 원본이 있을 때만)
# -----------------------------------------------------------------------------
# 라우팅은 비결정적이라 1회 draw 로는 description 수정이 개선인지 노이즈인지 구분할 수
# 없다. 필요한 스킬은 매번 떠야 하므로 pass@k(1회라도 성공)가 아니라 pass^k(k회 전부
# 성공) 기준으로 본다. 회차마다 결과가 갈린 케이스는 점수와 별개로 드러내야, 흔들리는
# 조항을 고정된 실패와 구분해 손볼 수 있다.
RUNS_FILE="$EVAL_DIR/observed-runs.tsv"
if [ -f "$RUNS_FILE" ]; then
  echo "--- Step: 측정 안정성 (pass^k) ---"
  python3 - "$CASES" "$RUNS_FILE" <<'PY'
import sys
from collections import defaultdict


def norm(v):
    return frozenset() if v == 'none' else frozenset(s.strip() for s in v.split(',') if s.strip())


expected = {}
for line in open(sys.argv[1], encoding='utf-8'):
    line = line.rstrip('\n')
    if not line.strip() or line.lstrip().startswith('#'):
        continue
    p = line.split('\t')
    if len(p) >= 2:
        expected[p[0].strip()] = norm(p[1].strip())

runs = defaultdict(list)
for line in open(sys.argv[2], encoding='utf-8'):
    p = line.rstrip('\n').split('\t')
    if len(p) >= 3:
        runs[p[0].strip()].append(norm(p[2].strip()))

if not runs:
    print("[INFO] 회차 기록이 비어 있습니다.")
    sys.exit(0)

k = max(len(v) for v in runs.values())
stable_pass = [c for c, v in runs.items() if c in expected and all(r == expected[c] for r in v)]
flaky = [(c, v) for c, v in sorted(runs.items()) if len(set(v)) > 1]
scored = [c for c in runs if c in expected]

print(f"pass^{k} (k회 전부 기대와 일치): {len(stable_pass)}/{len(scored)}"
      f" ({len(stable_pass) * 100 // len(scored)}%)" if scored else "채점 대상 없음")
if flaky:
    print()
    print(f"회차마다 결과가 갈린 케이스 {len(flaky)}건 (라우팅 비결정성):")
    for c, v in flaky:
        seen = ['none' if not r else ','.join(sorted(r)) for r in v]
        print(f"  {c}  " + " | ".join(seen))
else:
    print(f"[INFO] {k}회 반복에서 결과가 갈린 케이스 없음.")
PY
fi

echo "======================================================"
if [ "$DESC_RC" -ne 0 ]; then
  echo "[ERROR] description 중복 분석 단계가 실패했습니다 (위 [ERROR] 참조)." >&2
  echo "        검사기가 죽은 상태의 라우팅 정확도는 반쪽짜리 신호이므로 실패로 종료합니다." >&2
  exit 1
fi
exit "$SCORE_RC"
