# 020-image-hardening-standard.md 4절 중단 조건 재현: "최종 스테이지에 USER
# 지시어가 누락되어 컨테이너가 root(UID 0)로 실행되는 상태". USER 를 제거한
# 변형이며 trivy DS-0002 가 탐지해야 한다.
# 주의: pre-flight-check.sh 의 trivy misconfig 는 --exit-code 0 이라 커밋을 막지
# 않는다. 이 픽스처는 "차단"이 아니라 "탐지"만 검증한다.
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
