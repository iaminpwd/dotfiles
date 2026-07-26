# 010-containers-core.md 2.1 Pinned Versions 재현: "베이스 이미지는 패치 버전까지
# 명시적으로 고정". 빌드 스테이지 태그를 latest 로 되돌린 변형이며,
# hadolint DL3007 이 잡아야 한다.
FROM golang:latest AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o /out/server ./cmd/server

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /out/server /app/server
USER 65532:65532
ENTRYPOINT ["/app/server"]
