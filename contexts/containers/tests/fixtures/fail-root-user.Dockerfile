# 020-image-hardening-standard.md 4절 중단 조건 재현: "최종 스테이지에 USER
# 지시어가 누락되어 컨테이너가 root(UID 0)로 실행되는 상태". USER 를 제거한
# 변형이며 trivy DS-0002 가 탐지해야 한다.
#
# 이 위반은 두 곳에서 서로 다른 강제력으로 검사된다: validate_security() 의 trivy
# misconfig 스캔(--exit-code 0, 경고 전용 — "탐지"만 검증)과, validate_docker() 의
# container-hardening-gate.sh(하드 블록 — 2026-08-04 도입. db-sg-checker.sh 와 같은
# 급의 오탐 거의 없는 기초 항목이라 다른 하드 게이트와 강제력을 맞췄다).
FROM golang:1.24.5-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o /out/server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /out/server /app/server
ENTRYPOINT ["/app/server"]
