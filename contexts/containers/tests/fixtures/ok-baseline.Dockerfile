# 010-containers-core.md 2.1 절과 020-image-hardening-standard.md 2.1 절을 모두
# 갖춘 기준 Dockerfile. hadolint 지적 0건으로 통과해야 한다. 이 픽스처가 깨지면
# 룰북이 권장하는 Dockerfile 모양 자체가 검증기를 통과하지 못한다는 뜻이다.
# 나머지 fail-* 픽스처는 전부 이 파일에서 위반 1건만 주입한 변형이다.
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
ENTRYPOINT ["/app/server"]
