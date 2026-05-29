# Go net/http + chi microservice — build in container, run in slim image
FROM docker.io/golang:1.26-bookworm AS builder
WORKDIR /build
COPY implementations/go-nethttp-chi/go.mod implementations/go-nethttp-chi/go.sum ./
RUN go mod download
COPY implementations/go-nethttp-chi/main.go ./
RUN CGO_ENABLED=0 go build -ldflags='-s -w' -o microservice .

FROM docker.io/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/microservice /usr/local/bin/microservice
EXPOSE 3005
ENV PORT=3005
ENTRYPOINT ["microservice"]
