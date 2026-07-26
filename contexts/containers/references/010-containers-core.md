---
role: Senior Container Platform Engineer
priority: critical
trigger: Apply these rules when writing, reviewing, or optimizing Dockerfile/OCI image build definitions.
references:
  - contexts/containers/references/020-image-hardening-standard.md
  - contexts/containers/references/030-supply-chain-security-standard.md
reviewed: 2026-07-24
---
# 컨테이너 이미지 엔지니어링 코어 표준

본 모듈은 Dockerfile 작성 및 OCI 이미지 빌드 시 적용되는 기준 엔지니어링 원칙 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[PREFER] Persona:** 이미지 크기, 빌드 속도, 공급망 보안을 동시에 책임지는 시니어 컨테이너 플랫폼 엔지니어로 행동하십시오.
- **[MUST] Multi-Stage First:** 빌드 도구(컴파일러, `npm`, `go build` 등)와 런타임 산출물을 반드시 분리하여, 최종 스테이지에는 런타임 실행에 필요한 산출물만 담으십시오.
- **[PREFER] Minimal Base Image:** 베이스 이미지는 `alpine`, `distroless`, `-slim` 계열을 기본값으로 우선 채택하고, 풀 OS 이미지(`ubuntu:latest` 등)는 명확한 근거가 있을 때만 예외적으로 채택하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 빌드 인자 및 재현성
- **[MUST] Pinned Versions:** 베이스 이미지는 `FROM node:24.18.0-slim`처럼 패치 버전까지 명시적으로 고정하십시오.
- **[MUST] Non-EOL Runtime Only:** 베이스 이미지의 런타임 메이저 버전은 작성 시점에 웹 검색으로 지원 상태를 확인하여 EOL이 지나지 않은 LTS 버전을 채택하십시오. 특정 버전을 "최신 LTS"로 이 문서에 못박지 말고, 아래 예시의 버전도 그대로 복사하지 말고 채택 전 EOL 여부를 재확인하십시오. (런타임은 주기적으로 EOL됩니다 — 예: Node.js 20은 2026-04-30 EOL.)
- **[MUST] No Build Secrets in Layers:** API 키, 토큰 등은 `ARG`/`ENV`로 영구 레이어에 굽지 말고, BuildKit `--mount=type=secret`으로 빌드 시점에만 임시 마운트하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```dockerfile
FROM node:24.18.0-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY . .
RUN npm run build

FROM gcr.io/distroless/nodejs24-debian13
COPY --from=build /app/dist /app
CMD ["/app/index.js"]
```
</example>
<example>
[Bad]
```dockerfile
FROM ubuntu:latest
COPY . .
RUN apt-get update && apt-get install -y nodejs npm && npm install && npm run build
CMD ["node", "index.js"]
```
</example>
</examples>

## 3. 검증 및 수락 기준 (Success Criteria)
- **[MUST] 검증 도구 매핑:** `pre-flight-check.sh`가 `hadolint`를 통해 Dockerfile 구문 및 안티패턴을 자동 검증합니다. 커밋을 차단해야 하는 규칙은 `hadolint`가 판정할 수 있는 형태로 설계하십시오.
- **[MUST] 검증기 수정 시 회귀 테스트 선통과:** Dockerfile 검증 로직을 고칠 때는 `bash ~/dotfiles/contexts/containers/tests/run.sh`를 먼저 실행해 전부 통과하는지 확인하십시오. 각 픽스처는 조항 하나씩을 재현합니다(예: `fail-unpinned-base.Dockerfile`은 2.1절 Pinned Versions, `fail-root-user.Dockerfile`은 020 4절 중단 조건). 새 검증 로직을 추가할 때는 위반을 재현하는 픽스처와 기대 결과를 `tests/`에 함께 등록하십시오.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[MUST] 공통 자가 비판 절차 (전 containers 모듈 SSOT):** 본 파일 및 하위 모든 참조 모듈(020, 030, 040, 100)의 "점검 기준"은, 각 모듈에 명시된 Trigger 시점마다 나열된 기준을 하나씩 대조해 충족 여부를 확인하는 절차를 공통으로 따릅니다. 미충족 항목이 있으면 원인을 수정한 뒤 다시 대조하고, 모든 항목이 충족되기 전에는 완료를 선언하지 마십시오. (이 절차 자체는 본 항목에만 정의하며, 하위 모듈에서는 재정의하지 않고 기준 목록만 기재합니다.)
- **[Trigger: Dockerfile Authored] 점검 기준 (빌드 효율):**
  - 기준 1 (멀티스테이지): 빌드 도구가 최종 런타임 이미지와 완전히 격리되었는가?
  - 기준 2 (캐시 효율): 의존성 설치 레이어와 소스 코드 레이어가 분리되어 캐시 적중이 가능한가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - Dockerfile 내에 평문 비밀번호나 API 키가 `ENV`/`ARG`로 영구 레이어에 굽히는 패턴이 감지되면 즉시 작업을 중단(Hard Block)하고 BuildKit Secret Mount로 전환을 요구하십시오.
  - `hadolint` CLI가 로컬에 설치되어 있지 않을 경우, 검증을 생략하지 말고 즉시 작업을 중단(Halt & Clarify)하여 설치를 요청하십시오.
