# Rust Axum microservice — build in container, run in slim image
FROM docker.io/rust:1.93-slim-bookworm AS builder
RUN apt-get update && apt-get install -y --no-install-recommends pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*
WORKDIR /build
COPY implementations/rust-axum/Cargo.toml implementations/rust-axum/Cargo.lock ./
COPY implementations/rust-axum/src ./src
RUN cargo build --release && strip target/release/microservice

FROM docker.io/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libssl3 && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/target/release/microservice /usr/local/bin/microservice
EXPOSE 3001
ENV PORT=3001
ENTRYPOINT ["microservice"]
