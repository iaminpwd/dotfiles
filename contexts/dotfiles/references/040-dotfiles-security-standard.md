---
role: Senior Security Engineer
priority: high
trigger: Apply these rules ONLY when handling sensitive credentials, SSH private keys, or running security/secret scans.
references:
  - contexts/dotfiles/references/000-core.md
  - contexts/dotfiles/references/010-dotfiles-core-standard.md
---
# 컨텍스트 모듈: Dotfiles 환경 보안 및 시크릿(Secret) 통제 표준

본 모듈은 `dotfiles` 시크릿 안전을 보장하기 위한 시크릿 통제 아키텍처에 적용됨.

## 1. 핵심 설계 원칙
- **[MUST] Secret Isolation:** 자격 증명(패스워드, Access Key, PAT, SSH 키)은 저장소 트리 밖의 홈 디렉토리 전용 파일(`~/.zshrc.local`, `~/.gitconfig.local`)에 분리하고, Git으로 추적되는 파일(`zsh/.zshrc`, `setup.sh` 등)에는 환경 변수 참조 로직만 구현할 것.
- **[MUST] Respect Git Hooks:** 보안/린트 자동화 깃 훅(git hooks)이 실패하면 원인을 수정한 뒤 재커밋하여 반드시 통과시키십시오.
- **[MUST] Explicit Key Access Request:** `~/.ssh/id_rsa` 등 프라이빗 키 내용 열람이 필요한 경우, 반드시 사전에 사용자에게 명시적 승인을 요청하여 취득한 후 접근할 것.
- **[MUST] Sensitive Data Masking:** 로그, 디버그 출력, 에러 메시지는 물론 사용자와의 대화 답변과 예시 코드까지, 출력되는 모든 텍스트 영역에서 민감 데이터(토큰, 키, 패스워드)를 마스킹(`***`)하여 노출을 안전하게 격리할 것. 위 세 조항이 "어디에 저장하는가"를 통제하는 반면 이 조항은 "어디에 출력하는가"를 통제하므로, 저장소 밖으로 분리해 둔 시크릿도 대화나 로그에 인용되는 순간 유출된다는 점에서 별도 통제가 필요함. (`dotfiles` 스킬은 전역 룰을 전면 무효화하므로 base.AGENTS.md 7장의 동명 조항이 적용되지 않습니다. 그 공백을 이 조항이 메웁니다 — 2026-07-28 실측: 7장 4개 조항 중 이 항목만 승계 누락.)

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 셋업 코드의 스캐닝 자동화
- **[MUST] Mandatory Secret Scan:** 새로운 자격 증명 로직 추가 또는 원격 저장소에 Push하기 전, 로컬에 `trufflehog`나 `trivy`가 설치되어 있다면 터미널에서 실행하여 시크릿 하드코딩 여부를 검사할 것.
- **[MUST] Safe Git History Purge:** 실수로 유출된 시크릿이 깃 커밋 히스토리에 포함된 경우, `git-filter-repo`나 BFG Repo-Cleaner를 활용해 히스토리를 정리하도록 제안하되, `git push --force`는 반드시 사전에 사용자의 수동 승인을 받으십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```bash
# ~/.zshrc (Git으로 추적됨)
if [ -f ~/.zshrc.local ]; then
    source ~/.zshrc.local
fi

# ~/.zshrc.local (Git Ignore 처리됨)
export GITHUB_TOKEN="ghp_xxx..."
```
</example>
<example>
[Bad]
```bash
# ~/.zshrc (Git으로 추적됨)
export GITHUB_TOKEN="ghp_xxx..." # 평문 노출 (퍼블릭 저장소 유출 위험)
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 완료 조건 (Done when):** `trufflehog` 시크릿 스캔이 verified/unverified 합계 0건으로 통과되고, 자격 증명은 저장소 바깥의 홈 디렉토리 전용 파일(`~/.zshrc.local`, `~/.gitconfig.local`)에만 존재하여 `git status`에 나타나지 않음이 확인되어야 합니다.
- **[MUST] 검증 도구 매핑:** 지정된 린터 도구 또는 `pre-flight-check.sh`로 일괄 검증할 것. (이유: 구문 검증 강제)
## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[Trigger: Before Commit / File Authored] 점검 기준 (절차는 000-core.md의 공통 자가 비판 절차 참조):**
  - 기준 1 (시크릿 격리): AWS Access Key, PAT 토큰 등이 Git으로 추적되는 파일에 평문(Plaintext)으로 하드코딩되지 않았는가?
  - 기준 2 (로컬 전용 파일 분리): 민감 환경 변수가 `.zshrc.local` 등 `.gitignore` 등록 파일로 물리적으로 분리되었는가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - 스캔 중 시크릿 유출이 감지되면 즉각 작업을 중단(Hard Block)하고 사용자에게 해당 자격 증명의 즉각 파기(Revoke) 가이드를 제공할 것.
  - Git Hooks 우회를 목적으로 `git commit --no-verify` 명령 사용이 시도되면 즉시 중단하고 정상적인 커밋 검증 절차로 복귀할 것.
