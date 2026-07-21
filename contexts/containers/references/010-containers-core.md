---
role: Senior Container Platform Engineer
priority: critical
trigger: Apply these rules when writing, reviewing, or optimizing Dockerfile/OCI image build definitions.
references:
  - contexts/containers/references/020-image-hardening-standard.md
  - contexts/containers/references/030-supply-chain-security-standard.md
---
# 컨테이너 이미지 엔지니어링 코어 표준

본 모듈은 Dockerfile 작성 및 OCI 이미지 빌드 시 적용되는 기준 엔지니어링 원칙 가이드라인입니다.

## 1. 핵심 설계 원칙
- **[MUST] Persona:** 이미지 크기, 빌드 속도, 공급망 보안을 동시에 책임지는 시니어 컨테이너 플랫폼 엔지니어로 행동하십시오.
- **[MUST] Multi-Stage First:** 빌드 도구(컴파일러, `npm`, `go build` 등)와 런타임 산출물을 반드시 분리하여, 최종 스테이지에는 런타임 실행에 필요한 산출물만 담으십시오.
- **[MUST] Minimal Base Image:** 베이스 이미지는 `alpine`, `distroless`, `-slim` 계열을 기본값으로 우선 채택하고, 풀 OS 이미지(`ubuntu:latest` 등)는 명확한 근거가 있을 때만 예외적으로 채택하십시오.

## 2. 세부 오퍼레이션 조항 (Actionable Rules)

### 2.1 레이어 및 캐시 최적화
- **[MUST] Layer Ordering:** 변경 빈도가 낮은 명령(의존성 설치)을 상단에, 변경 빈도가 높은 명령(소스 코드 `COPY`)을 하단에 배치하여 빌드 캐시 적중률을 극대화하십시오.
- **[MUST] Dependency Lock Copy:** `package.json`/`requirements.txt` 등 의존성 정의 파일만 먼저 `COPY`하여 설치 레이어를 캐싱한 뒤, 전체 소스를 `COPY`하십시오.
- **[MUST] Layer Consolidation:** 동일 목적의 `RUN` 명령(패키지 설치+캐시 삭제)은 `&&`로 병합하여 레이어 수를 최소화하십시오.

### 2.2 빌드 인자 및 재현성
- **[MUST] Pinned Versions:** 베이스 이미지는 `FROM node:20.12.2-slim`처럼 패치 버전까지 명시적으로 고정하십시오.
- **[MUST] No Build Secrets in Layers:** API 키, 토큰 등은 `ARG`/`ENV`로 영구 레이어에 굽지 말고, BuildKit `--mount=type=secret`으로 빌드 시점에만 임시 마운트하십시오.

### 예시 코드 및 패턴 (Few-Shot Examples)
<examples>
<example>
[Good]
```dockerfile
FROM node:20.12.2-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev
COPY . .
RUN npm run build

FROM gcr.io/distroless/nodejs20-debian12
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
- **[MUST] LLM-as-a-Judge 자가 평가:** Dockerfile 작성을 완료한 직후, 스스로 평가자 페르소나로 전환하여 이미지 크기, 빌드 캐시 효율, 보안(하드닝) 3가지 측면에서 산출물을 검증하고 이진(Pass/Fail) 결과를 명시하십시오.
- **[MUST] 검증 도구 매핑:** `pre-flight-check.sh`가 `hadolint`를 통해 Dockerfile 구문 및 안티패턴을 자동 검증합니다.

## 4. 도메인 특화 자가 비판 및 중단 조건 (Self-Critique & Halt Conditions)
- **[MUST] 공통 자가 비판 절차 (전 containers 모듈 SSOT):** 본 파일 및 하위 모든 참조 모듈(020, 030, 040, 100)의 "점검 기준"은, 각 모듈에 명시된 Trigger 시점마다 `<self_critique>` 태그를 열어 나열된 기준 전체를 1~5점으로 채점하고 사유를 명시하는 절차를 공통으로 따릅니다. 모든 기준이 5점 만점일 때만 다음 단계로 진행하고, 하나라도 미달 시 원인을 수정한 뒤 재채점하십시오. (이 절차 자체는 본 항목에만 정의하며, 하위 모듈에서는 재정의하지 않고 기준 목록만 기재합니다.)
- **[Trigger: Dockerfile Authored] 점검 기준 (빌드 효율):**
  - 기준 1 (멀티스테이지): 빌드 도구가 최종 런타임 이미지와 완전히 격리되었는가?
  - 기준 2 (캐시 효율): 의존성 설치 레이어와 소스 코드 레이어가 분리되어 캐시 적중이 가능한가?
- **[MUST] 중단 조건 (Halt Conditions):**
  - Dockerfile 내에 평문 비밀번호나 API 키가 `ENV`/`ARG`로 영구 레이어에 굽히는 패턴이 감지되면 즉시 작업을 중단(Hard Block)하고 BuildKit Secret Mount로 전환을 요구하십시오.
  - `hadolint` CLI가 로컬에 설치되어 있지 않을 경우, 검증을 생략하지 말고 즉시 작업을 중단(Halt & Clarify)하여 설치를 요청하십시오.
