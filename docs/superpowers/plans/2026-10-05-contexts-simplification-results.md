# contexts 간소화 실행 결과

작성일: 2026-10-05 · 기준 커밋: `de2e2d142a50b1485e2ef64b1340dece0ae080a6`

계획의 Task 1–5를 순서대로 반영했다. 문서 변경과 검토는 끝났고, 전체 회귀 검사는 미통과 상태다. 초기 실행은 격리된 작업 폴더에서 진행했다. 이후 사용자의 요청으로 GitHub 커밋·푸시·머지를 진행하며, WSL 전체 회귀 재검증은 별도 인수인계한다. 실제 환경 배포는 수행하지 않았다.

## 변경

1. 기존 구조와 검증 결과를 기록하고 격리된 Git worktree를 준비했다.
2. 전역 기본 지침을 줄이고 dotfiles 고유 경로·도구 정책·검사 명령을 로컬 스킬로 정리했다.
3. prompt-architect와 pre-flight-check 적용 범위를 좁히고 관련 검사 선택 기준을 정리했다.
4. 도메인 문서의 반복 절차·역할 메타데이터·설명용 예시를 줄였다. 기술 규칙과 실행 경계를 유지했다.
5. README와 색인을 동기화하고 정적 검사 및 회귀 검사, 별도 검토를 수행했다.

전역 기본 문서는 49줄에서 11줄로 줄었다. 동일한 기존 프롬프트 문서 70개(base, SKILL, references)의 전체 줄 수는 4,031줄에서 2,976줄로 줄었다(26.2% 감소). 전체 문서량 기준이며 실제 세션 주입량이나 토큰 절감 측정값은 아니다.

검토 과정에서 Terraform 상태 변경 전 plan 실행, EKS API 접근 제한, 운영 DB DDL 잠금 확인, 컨테이너 의존성 캐시 레이어 규칙을 명시적으로 복원했다. FinOps와 GitOps의 별도 보고 파일은 요청 시 작성하도록 문장을 일치시켰다. 후속 검토에서 이 지적 사항들의 해결을 확인했다.

## 검사 결과

| 검사 | 결과 |
|---|---|
| 프롬프트 구조·참조·색인 검사 | 통과. `PROMPT_LINT_EXAMPLES=0 QUIET=0 bash bin/linters/prompt-lint.sh`; 예시 실행 검사는 제외 |
| 라우팅 케이스 정합성 | 27건 통과. 실제 모델 라우팅 정확도 평가는 아님 |
| 색인 생성기 회귀 | 7/7 통과 |
| README 제외 디렉토리 회귀 | 통과 |
| provenance 회귀 | 9/9 통과 |
| 전체 스킬 회귀 | 9개 스위트 중 8개 실패, drawio 통과 |
| `git diff --check` | 통과 |
| 실행·배포·회귀 자산 변경 | bin, ansible, scripts, tests, evals, examples 변경 없음 |

전체 회귀는 Git Bash에서 `bash bin/hooks/run-suite.sh contexts/*/tests/run.sh`로 실행했다. `just`가 없어 동등한 레시피 명령을 사용했다. Windows 실행 환경에는 shellcheck, trivy, sam, yq, jq 등 필요한 도구가 없으며 플랫폼 차이로 인한 실패도 있다. 모든 실패의 원인을 개별 확정한 것은 아니다. AIOps의 unavailable-tool-is-surfaced 실패(9/10)는 원본 체크아웃에서도 동일하게 재현했다. 프롬프트 예시 회귀는 33/35이며 Good Dockerfile과 Good bash 검사는 각각 trivy와 shellcheck가 없어 실패했다.

실행 코드와 테스트는 그대로 보존했다. 전체 회귀 통과나 실제 에이전트 성능 개선은 주장하지 않는다. 유료 모델 비교 평가는 수행하지 않았다. 상세 실행 로그는 작업 폴더의 `.agent-state/contexts-simplification/`에 보관한다.

## 남은 확인

- 필요한 도구가 갖춰진 지원 환경에서 전체 회귀를 다시 실행한다.
- 실제 세션의 지침 주입량·불필요한 조회·작업 품질을 비교한다.
- WSL 재검증은 [인수인계 프롬프트](2026-10-05-contexts-simplification-wsl-handoff.md)를 따른다.
