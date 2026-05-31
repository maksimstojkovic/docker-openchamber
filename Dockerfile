# syntax=docker/dockerfile:1.7

# ── Builder stage ────────────────────────────────────────────────────────────
FROM oven/bun:1 AS builder

ARG OPENCHAMBER_VERSION
ARG TARGETARCH

WORKDIR /src

# Install build-time deps with explicit cleanup for minimal layer size.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl git \
        make g++ python3 \
        nodejs npm \
    && npm install -g node-gyp \
    && rm -rf /var/lib/apt/lists/*

# Download pinned upstream source.
RUN set -eux; \
    if [ -z "${OPENCHAMBER_VERSION}" ]; then echo "OPENCHAMBER_VERSION build-arg is required" >&2; exit 1; fi; \
    curl -fsSL --retry 5 --retry-all-errors \
        "https://github.com/openchamber/openchamber/archive/refs/tags/v${OPENCHAMBER_VERSION}.tar.gz" \
        | tar -xz --strip-components=1

# Install deps and build (cache mount speeds up repeat builds).
RUN --mount=type=cache,target=/root/.bun/install/cache,sharing=locked \
    bun install --frozen-lockfile && \
    bun run build:web

# ── Runtime stage ───────────────────────────────────────────────────────────
FROM debian:trixie-slim

ARG OPENCODE_VERSION
ARG TARGETARCH
ARG S6_OVERLAY_VERSION=3.2.0.2
ARG DEBIAN_FRONTEND=noninteractive

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/config \
    XDG_CONFIG_HOME=/config/.config \
    XDG_DATA_HOME=/config/.local/share \
    XDG_STATE_HOME=/config/.local/state \
    XDG_CACHE_HOME=/config/.cache \
    PUID=1000 \
    PGID=1000 \
    TZ=Etc/UTC \
    NPM_CONFIG_PREFIX=/config/.npm-global \
    PATH=/config/.npm-global/bin:/usr/local/bin:$PATH

# Core runtime + build tools for npm global installs (opencode-ai has native deps).
# We keep apt lists so we don't need apt-get update later; remove in the same layer.
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-${TARGETARCH} \
    --mount=type=cache,target=/var/lib/apt,sharing=locked,id=aptlists-${TARGETARCH} \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl tar xz-utils \
        bash tzdata \
        git openssh-client \
        nano vim \
        jq ripgrep fd-find \
        imagemagick graphviz \
        python3 python3-matplotlib python3-pil \
        nodejs npm \
        make g++ \
    && ln -sf /usr/bin/fdfind /usr/bin/fd \
    && sed -i 's|<policy domain="coder" rights="none" pattern="\(PDF\|PS\|PS2\|PS3\|EPS\|XPS\)" />|<policy domain="coder" rights="read\|write" pattern="\1" />|g' /etc/ImageMagick-6/policy.xml || true

# Install s6-overlay with retry for transient network failures.
RUN set -eux; \
    case "${TARGETARCH}" in \
        amd64)  S6_ARCH=x86_64 ;; \
        arm64)  S6_ARCH=aarch64 ;; \
        *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL --retry 5 --retry-all-errors \
        "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
        | tar -Jxpf - -C /; \
    curl -fsSL --retry 5 --retry-all-errors \
        "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" \
        | tar -Jxpf - -C /

# Install pinned opencode-ai globally (heavy layer first; cache across bumps).
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    set -eux; \
    if [ -z "${OPENCODE_VERSION}" ]; then echo "OPENCODE_VERSION build-arg is required" >&2; exit 1; fi; \
    npm install -g "opencode-ai@${OPENCODE_VERSION}"; \
    opencode --version

# Copy the entire built source tree so Bun's symlink structure stays intact.
COPY --from=builder /src /usr/local/lib/openchamber

# Scripts/config that change most often; keep after heavy layers.
COPY root/ /

# Create runtime user and directories.
RUN chmod +x /usr/local/bin/openchamber-* \
    && groupadd -g 1000 openchamber \
    && useradd -u 1000 -g openchamber -d /config -s /usr/local/bin/openchamber-shell -M openchamber \
    && install -d -o openchamber -g openchamber -m 755 /config /workspace \
    && mkdir -p /ssh \
    && ln -s /usr/local/lib/openchamber /src \
    && chmod +x \
        /etc/cont-init.d/* \
        /etc/s6-overlay/s6-rc.d/*/run

# OCI labels
LABEL org.opencontainers.image.title="docker-openchamber" \
      org.opencontainers.image.description="Self-hostable OpenChamber (OpenCode web UI) for ARM64/AMD64" \
      org.opencontainers.image.source="https://github.com/maksimstojkovic/docker-openchamber" \
      org.opencontainers.image.licenses="MIT"

EXPOSE 3000
VOLUME ["/config", "/workspace", "/ssh"]

# Health-check against the web UI so an unready container appears unhealthy early.
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD curl -fsS --max-time 8 -o /dev/null "http://127.0.0.1:3000/health" || exit 1

ENTRYPOINT ["/init"]
