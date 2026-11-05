# One Dockerfile for every service: --build-arg SERVICE=<name> picks ./cmd/<name>.
# Stage 1: build a static binary (no cgo, so it runs on distroless/static)
FROM golang:1.27-alpine AS builder

ARG SERVICE

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY cmd ./cmd
COPY internal ./internal
RUN test -n "${SERVICE}" || (echo "build with --build-arg SERVICE=<name>" >&2 && exit 1)
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/app ./cmd/${SERVICE}

# Stage 2: runtime has only the binary + CA certs, runs as uid 65532
FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=builder /out/app /app

USER nonroot:nonroot

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/app", "-healthcheck"]

ENTRYPOINT ["/app"]
