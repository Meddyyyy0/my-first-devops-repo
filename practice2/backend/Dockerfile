# Dependencies are cached independently of application sources.
FROM golang:1.22-alpine AS builder
WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/app .
# No compiler or shell in the runtime; numeric non-root identity.
FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=builder /out/app /app/app
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/app/app"]
