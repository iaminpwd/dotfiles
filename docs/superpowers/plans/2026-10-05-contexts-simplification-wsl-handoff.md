# WSL 회귀 검증 인수인계 프롬프트

아래 내용을 WSL에서 저장소를 연 에이전트에게 전달한다.

```text
이 저장소의 contexts 간소화 변경을 WSL에서 검증해줘.

먼저 현재 경로가 원하는 dotfiles 저장소인지 확인하고 git status --short를 확인해. 사용자 변경이 있으면 보존하고 덮어쓰지 마. main으로 이동할 수 있는 깨끗한 상태라면 git fetch origin, git switch main, git pull --ff-only를 순서대로 실행해. 깨끗하지 않으면 origin/main을 별도 worktree에서 검증해. git rev-parse HEAD로 검증 대상 커밋을 기록해.

docs/superpowers/plans/2026-10-05-contexts-simplification.md와 같은 폴더의 contexts-simplification-results.md를 읽어. 이번 변경은 전역 기본 지침과 도메인별 반복 절차를 줄인 문서 변경이다. scripts/tests/evals/examples, bin, ansible의 실행 및 배포 로직은 변경하지 않았다. 기존 기준 커밋은 de2e2d142a50b1485e2ef64b1340dece0ae080a6이다.

Windows Git Bash에서는 구조 검사와 27개 라우팅 정합성, 색인 회귀 7/7, provenance 9/9가 통과했다. 전체 회귀는 9개 스위트 중 8개 실패했다. shellcheck, trivy, sam, yq, jq 등 도구 누락과 플랫폼 차이가 있지만 모든 실패 원인이 확정된 것은 아니다. 프롬프트 예시 회귀는 33/35로 Good bash와 Good Dockerfile 검사가 각각 shellcheck/trivy 누락으로 실패했다. AIOps unavailable-tool-is-surfaced 실패(9/10)는 원본 기준 커밋에서도 동일했다. WSL 사용만으로 해결된다고 가정하지 마.

1. uname, Bash/Python 버전과 필수 도구 설치 상태를 확인해. mise 버전 정본은 stow/mise/.config/mise/config.toml이고 CI 검증 도구 선택은 .github/scripts/ci-tool-config.py를 참고해. 기존 설치 정책과 패키지 관리자 경로를 따른다. 버전을 임의로 바꾸거나 setup 전체를 검증 목적으로 실행하지 마. 필요한 의존성 누락은 명시하고 저장소 설정·자격 증명·배포 상태를 변경하지 않아도 가능한 검증부터 진행해.
2. 문서 구조 검사를 실행해: bash bin/linters/prompt-lint.sh. 이번에는 PROMPT_LINT_EXAMPLES=0을 설정하지 말고 실행 가능한 예시 검사도 포함해. just가 있으면 just test와 just verify를 실행해. 없으면 각각 bash bin/hooks/run-suite.sh contexts/*/tests/run.sh와 bash bin/hooks/run-suite.sh --pfc-args=--all로 실행해. 실패해도 다른 검사가 실행되도록 결과와 종료 코드를 따로 기록하고, 민감한 값은 로그에서 마스킹해.
3. 실패는 도구/환경 누락, 기존 기준 커밋에서도 재현되는 실패, 이번 변경에서만 재현되는 실패로 구분해. 같은 조건의 별도 worktree에서 기준 커밋을 비교해. 특히 AIOps unavailable-tool-is-surfaced를 재확인해. 테스트 기대값 완화나 검사 우회로 통과시키지 마.
4. 문서 변경으로 생긴 결함이 확인되면 고유 기술 조건과 경로/라우팅 계약을 유지하는 최소 수정으로 고쳐서 관련 검사를 다시 실행해. 환경 문제나 기존 실행 코드 결함은 증거를 보고하고 수정 범위를 먼저 설명해. 유료 모델 평가나 실제 클라우드 배포는 실행하지 마.
5. 최종 보고에는 대상 커밋, 실행 환경/도구 버전, 명령별 종료 코드, 스위트별 통과·실패 수, 기준 커밋 비교, 수정 파일과 미검증 범위를 포함해. 전체 회귀가 실제로 통과한 경우에만 통과라고 써. 결과 문서를 업데이트해도 되지만 커밋·푸시·머지는 별도 요청이 없으면 하지 마.
```
