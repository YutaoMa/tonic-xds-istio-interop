FROM rust:1 AS builder
WORKDIR /build
COPY . .
RUN cargo build --release --bins

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/target/release/tonic-xds-client /usr/local/bin/
COPY --from=builder /build/target/release/greeter_server /usr/local/bin/
CMD ["greeter_server"]
