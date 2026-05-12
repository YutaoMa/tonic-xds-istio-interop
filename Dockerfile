FROM rust:1 AS builder
WORKDIR /app
COPY . .
RUN cargo build --release -p tonic-xds --example greeter_server --example channel --features testutil

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/examples/greeter_server /usr/local/bin/
COPY --from=builder /app/target/release/examples/channel /usr/local/bin/xds-channel
CMD ["greeter_server"]
