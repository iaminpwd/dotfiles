# 010-containers-core.md 예시가 JSON 배열 형태(exec form)를 쓰는 이유를 고정한다.
# shell form 은 PID 1 이 셸이 되어 SIGTERM 이 애플리케이션에 전달되지 않으므로
# Graceful Shutdown 이 깨진다. hadolint DL3025 가 잡아야 한다.
FROM golang:1.24.5-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o /out/server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /out/server /app/server
USER 65532:65532
ENTRYPOINT /app/server
