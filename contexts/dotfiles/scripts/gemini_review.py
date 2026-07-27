#!/usr/bin/env python3
"""심야 자동 리뷰 파이프라인 (시야 분리 + 요일 로테이션)

무료 티어의 분당 토큰(TPM) 예산에 맞추기 위해, 전 코퍼스를 매 패스마다
재전송하지 않고 각 패스가 실제로 필요로 하는 시야만 입력한다.

  - 전역 패스: 조항 인덱스(파일 경로 + 헤딩 + 조항명)만 입력하고 주 1회 실행
  - 로컬 패스: 스킬 단위 청크 전문을 입력하고 요일별로 순회 (7일에 전 코퍼스 1회전)
  - 링크/코드펜스/SSOT 무결성: prompt-lint.sh 가 결정론적으로 검사하므로 LLM 패스 없음
"""
import os
import re
import sys
import time
import glob
import argparse
import datetime
from typing import Dict, List, Any, Tuple

try:
    from google import genai
    from google.genai import types
    from google.genai.errors import APIError
    HAS_GENAI_SDK = True
except ImportError:
    genai = None
    types = None
    APIError = Exception
    HAS_GENAI_SDK = False

DEFAULT_MODEL = os.getenv("GEMINI_MODEL", "gemini-3.6-flash")
# 호출 간격. TPM 은 분당 예산이므로 간격을 벌리면 총량 제약이 사라진다.
CALL_INTERVAL_SEC = int(os.getenv("GEMINI_CALL_INTERVAL", "90"))
MAX_RETRIES = int(os.getenv("GEMINI_MAX_RETRIES", "3"))
# 일 요청 수(RPD) 예산. 대기로 회복되지 않으므로 초과 전에 스스로 멈춘다.
MAX_DAILY_REQUESTS = int(os.getenv("GEMINI_MAX_DAILY_REQUESTS", "20"))
# 요일 버킷 수. 7 이면 일주일에 전 코퍼스를 정확히 1회전한다.
BUCKET_COUNT = 7
# 전역 시야 패스를 수행하는 요일 (6 = 일요일, datetime.weekday() 기준)
GLOBAL_PASS_WEEKDAY = 6

DOC_PERSONA = "You are a Senior Prompt Security Reviewer."
SCRIPT_PERSONA = "You are a Senior Code Security Reviewer."

# 전역 시야가 필요한 패스. 전문 대신 조항 인덱스를 입력한다.
GLOBAL_PASSES = [
    ("A-1", "[의미론적 충돌 & SSOT] 전역 룰(contexts/base.AGENTS.md)과 하위 SKILL.md / references 간의 "
            "의미론적 모순 및 SSOT 위반 지점을 지목하십시오."),
    ("A-4", "[크로스 스킬 파편화 & 개념 중복] 여러 SKILL.md 및 references 에 파편화되어 중복 정의된 규칙을 "
            "지목하고, SSOT 위임 구조로 정리하는 방안을 제시하십시오."),
]

# 핸드오프 프로토콜 패스. 대상 문서가 한정적이라 해당 문서 전문만 입력한다.
HANDOFF_PASS = (
    "A-3",
    "[멀티 에이전트 핸드오프] agent-handoff 프로토콜에서 Claude-Gemini 협업 시 거짓 성공 보고가 "
    "발생할 수 있는 지점을 조명하십시오.",
)
HANDOFF_GROUPS = ("agent-handoff", "ROOT")

# 문서 로컬 검사 패스. 요일별 스킬 청크 전문에 적용한다.
LOCAL_PASSES = [
    ("A-2", "[프롬프트 출처 & 규칙 승격] 056-rule-provenance-standard 의 실측 사건 병기 여부와 "
            "050-prompt-engineering-standard 의 긍정형 지시 준수 여부를 검토하십시오."),
    ("A-5", "[룰북 예외 & pre-flight 조항] EXCEPTION APPLIED 오버라이드 지시의 안전성과 문서 내 선언된 "
            "pre-flight-check 조항의 무결성을 검토하십시오."),
    ("A-7", "[AI 인지 환각 & 모호성 방지] 에이전트가 오해하거나 환각(Hallucination)을 일으킬 수 있는 "
            "모호한 서술 및 상충하는 지시어를 탐색하십시오."),
]

# 스크립트 코드군 패스. 코퍼스가 작아 통째로 입력하되 요일별로 1개씩 순회한다.
SCRIPT_PASSES = [
    ("B-1", "[setup.sh 롤백 & 복구 결함] 스크립트 중단 시 기존 환경 파괴 방지 및 cleanup 롤백 미흡 지점을 "
            "탐색하십시오."),
    ("B-2", "[포터블 환경 & OS/쉘 호환성] Linux/macOS/WSL 및 Bash/Zsh 구문 차이로 인한 오동작 위험을 "
            "탐색하십시오."),
    ("B-3", "[DX & 에러 복구 가이드 문구] 실행 실패 시 출력되는 메시지의 직관성과 복구 안내 문구를 "
            "검토하십시오."),
    ("B-4", "[비동기 런타임 레이스 & 쉘 정체] 비동기 실행 시 자원 경쟁(Race Condition) 및 PAGER 미설정으로 "
            "인한 쉘 멈춤(Hang) 지점을 탐색하십시오."),
]

# 조항 인덱스 추출 대상: 상위 헤딩, `- **[MUST] 조항명:**` 의 조항명, frontmatter 참조 선언.
# 조항 본문까지 실으면 인덱스가 전문보다 커지므로(2026-07-28 실측: 78,421 tok 으로 스킬 청크
# 전문의 3.2배) 이름만 남긴다.
HEADING_PATTERN = re.compile(r"^#{1,3} ")
CLAUSE_NAME_PATTERN = re.compile(r"^\s*[-*] \*\*(\[[^\]]+\][^*:]*)")
RETRY_DELAY_PATTERN = re.compile(r"retryDelay['\"]?\s*[:=]\s*['\"]?(\d+)s")
# 일 단위 할당량은 대기로 회복되지 않으므로 재시도 없이 중단해야 한다.
DAILY_QUOTA_HINTS = ("PerDay", "per day", "PerDayPerProject")


def dedupe_symlinks(paths: List[str]) -> List[str]:
    """심볼릭 링크와 그 원본이 함께 잡히면 원본만 남긴다.

    루트의 AGENTS.md / CLAUDE.md 는 contexts/dotfiles/SKILL.md 를 가리키므로, 그대로 두면
    같은 실체를 여러 벌 전송하고 서로 다른 요일 버킷에 배정되어 같은 문서를 두 번
    리뷰하게 된다.
    """
    real_targets = {os.path.realpath(p) for p in paths if not os.path.islink(p)}
    return [p for p in paths
            if not (os.path.islink(p) and os.path.realpath(p) in real_targets)]


def estimate_tokens(text: str) -> int:
    """예산 로깅용 근사치. 한글은 약 1.2자/토큰, ASCII 는 약 4자/토큰으로 계산한다."""
    non_ascii = sum(1 for ch in text if ord(ch) > 127)
    return int(non_ascii / 1.2 + (len(text) - non_ascii) / 4)


def scan_doc_groups() -> Dict[str, Dict[str, str]]:
    """문서를 스킬 디렉토리 단위로 그룹화하여 수집한다. (ROOT = 레포 루트 및 contexts 직속 문서)"""
    targets = set(glob.glob("*.md")) | set(glob.glob("contexts/**/*.md", recursive=True))
    groups: Dict[str, Dict[str, str]] = {}

    for path in dedupe_symlinks(sorted(targets)):
        if not os.path.isfile(path):
            continue
        parts = path.split("/")
        group = parts[1] if len(parts) > 2 and parts[0] == "contexts" else "ROOT"
        try:
            with open(path, "r", encoding="utf-8") as f:
                groups.setdefault(group, {})[path] = f.read()
        except OSError as e:
            print(f"[WARN] Failed to read doc {path}: {e}", file=sys.stderr, flush=True)

    return groups


def scan_script_files() -> Dict[str, str]:
    """쉘 및 파이썬 스크립트를 수집한다. 코퍼스가 작아 그룹 분할 없이 통째로 사용한다."""
    targets = set(glob.glob("**/*.sh", recursive=True)) | set(glob.glob("contexts/dotfiles/scripts/*.py"))
    files: Dict[str, str] = {}

    for path in dedupe_symlinks(sorted(targets)):
        if not os.path.isfile(path):
            continue
        try:
            with open(path, "r", encoding="utf-8") as f:
                files[path] = f.read()
        except OSError as e:
            print(f"[WARN] Failed to read script {path}: {e}", file=sys.stderr, flush=True)

    return files


def build_context_block(files: Dict[str, str]) -> str:
    """수집본을 파일 경로가 명시된 마크다운 블록으로 합성한다."""
    return "\n".join(f"### File: `{path}`\n```markdown\n{content}\n```\n"
                     for path, content in files.items())


def extract_index_line(raw: str) -> str:
    """인덱스에 실을 한 줄을 뽑는다. 해당 없으면 빈 문자열."""
    if HEADING_PATTERN.match(raw) or raw.startswith("references:"):
        return raw.strip()[:120]
    match = CLAUSE_NAME_PATTERN.match(raw)
    return f"- {match.group(1).strip()}" if match else ""


def build_clause_index(groups: Dict[str, Dict[str, str]]) -> str:
    """전역 패스용 저비용 입력. 본문을 버리고 파일 경로 + 헤딩 + 조항명만 남긴다."""
    lines: List[str] = []
    for group in sorted(groups):
        for path, content in groups[group].items():
            lines.append(f"## {path}")
            lines.extend(line for line in map(extract_index_line, content.splitlines()) if line)
    return "\n".join(lines)


def group_size(group: Dict[str, str]) -> int:
    return sum(len(content) for content in group.values())


def balance_buckets(groups: Dict[str, Dict[str, str]], count: int = BUCKET_COUNT) -> List[List[str]]:
    """스킬 그룹을 크기순으로 가장 작은 버킷에 배정하여 요일별 분량을 고르게 맞춘다."""
    buckets: List[List[str]] = [[] for _ in range(count)]
    sizes = [0] * count

    for name in sorted(groups, key=lambda g: -group_size(groups[g])):
        target = sizes.index(min(sizes))
        buckets[target].append(name)
        sizes[target] += group_size(groups[name])

    return buckets


_request_count = 0


def consume_request_budget(label: str) -> None:
    """RPD 는 대기로 회복되지 않으므로, 재시도까지 합산해 초과 직전에 스스로 중단한다."""
    global _request_count
    _request_count += 1
    if _request_count > MAX_DAILY_REQUESTS:
        raise RuntimeError(
            f"{label}: 일일 요청 예산 {MAX_DAILY_REQUESTS}회를 초과했습니다 "
            f"(재시도 포함 {_request_count}회째). RPD 소진을 피하기 위해 중단합니다."
        )


def canary_probe(client: Any, model_name: str) -> None:
    """대형 페이로드를 태우기 전에 키/모델/할당량 생존 여부를 최소 비용으로 확인한다."""
    print("[CANARY] 최소 프롬프트로 할당량 생존 여부를 확인합니다...", flush=True)
    consume_request_budget("CANARY")
    try:
        client.models.generate_content(
            model=model_name,
            contents="ping",
            config=types.GenerateContentConfig(temperature=0.0, max_output_tokens=16),
        )
    except APIError as e:
        print(f"[CANARY][FAIL] {e}", file=sys.stderr, flush=True)
        print("[CANARY][FAIL] 본 검사를 시작하지 않고 중단합니다. "
              f"모델명('{model_name}'), API 키, 프로젝트 할당량을 먼저 확인하십시오.",
              file=sys.stderr, flush=True)
        sys.exit(1)
    print("[CANARY] 통과. 본 검사를 시작합니다.", flush=True)


def call_gemini_with_retry(client: Any, model_name: str, prompt: str, label: str) -> str:
    """429 발생 시 응답 본문을 그대로 노출하고, retryDelay 가 있으면 그 값을 우선 준수한다."""
    for attempt in range(1, MAX_RETRIES + 1):
        consume_request_budget(label)
        try:
            response = client.models.generate_content(
                model=model_name,
                contents=prompt,
                config=types.GenerateContentConfig(temperature=0.2),
            )
            return response.text
        except APIError as e:
            detail = str(e)
            if not any(k in detail for k in ("429", "ResourceExhausted", "QuotaExceeded")):
                print(f"[ERROR] {label} API Error: {detail}", file=sys.stderr, flush=True)
                raise

            print(f"[RATE-LIMIT] {label} 429 ({attempt}/{MAX_RETRIES}): {detail}", flush=True)
            if any(hint in detail for hint in DAILY_QUOTA_HINTS):
                raise RuntimeError(
                    f"{label}: 일일 할당량(RPD) 소진으로 판단됩니다. 대기해도 회복되지 않으므로 중단합니다."
                ) from e

            match = RETRY_DELAY_PATTERN.search(detail)
            wait_sec = int(match.group(1)) + 5 if match else CALL_INTERVAL_SEC * attempt
            print(f"[RATE-LIMIT] {wait_sec}s 대기 후 재시도합니다.", flush=True)
            time.sleep(wait_sec)

    raise RuntimeError(f"{label}: 재시도 {MAX_RETRIES}회 후에도 429가 해소되지 않았습니다.")


def plan_daily_calls(doc_groups: Dict[str, Dict[str, str]],
                     script_files: Dict[str, str],
                     weekday: int,
                     day_index: int = None) -> Tuple[List[Tuple[str, str, str, str]], List[str]]:
    """오늘 수행할 호출 목록을 (라벨, 지시문, 컨텍스트, 페르소나) 튜플로 구성한다."""
    today_groups = balance_buckets(doc_groups)[weekday]
    today_docs = {path: content
                  for name in today_groups
                  for path, content in doc_groups[name].items()}
    chunk_context = build_context_block(today_docs)

    calls: List[Tuple[str, str, str, str]] = [
        (f"{pass_id} [{'+'.join(today_groups)}]", desc, chunk_context, DOC_PERSONA)
        for pass_id, desc in LOCAL_PASSES
    ]

    if weekday == GLOBAL_PASS_WEEKDAY:
        index_context = build_clause_index(doc_groups)
        calls.extend((f"{pass_id} [전역 조항 인덱스]", desc, index_context, DOC_PERSONA)
                     for pass_id, desc in GLOBAL_PASSES)

        handoff_docs = {path: content
                        for name in HANDOFF_GROUPS if name in doc_groups
                        for path, content in doc_groups[name].items()}
        calls.append((f"{HANDOFF_PASS[0]} [핸드오프 문서]", HANDOFF_PASS[1],
                      build_context_block(handoff_docs), DOC_PERSONA))

    # 요일(7)로 나누면 패스 수(4)와 주기가 어긋나 B-4 만 주 1회가 된다. 날짜 일련번호로
    # 순회하면 7 과 4 가 서로소이므로 4주에 걸쳐 네 패스가 각각 7회로 균등해진다.
    rotation = weekday if day_index is None else day_index
    script_id, script_desc = SCRIPT_PASSES[rotation % len(SCRIPT_PASSES)]
    calls.append((f"{script_id} [스크립트 전체]", script_desc,
                  build_context_block(script_files), SCRIPT_PERSONA))

    return calls, today_groups


def run_daily_review(client: Any, model_name: str,
                     calls: List[Tuple[str, str, str, str]],
                     scope_note: str, dry_run: bool = False) -> str:
    """계획된 호출을 간격을 두고 순차 실행한 뒤, 마지막 1회로 통합 보고서를 정제한다."""
    sections: List[str] = []

    for index, (label, desc, context, persona) in enumerate(calls, 1):
        tokens = estimate_tokens(context)
        print(f"[{index}/{len(calls)}] {label} (입력 약 {tokens:,} tokens)", flush=True)

        if dry_run:
            sections.append(f"### {label}\n(dry-run: 입력 약 {tokens:,} tokens)\n")
            continue

        prompt = (f"{persona}\n\n## Target\n{context}\n\n## Instruction\n{desc}\n"
                  f"발견 사항이 없으면 없다고 명시하고, 있으면 파일 경로와 근거를 함께 제시하십시오.\n")
        sections.append(f"### {label}\n{call_gemini_with_retry(client, model_name, prompt, label)}\n")
        print(f"[{index}/{len(calls)}] 완료. {CALL_INTERVAL_SEC}s 대기...", flush=True)
        time.sleep(CALL_INTERVAL_SEC)

    body = "\n\n".join(sections)
    header = f"# 심야 자동 리뷰 보고서\n\n- 모델: `{model_name}`\n- 검사 범위: {scope_note}\n"

    if dry_run:
        return f"{header}\n{body}"

    print(f"[{len(calls) + 1}/{len(calls) + 1}] Final: 통합 보고서 정제", flush=True)
    final_prompt = (
        f"You are a Senior Reviewer.\n\n## Today's Pass Results\n{body}\n\n"
        f"## Final Instruction\n"
        f"위 패스 결과를 종합하여 마크다운 보고서를 작성하십시오. "
        f"Summary, Critical Issues, Major Issues, Minor Improvements, Action Items 섹션을 포함하고 "
        f"가능한 경우 구체적 Diff 를 제시하십시오. 오늘 검사하지 않은 범위는 언급하지 마십시오."
    )
    return f"{header}\n{call_gemini_with_retry(client, model_name, final_prompt, 'Final')}"


def main() -> None:
    parser = argparse.ArgumentParser(description="Gemini Nightly Review")
    parser.add_argument("--dry-run", action="store_true", help="Gemini API 호출 없이 계획만 검증")
    parser.add_argument("--model", type=str, default=DEFAULT_MODEL, help="Gemini model name")
    parser.add_argument("--weekday", type=int, default=None,
                        help="요일 버킷 강제 지정 (0=월 ~ 6=일). 미지정 시 오늘 날짜 사용")
    args = parser.parse_args()

    doc_groups = scan_doc_groups()
    script_files = scan_script_files()
    today = datetime.date.today()
    weekday = args.weekday if args.weekday is not None else today.weekday()

    doc_count = sum(len(g) for g in doc_groups.values())
    print(f"[INFO] 문서 {doc_count}개 / {len(doc_groups)}개 그룹, 스크립트 {len(script_files)}개 수집.",
          flush=True)

    calls, today_groups = plan_daily_calls(doc_groups, script_files, weekday, today.toordinal())
    scope_note = f"{today.isoformat()} (weekday={weekday}) / 문서 그룹: {', '.join(today_groups)}"
    total_tokens = sum(estimate_tokens(context) for _, _, context, _ in calls)
    max_tokens = max(estimate_tokens(context) for _, _, context, _ in calls)
    planned_requests = len(calls) + 2  # 카나리아 1회 + 최종 정제 1회
    print(f"[INFO] 오늘 계획: {planned_requests}회 요청 (RPD 예산 {MAX_DAILY_REQUESTS}회), "
          f"입력 약 {total_tokens:,} tokens, 최대 단일 {max_tokens:,} tokens, "
          f"간격 {CALL_INTERVAL_SEC}s.", flush=True)
    print(f"[INFO] 검사 범위: {scope_note}", flush=True)

    if planned_requests > MAX_DAILY_REQUESTS:
        print(f"[ERROR] 계획된 요청 수가 RPD 예산을 이미 초과합니다. BUCKET_COUNT 를 늘리거나 "
              f"패스를 요일별로 더 분산하십시오.", file=sys.stderr, flush=True)
        sys.exit(1)

    if args.dry_run:
        print(run_daily_review(None, args.model, calls, scope_note, dry_run=True), flush=True)
        return

    if not HAS_GENAI_SDK:
        print("[ERROR] 'google-genai' 패키지가 필요합니다. 설치: pip install google-genai",
              file=sys.stderr, flush=True)
        sys.exit(1)

    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        print("[ERROR] GEMINI_API_KEY 환경 변수가 설정되지 않았습니다.", file=sys.stderr, flush=True)
        sys.exit(1)

    client = genai.Client(api_key=api_key)
    canary_probe(client, args.model)
    report = run_daily_review(client, args.model, calls, scope_note)

    os.makedirs("reviews", exist_ok=True)
    output_path = os.path.join("reviews", f"{today.isoformat()}.md")
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(report)
    print(f"[SUCCESS] 보고서를 {output_path} 에 기록했습니다.", flush=True)


if __name__ == "__main__":
    main()
