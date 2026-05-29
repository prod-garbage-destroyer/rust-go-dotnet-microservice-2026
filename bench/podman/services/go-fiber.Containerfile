# Go Fiber microservice — build in container, run in slim image
FROM docker.io/golang:1.26-bookworm AS builder
WORKDIR /build
COPY implementations/go-fiber/go.mod implementations/go-fiber/go.sum ./
RUN go mod download
COPY implementations/go-fiber/main.go ./
RUN CGO_ENABLED=0 go build -ldflags='-s -w' -o microservice .

FROM docker.io/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/microservice /usr/local/bin/microservice
EXPOSE 3002
ENV PORT=3002
ENTRYPOINT ["microservice"]
