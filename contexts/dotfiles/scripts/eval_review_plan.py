#!/usr/bin/env python3
"""gemini_review.py 계획 로직 검증 (Gemini API 호출 없음, 무료)

야간 리뷰 파이프라인이 실제로 호출을 태우기 전에, 계획 단계에서 확정되는 성질만
정량 검사한다. 수집 정합성, 요일 버킷 1회전, 패스 로테이션 균등성, 무료 티어
RPD/TPM 예산 적합성이 대상이다.

사용법:
    python3 contexts/dotfiles/scripts/eval_review_plan.py     # 실패 시 종료 코드 1
"""
import os
import sys
import glob
import datetime
import importlib.util
from collections import Counter, defaultdict
from typing import Dict, List

# 무료 티어 한도. 변경 시 이 두 값만 고치면 된다.
TPM_LIMIT = 250_000
RPD_LIMIT = 20
# 단일 호출이 TPM 을 이 비율 이상 점유하면 실패로 본다. 응답 토큰과 재시도 여유분이다.
TPM_SAFETY_RATIO = 0.8
# 요일 주기(7)와 스크립트 패스 수의 최소공배수만큼 돌려 장기 분포를 본다.
ROTATION_DAYS = 28

# 이 파일은 contexts/dotfiles/scripts/ 에 있으므로 3단계 위가 레포 루트다.
REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

failures: List[str] = []
warnings: List[str] = []


def load_review_module():
    """검사 대상 모듈을 경로로 직접 적재한다. (scripts/ 는 패키지가 아니다)"""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gemini_review.py")
    spec = importlib.util.spec_from_file_location("gemini_review", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def check(name: str, ok: bool, detail: str = "") -> None:
    print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f" — {detail}" if detail else ""))
    if not ok:
        failures.append(name)


def warn(name: str, detail: str) -> None:
    print(f"[WARN] {name} — {detail}")
    warnings.append(name)


def section(title: str) -> None:
    print()
    print("=" * 70)
    print(title)
    print("=" * 70)


def check_collection(gr, doc_groups: Dict[str, Dict[str, str]],
                     script_files: Dict[str, str]) -> None:
    section("1. 수집 정합성")

    doc_paths = [p for group in doc_groups.values() for p in group]
    raw = sorted(p for p in set(glob.glob("*.md")) | set(glob.glob("contexts/**/*.md", recursive=True))
                 if os.path.isfile(p))
    expected = set(gr.dedupe_symlinks(raw))
    check("문서 수집 누락 없음 (심볼릭 링크 제외)", set(doc_paths) == expected,
          f"수집 {len(doc_paths)}개 / 기대 {len(expected)}개 "
          f"(원본 {len(raw)}개 중 링크 {len(raw) - len(expected)}개 제외)")
    check("스크립트 수집됨", len(script_files) > 0, f"{len(script_files)}개")

    for label, paths in (("문서", doc_paths), ("스크립트", list(script_files))):
        by_real = defaultdict(list)
        for path in paths:
            by_real[os.path.realpath(path)].append(path)
        dups = {k: v for k, v in by_real.items() if len(v) > 1}
        check(f"{label} 실체 중복 없음", not dups,
              "; ".join(f"{os.path.relpath(k, REPO_ROOT)} <- {v}" for k, v in dups.items()))


def check_buckets(gr, doc_groups: Dict[str, Dict[str, str]]) -> None:
    section("2. 버킷 분배 (7일 1회전)")

    buckets = gr.balance_buckets(doc_groups)
    flat = [name for bucket in buckets for name in bucket]
    check("버킷 수 == BUCKET_COUNT", len(buckets) == gr.BUCKET_COUNT, f"{len(buckets)}개")
    check("모든 그룹이 정확히 1회 배정",
          sorted(flat) == sorted(doc_groups) and len(flat) == len(set(flat)),
          f"배정 {len(flat)}개 / 전체 그룹 {len(doc_groups)}개")

    sizes = [sum(gr.group_size(doc_groups[name]) for name in bucket) for bucket in buckets]
    for index, (bucket, size) in enumerate(zip(buckets, sizes)):
        print(f"    요일 {index}: {size:>7,} bytes  {bucket}")
    ratio = max(sizes) / max(min(sizes), 1)
    check("버킷 편차 3배 이내", ratio <= 3.0, f"최대/최소 = {ratio:.2f}배")


def check_daily_plan(gr, doc_groups, script_files) -> int:
    section("3. 요일별 호출 계획")

    peak = 0
    for weekday in range(gr.BUCKET_COUNT):
        calls, _ = gr.plan_daily_calls(doc_groups, script_files, weekday)
        tokens = [gr.estimate_tokens(context) for _, _, context, _ in calls]
        peak = max(peak, max(tokens))
        labels = [label.split(" ")[0] for label, _, _, _ in calls]
        print(f"    요일 {weekday}: 패스 {len(calls)}개  최대 단일 {max(tokens):>7,} tok  "
              f"합계 {sum(tokens):>8,} tok  {labels}")

        has_global = any(label in ("A-1", "A-4", "A-3") for label in labels)
        expected_global = weekday == gr.GLOBAL_PASS_WEEKDAY
        check(f"요일 {weekday}: 전역 패스 {'포함' if expected_global else '제외'}",
              has_global == expected_global, str(labels))

    return peak


def check_rotation(gr, doc_groups, script_files) -> None:
    section(f"4. 스크립트 패스 로테이션 분포 ({ROTATION_DAYS}일)")

    hits = Counter()
    base = datetime.date.today().toordinal()
    for offset in range(ROTATION_DAYS):
        calls, _ = gr.plan_daily_calls(doc_groups, script_files,
                                       offset % gr.BUCKET_COUNT, base + offset)
        hits[next(label.split(" ")[0] for label, _, _, _ in calls
                  if label.startswith("B-"))] += 1

    for pass_id, _ in gr.SCRIPT_PASSES:
        print(f"    {pass_id}: {ROTATION_DAYS}일간 {hits[pass_id]}회")
    check(f"{ROTATION_DAYS}일 주기에서 스크립트 패스가 균등 실행",
          len(set(hits.values())) == 1 and len(hits) == len(gr.SCRIPT_PASSES), str(dict(hits)))


def check_quota(gr, doc_groups, script_files, peak_tokens: int) -> None:
    section(f"5. 무료 티어 예산 (RPD {RPD_LIMIT} / TPM {TPM_LIMIT:,})")

    check("스크립트의 RPD 예산이 실제 한도 이하",
          gr.MAX_DAILY_REQUESTS <= RPD_LIMIT,
          f"MAX_DAILY_REQUESTS={gr.MAX_DAILY_REQUESTS} <= {RPD_LIMIT}")

    for weekday in range(gr.BUCKET_COUNT):
        calls, _ = gr.plan_daily_calls(doc_groups, script_files, weekday)
        planned = len(calls) + 2                                   # 카나리아 + 최종 정제
        worst = 1 + (len(calls) + 1) * gr.MAX_RETRIES
        print(f"    요일 {weekday}: 계획 {planned:>2}회 / 최악(재시도 {gr.MAX_RETRIES}회) {worst:>2}회")
        check(f"요일 {weekday}: 계획 요청이 RPD 예산 이내", planned <= gr.MAX_DAILY_REQUESTS,
              f"{planned} <= {gr.MAX_DAILY_REQUESTS}")
        if worst > gr.MAX_DAILY_REQUESTS:
            warn(f"요일 {weekday}: 최악 재시도 시 예산 초과",
                 f"{worst} > {gr.MAX_DAILY_REQUESTS} — consume_request_budget 가 차단해야 함")

    # 호출 간격이 60s 이상이면 TPM 은 사실상 호출 1건당 걸린다.
    limit = int(TPM_LIMIT * TPM_SAFETY_RATIO)
    print(f"    최대 단일 호출 입력: {peak_tokens:,} tok = 한도의 {peak_tokens / TPM_LIMIT:.0%}")
    check(f"최대 단일 호출이 TPM 한도의 {TPM_SAFETY_RATIO:.0%} 이내",
          peak_tokens <= limit, f"{peak_tokens:,} / {limit:,}")


def main() -> None:
    os.chdir(REPO_ROOT)
    gr = load_review_module()

    doc_groups = gr.scan_doc_groups()
    script_files = gr.scan_script_files()

    check_collection(gr, doc_groups, script_files)
    check_buckets(gr, doc_groups)
    peak = check_daily_plan(gr, doc_groups, script_files)
    check_rotation(gr, doc_groups, script_files)
    check_quota(gr, doc_groups, script_files, peak)

    section(f"결과: FAIL {len(failures)}건 / WARN {len(warnings)}건")
    for name in failures:
        print(f"  FAIL: {name}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
