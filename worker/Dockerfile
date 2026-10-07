# syntax=docker/dockerfile:1

FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /out/worker ./cmd/worker

FROM alpine:3.20 AS runtime

RUN addgroup -g 1000 appuser \
    && adduser -D -u 1000 -G appuser appuser

COPY --from=build --chown=appuser:appuser /out/worker /usr/local/bin/worker

USER appuser

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
    CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:9090/healthz || exit 1

ENTRYPOINT ["/usr/local/bin/worker"]
