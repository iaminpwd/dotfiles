# 010-containers-core.md 2.1 Pinned Versions 재현(패키지 레벨). 버전 미고정
# 패키지 설치를 주입한 변형이며, hadolint DL3018 이 잡아야 한다.
FROM golang:1.24.5-alpine AS build
WORKDIR /src
RUN apk add --no-cache curl
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o /out/server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /out/server /app/server
USER 65532:65532
ENTRYPOINT ["/app/server"]
