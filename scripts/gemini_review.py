#!/usr/bin/env python3
import os
import sys
import time
import glob
import argparse
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

def scan_target_files() -> Tuple[Dict[str, str], Dict[str, str]]:
    """
    이원화 전수 스캔:
    - Group A: AI 룰북, SKILL.md, references/**/*.md 전체 프롬프트 문서 (104개)
    - Group B: setup.sh, pre-flight-check.sh, *.sh 및 파이썬 스크립트 코드 (16개)
    """
    doc_files = {}
    script_files = {}

    # Group A: 프롬프트 & 룰북 문서
    doc_targets = set()
    doc_targets.update(glob.glob("*.md"))
    doc_targets.update(glob.glob("contexts/**/*.md", recursive=True))
    doc_targets.update(glob.glob("references/**/*.md", recursive=True))

    for path in sorted(doc_targets):
        if os.path.isfile(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    doc_files[path] = f.read()
            except Exception as e:
                print(f"[WARN] Failed to read doc {path}: {e}", file=sys.stderr, flush=True)

    # Group B: 쉘 & 파이썬 스크립트 코드
    script_targets = set()
    script_targets.update(glob.glob("**/*.sh", recursive=True))
    script_targets.update(glob.glob("scripts/*.py"))

    for path in sorted(script_targets):
        if os.path.isfile(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    script_files[path] = f.read()
            except Exception as e:
                print(f"[WARN] Failed to read script {path}: {e}", file=sys.stderr, flush=True)

    return doc_files, script_files

def build_context_block(files: Dict[str, str]) -> str:
    """스캔된 수집본을 마크다운 코드 블록으로 합성"""
    blocks = []
    for path, content in files.items():
        blocks.append(f"### File: `{path}`\n```markdown\n{content}\n```\n")
    return "\n".join(blocks)

def call_gemini_with_retry(client: Any, model_name: str, prompt: str, max_retries: int = 3) -> str:
    """API 429 감지 시 백오프 대기 및 실시간 로그 출력"""
    for attempt in range(max_retries):
        try:
            response = client.models.generate_content(
                model=model_name,
                contents=prompt,
                config=types.GenerateContentConfig(
                    temperature=0.2,
                )
            )
            return response.text
        except APIError as e:
            if "429" in str(e) or "ResourceExhausted" in str(e) or "QuotaExceeded" in str(e):
                wait_sec = 45 * (attempt + 1)
                print(f"[RATE-LIMIT] 429 limit detected. Waiting {wait_sec}s for quota reset (Attempt {attempt+1}/{max_retries})...", flush=True)
                time.sleep(wait_sec)
            else:
                print(f"[ERROR] API Error encountered: {e}", file=sys.stderr, flush=True)
                raise e
    raise RuntimeError("Gemini API call failed after retries due to rate limits.")

def run_thorough_review(client: Any, model_name: str, doc_context: str, script_context: str, dry_run: bool = False) -> str:
    """
    [AI 특화 12회 정밀 심층 리뷰 - 시크릿 스캔 등 중복 제외]
    - Group A 7-Pass (AI 프롬프트, SSOT, 출처, 핸드오프, 파편화, 앵커 무결성, 환각 방지)
    - Group B 4-Pass (setup.sh 롤백, OS 호환성, DX 에러 문구, 비동기 런타임 레이스)
    - Final 1-Pass (통합 마크다운 보고서 review.md 생성)
    - 총 12회 호출로 1분당 토큰(TPM 25만)과 일일 횟수(RPD 20회) 한도를 100% 여유롭게 통과!
    """
    group_a_prompts = [
        "Pass A-1: [의미론적 충돌 & SSOT] 전역 룰(base.AGENTS.md)과 하위 SKILL.md/references 간의 의미론적 모순 및 SSOT 위반을 명시하십시오.",
        "Pass A-2: [프롬프트 출처 & 규칙 승격] 056-rule-provenance-standard 실측 사건 병기 여부와 050 긍정형 지시 준수 여부를 다루십시오.",
        "Pass A-3: [멀티 에이전트 핸드오프] agent-handoff 프로토콜 등 Claude-Gemini 협업 시 거짓 성공 보고 위험 지점을 조명하십시오.",
        "Pass A-4: [크로스 스킬 파편화 & 개념 중복] 여러 SKILL.md 및 references 에 파편화되어 중복 정의된 규칙 지점을 구체화하십시오.",
        "Pass A-5: [룰북 예외 & pre-flight 조항] EXCEPTION APPLIED 오버라이드 지시 안전성 및 룰북 내 선언된 pre-flight-check 조항 무결성을 검토하십시오.",
        "Pass A-6: [룰북 앵커 & cross-reference 무결성] references/ 문서 간에 링크된 파일 경로 및 # Realistic-Error-Handling 같은 앵커 참조 무결성을 검사하십시오.",
        "Pass A-7: [AI 인지 환각 & 모호성 방지] 에이전트가 오해하거나 환각(Hallucination)을 일으킬 수 있는 모호한 룰북 서술 및 상충하는 지시어를 탐색하십시오."
    ]

    group_b_prompts = [
        "Pass B-1: [setup.sh 롤백 & 복구 결함] setup.sh 등 스크립트 중단 시 기존 환경 파괴 방지 및 cleanup 롤백 미흡 지점을 탐색하십시오.",
        "Pass B-2: [포터블 환경 & OS/쉘 호환성] Linux/macOS/WSL 및 Bash/Zsh 쉘 구문 차이로 인한 스크립트 오동작 위험을 탐색하십시오.",
        "Pass B-3: [DX & 에러 복구 가이드 문구] 스크립트 실행 실패 시 사용자에게 출력되는 메시지의 직관성과 복구 안내 문구를 검토하십시오.",
        "Pass B-4: [비동기 런타임 레이스 & 쉘 정체] 스크립트 비동기 실행 시 자원 경쟁(Race Condition) 및 PAGER 미설정으로 인한 쉘 멈춤(Hang) 지점을 탐색하십시오."
    ]

    history_a = ""
    history_b = ""

    # Phase 1: Group A 문서군 검사 (7회)
    print("=== [PHASE 1] Group A (AI 프롬프트 & 룰북 문서군) 7-Pass 검사 시작 ===", flush=True)
    for i, pass_desc in enumerate(group_a_prompts, 1):
        print(f"[GROUP A {i}/7] Running: {pass_desc.split(']')[0]}]...", flush=True)
        if dry_run:
            print(f"  └> [DRY-RUN] Group A Pass {i} prompt built.", flush=True)
            time.sleep(0.05)
            last_a = f"Group A Pass {i} Output"
        else:
            prompt_a = f"You are a Senior Prompt Security Reviewer.\n\n## Target Documents (Group A)\n{doc_context}\n\n## Group A History\n{history_a}\n\n## Instruction\n{pass_desc}\n"
            last_a = call_gemini_with_retry(client, model_name, prompt_a)
            print(f"[GROUP A {i}/7] Completed. Waiting 15s...", flush=True)
            time.sleep(15)
        history_a += f"\n\n### Group A Pass {i} Output:\n{last_a}\n"

    # Phase 2: Group B 코드군 검사 (4회)
    print("\n=== [PHASE 2] Group B (쉘 & 파이썬 스크립트 코드군) 4-Pass 검사 시작 ===", flush=True)
    for i, pass_desc in enumerate(group_b_prompts, 1):
        print(f"[GROUP B {i}/4] Running: {pass_desc.split(']')[0]}]...", flush=True)
        if dry_run:
            print(f"  └> [DRY-RUN] Group B Pass {i} prompt built.", flush=True)
            time.sleep(0.05)
            last_b = f"Group B Pass {i} Output"
        else:
            prompt_b = f"You are a Senior Code Security Reviewer.\n\n## Target Scripts (Group B)\n{script_context}\n\n## Group B History\n{history_b}\n\n## Instruction\n{pass_desc}\n"
            last_b = call_gemini_with_retry(client, model_name, prompt_b)
            print(f"[GROUP B {i}/4] Completed. Waiting 15s...", flush=True)
            time.sleep(15)
        history_b += f"\n\n### Group B Pass {i} Output:\n{last_b}\n"

    # Phase 3: Final Pass - Group A + Group B 통합 마크다운 보고서 정제 (1회)
    print("\n=== [PHASE 3] Final Pass: 통합 보고서 정제 및 review.md 커밋 생성 ===", flush=True)
    if dry_run:
        print("  └> [DRY-RUN] Final report built successfully.", flush=True)
        return f"# 🌙 Gemini Nightly Review Report (12-Pass Thorough Verified)\n\nModel: `{model_name}`\nAll 12 calls prepared."

    final_prompt = (
        f"You are a Senior Reviewer.\n\n"
        f"## Group A (Prompts & Rules) Full Analysis:\n{history_a}\n\n"
        f"## Group B (Scripts & Codes) Full Analysis:\n{history_b}\n\n"
        f"## Final Instruction\n"
        f"Group A와 Group B의 모든 11개 패스 분석 결과를 종합하여 'review.md' 파일에 커밋할 최상의 마크다운 보고서를 작성하십시오. "
        f"Summary, Critical Issues, Major Issues, Minor Improvements, Action Items 섹션을 포함하고 구체적 Diff를 제시하십시오."
    )
    final_report = call_gemini_with_retry(client, model_name, final_prompt)
    print("[FINAL] Review report synthesis completed successfully!", flush=True)
    return final_report

def main():
    parser = argparse.ArgumentParser(description="Gemini Nightly Review")
    parser.add_argument("--dry-run", action="store_true", help="Run without calling Gemini API")
    parser.add_argument("--model", type=str, default=DEFAULT_MODEL, help="Gemini model name")
    args = parser.parse_args()

    doc_files, script_files = scan_target_files()
    doc_bytes = sum(len(v) for v in doc_files.values())
    script_bytes = sum(len(v) for v in script_files.values())

    print(f"[INFO] Scanned Group A (Docs/Prompts): {len(doc_files)} files ({doc_bytes} bytes).", flush=True)
    print(f"[INFO] Scanned Group B (Scripts/Codes): {len(script_files)} files ({script_bytes} bytes).", flush=True)

    doc_context = build_context_block(doc_files)
    script_context = build_context_block(script_files)

    if args.dry_run:
        print(f"[DRY-RUN] Validating Thorough 12-Pass prompt chain with model '{args.model}'...", flush=True)
        report = run_thorough_review(None, args.model, doc_context, script_context, dry_run=True)
        print(report, flush=True)
        return

    if not HAS_GENAI_SDK:
        print("[ERROR] 'google-genai' package is required for live API calls. Install with: pip install google-genai", file=sys.stderr, flush=True)
        sys.exit(1)

    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        print("[ERROR] GEMINI_API_KEY environment variable is not set.", file=sys.stderr, flush=True)
        sys.exit(1)

    client = genai.Client(api_key=api_key)
    report = run_thorough_review(client, args.model, doc_context, script_context)

    with open("review.md", "w", encoding="utf-8") as f:
        f.write(report)
    print("[SUCCESS] Nightly review report written to review.md", flush=True)

if __name__ == "__main__":
    main()
