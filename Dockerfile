# syntax=docker/dockerfile:1.7

# ----------------------------------------------------------------------
# Stage 1 — fetch and extract the Minecraft Education dedicated server
# bundle. By default we pull from Microsoft's official "always latest"
# redirect (https://aka.ms/downloadmee-linuxserver) as documented in:
# https://edusupport.minecraft.net/hc/en-us/articles/41757415076884
#
# For reproducible builds, pin to a specific version by overriding
# BUNDLE_URL to the resolved CDN URL (e.g. .../MinecraftEducation_LinuxDS_1.21.133.2.zip)
# and set BUNDLE_SHA256.
# ----------------------------------------------------------------------
FROM ubuntu:22.04 AS fetcher

ARG BUNDLE_URL=https://aka.ms/downloadmee-linuxserver
ARG BUNDLE_SHA256
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates curl unzip && \
    rm -rf /var/lib/apt/lists/*

# `bundle_auth` secret is consumed at build time only — never baked into
# a layer. Pass with:
#   echo "Bearer $TOKEN" | docker buildx build \
#       --secret id=bundle_auth,src=/dev/stdin ...
RUN --mount=type=secret,id=bundle_auth \
    set -eu; \
    if [ -z "${BUNDLE_URL:-}" ]; then \
        echo "ERROR: BUNDLE_URL build arg is required." >&2; \
        echo "       See README — host the dedicated server zip privately and pass its URL." >&2; \
        exit 1; \
    fi; \
    echo "Downloading bundle from $BUNDLE_URL"; \
    if [ -s /run/secrets/bundle_auth ]; then \
        printf 'header = "Authorization: %s"\n' "$(cat /run/secrets/bundle_auth)" > /tmp/curl.cfg; \
        curl -fsSL --config /tmp/curl.cfg -o /tmp/bundle.zip "$BUNDLE_URL"; \
        rm -f /tmp/curl.cfg; \
    else \
        curl -fsSL -o /tmp/bundle.zip "$BUNDLE_URL"; \
    fi; \
    if [ -n "${BUNDLE_SHA256:-}" ]; then \
        echo "${BUNDLE_SHA256}  /tmp/bundle.zip" | sha256sum -c -; \
    else \
        echo "WARNING: BUNDLE_SHA256 not set — skipping integrity check." >&2; \
    fi; \
    mkdir -p /tmp/extract /opt/mcedu; \
    unzip -q /tmp/bundle.zip -d /tmp/extract; \
    # Some bundles unzip flat, others nest under a single top-level dir
    # like MinecraftEducation_LinuxDS_1/. Handle both.
    entries="$(find /tmp/extract -mindepth 1 -maxdepth 1)"; \
    if [ "$(printf '%s\n' "$entries" | wc -l)" = "1" ] && [ -d "$entries" ]; then \
        src="$entries"; \
    else \
        src=/tmp/extract; \
    fi; \
    cp -a "$src/." /opt/mcedu/; \
    rm -rf /tmp/bundle.zip /tmp/extract; \
    test -f /opt/mcedu/bedrock_server_edu || { \
        echo "ERROR: bedrock_server_edu not found after extraction." >&2; \
        ls -la /opt/mcedu >&2; \
        exit 1; \
    }; \
    chmod 0755 /opt/mcedu/bedrock_server_edu; \
    # Persist the parsed MEE version (extracted from the resolved
    # filename) so it's available at runtime. Empty if unparseable.
    basename "$BUNDLE_URL" \
        | sed -nE 's/^MinecraftEducation_LinuxDS_([0-9.]+)\.zip$/\1/p' \
        > /opt/mcedu/.mee_version

# ----------------------------------------------------------------------
# Stage 2 — runtime image
# ----------------------------------------------------------------------
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libcurl4 \
        libssl3 \
        ca-certificates \
        tzdata \
        tini && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd -g 1000 mcedu && \
    useradd  -u 1000 -g 1000 -m -s /bin/bash mcedu && \
    mkdir -p /opt/mcedu /data && \
    chown -R mcedu:mcedu /opt/mcedu /data

COPY --from=fetcher --chown=mcedu:mcedu /opt/mcedu/ /opt/mcedu/
COPY --chown=root:root --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh

# Re-declare the build args in this stage so we can persist them as
# runtime ENV (they're inherited via build-arg propagation; the
# defaults here are only used if a caller doesn't pass them).
ARG BUNDLE_URL=https://aka.ms/downloadmee-linuxserver
ARG BUNDLE_SHA256=

# Build provenance — visible inside the container via `env`, `printenv`,
# or `echo $BUNDLE_URL` from any shell, including `docker exec`.
ENV BUNDLE_URL=${BUNDLE_URL} \
    BUNDLE_SHA256=${BUNDLE_SHA256}

USER mcedu
WORKDIR /data
VOLUME ["/data"]

# Default port from the shipped server.properties (20202/udp), plus
# 19132/udp which the server also binds for LAN visibility.
EXPOSE 20202/udp
EXPOSE 19132/udp

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
