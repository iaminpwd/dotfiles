# AI 아키텍트 프롬프트 엔지니어링 마스터 가이드

본 가이드는 AI 에이전트가 다른 워크스페이스(예: `gemini/gcp`, `gemini/azure` 등)에 대한 **새로운 프롬프트 룰북(`.gemini/` 파일들)을 스스로 작성하거나 확장할 때 반드시 준수해야 하는 메타 설계 표준**입니다.

## 1. 프롬프트 구조 설계 (Domain Breakdown)
- **[NEVER] Monolithic Prompting:** 모든 규칙을 하나의 거대한 파일(`GEMINI.md`)에 통째로 때려 넣지 마십시오. 이는 AI의 Attention을 분산시킵니다.
- **[MUST] Waterfall Modularity:** 반드시 생애주기 및 도메인별로 번호를 매겨 파일(모듈)을 분할하십시오. 
  - *예시:* `00-core`, `10-networking`, `20-iac`, `30-cicd`, `40-observability`, `50-incident-response` 등.

## 2. 멘탈 시뮬레이션 및 추상적 지시 금지 (Tool-Driven Rules)
- **[NEVER] Abstract Directives:** 새로운 프롬프트를 짤 때, "보안에 신경 쓰십시오", "코드를 리뷰할 때 베스트 프랙티스를 따르십시오" 와 같은 뻔하고 추상적인(Tutorial-level) 지시를 절대 작성하지 마십시오.
- **[MUST] CLI Tool Mapping:** 모든 검증 지시는 **반드시 로컬 터미널 도구(CLI)와 명시적으로 매핑**되어야 합니다.
  - *Bad:* "컨테이너 이미지를 스캔하십시오."
  - *Good:* "로컬 터미널에 `trivy`가 있다면 `run_command`로 `trivy image` 스캐닝을 돌려 취약점을 1차 사전 검증하십시오."

## 3. 자율 주행 트리거 (`[Trigger]` 패턴) 설계
프롬프트 내에 에이전트의 자율적 행동(Autonomous Action)을 유발하는 트리거를 반드시 설계하십시오.
- **[Trigger: Before Destructive Action] Drift Check:** K8s 매니페스트나 Terraform 코드 등 파급력이 큰 변경을 적용(Apply)하기 전에는, 무조건 `diff`나 `plan` 명령어(`helm-diff`, `terraform plan`)를 통해 시각적 편차를 확인받도록 트리거를 설계하십시오.
- **[Trigger: After Code Change] Self-Correction:** 스크립트나 코드를 수정한 직후, 사용자에게 묻지 않고 린터(`tflint`, `kube-linter`)를 돌려 문법 에러를 자가 치유(최대 3회)하도록 트리거를 설계하십시오.

## 4. 엔터프라이즈 마인드셋 락킹 (Enterprise Focus)
새로운 클라우드나 기술 스택에 대한 프롬프트를 작성할 때, 다음의 엔터프라이즈 3대 철학을 강제로 탑재하십시오.
1. **Zero-Trust Security:** 단순 동작보다는 최소 권한(PoLP), 하드코딩 시크릿 차단(`trufflehog`), OPA 정책 검증 등.
2. **Day-2 Operations & SRE:** 장애가 발생했을 때 어떻게 임시 우회(Mitigation)를 하고 사후 분석(Post-Mortem)을 할 것인지.
3. **FinOps & Autoscaling:** 리소스를 무지성으로 늘리지 않고, 스팟 인스턴스 혼합, 자동화된 스케일링, `infracost`를 활용한 비용 분석 등을 우선시할 것.
