# Cangmo runtime image. Build the Linux binary first:
#   cjpm build --target linux_x86_64
# then place it at target/release/bin/main.
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY target/release/bin/main /usr/local/bin/cangmo
COPY resources /app/resources
COPY themes /app/themes

RUN mkdir -p /app/data /app/data/uploads /app/data/logs /app/data/backups \
    && useradd --system --home /app --shell /usr/sbin/nologin cangmo \
    && chown -R cangmo:cangmo /app
USER cangmo

EXPOSE 8080
VOLUME ["/app/data"]
ENTRYPOINT ["cangmo", "serve", "--config", "/app/data/config.json"]
