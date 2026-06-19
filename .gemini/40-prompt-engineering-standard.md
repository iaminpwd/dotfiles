# AI 아키텍트 프롬프트 엔지니어링 마스터 가이드

본 가이드는 AI 에이전트가 다른 워크스페이스(예: `gemini/gcp`, `gemini/azure` 등)에 대한 **새로운 프롬프트 룰북(`.gemini/` 파일들)을 스스로 작성하거나 확장할 때 반드시 준수해야 하는 메타 설계 표준**입니다.

## 1. 프롬프트 구조 설계 (Domain Breakdown)
- **[NEVER] Monolithic Prompting (단일 프롬프트 금지):**
  > NEVER cram all rules into a single massive file like `GEMINI.md`. This scatters the AI's attention.
- **[MUST] Waterfall Modularity:** 반드시 생애주기 및 도메인별로 번호를 매겨 파일(모듈)을 분할하십시오. 
  - *예시:* `00-core`, `10-networking`, `20-iac`, `30-cicd`, `40-observability`, `50-incident-response` 등.

## 2. 멘탈 시뮬레이션 및 추상적 지시 금지 (Tool-Driven Rules)
- **[NEVER] Abstract Directives (추상적 지시 금지):**
  > NEVER write obvious, abstract (tutorial-level) directives like "pay attention to security" or "follow best practices when reviewing code" when writing new prompts.
- **[MUST] CLI Tool Mapping:** 모든 검증 지시는 **반드시 로컬 터미널 도구(CLI)와 명시적으로 매핑**되어야 합니다.
  - *Bad:* "컨테이너 이미지를 스캔하십시오."
  - *Good:* "로컬 터미널에 `trivy`가 있다면 `run_command`로 `trivy image` 스캐닝을 돌려 취약점을 1차 사전 검증하십시오."

## 3. 자율 주행 트리거 (`[Trigger]` 패턴) 설계
프롬프트 내에 에이전트의 자율적 행동(Autonomous Action)을 유발하는 트리거를 반드시 설계하십시오.
- **[Trigger: Before Destructive Action] Drift Check (편차 확인):**
  > Before applying high-impact changes like K8s manifests or Terraform code, you MUST design a trigger to visually confirm the drift using `diff` or `plan` commands (`helm-diff`, `terraform plan`).
- **[Trigger: After Code Change] Self-Correction (자가 치유):**
  > Immediately after modifying scripts or code, you MUST design a trigger to run a linter (`tflint`, `kube-linter`) and self-correct syntax errors (up to 3 times) without asking the user.

## 4. 엔터프라이즈 마인드셋 락킹 (Enterprise Focus)
새로운 클라우드나 기술 스택에 대한 프롬프트를 작성할 때, 다음의 엔터프라이즈 3대 철학을 강제로 탑재하십시오.
1. **Zero-Trust Security:** 단순 동작보다는 최소 권한(PoLP), 하드코딩 시크릿 차단(`trufflehog`), OPA 정책 검증 등.
2. **Day-2 Operations & SRE:** 장애가 발생했을 때 어떻게 임시 우회(Mitigation)를 하고 사후 분석(Post-Mortem)을 할 것인지.
3. **FinOps & Autoscaling:** 리소스를 무지성으로 늘리지 않고, 스팟 인스턴스 혼합, 자동화된 스케일링, `infracost`를 활용한 비용 분석 등을 우선시할 것.
