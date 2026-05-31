# syntax=docker/dockerfile:1.7

# ── Builder stage ────────────────────────────────────────────────────────────
FROM oven/bun:1 AS builder

ARG OPENCHAMBER_VERSION
ARG TARGETARCH

WORKDIR /app

# Install build-time deps for native modules (e.g. better-sqlite3).
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

# Install deps (cache mount avoids re-downloading on repeat builds).
RUN --mount=type=cache,target=/root/.bun/install/cache,sharing=locked \
    bun install --frozen-lockfile

# Build web assets.
RUN bun run build:web

# ── Runtime stage ───────────────────────────────────────────────────────────
FROM oven/bun:1

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

# Core runtime deps. nodejs + npm needed for opencode-ai global install.
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

# Install pinned opencode-ai globally (cache mount avoids re-downloading on bumps).
RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    set -eux; \
    if [ -z "${OPENCODE_VERSION}" ]; then echo "OPENCODE_VERSION build-arg is required" >&2; exit 1; fi; \
    npm install -g "opencode-ai@${OPENCODE_VERSION}"; \
    opencode --version

# Copy OpenChamber exactly like upstream: root node_modules + workspace node_modules,
# then built artifacts. Preserves Bun's symlink structure because WORKDIR matches.
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages/web/node_modules ./packages/web/node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/packages/web/package.json ./packages/web/package.json
COPY --from=builder /app/packages/web/bin ./packages/web/bin
COPY --from=builder /app/packages/web/server ./packages/web/server
COPY --from=builder /app/packages/web/dist ./packages/web/dist

# Scripts/config that change most often; keep after heavy layers.
COPY root/ /

# Delete upstream bun user (UID 1000) to avoid conflict with our openchamber user.
RUN userdel bun 2>/dev/null || true \
    && groupdel bun 2>/dev/null || true \
    && chmod +x /usr/local/bin/openchamber-* \
    && groupadd -g 1000 openchamber \
    && useradd -u 1000 -g openchamber -d /config -s /usr/local/bin/openchamber-shell -M openchamber \
    && install -d -o openchamber -g openchamber -m 755 /config /workspace \
    && mkdir -p /ssh \
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

HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD curl -fsS --max-time 8 -o /dev/null "http://127.0.0.1:3000/health" || exit 1

ENTRYPOINT ["/init"]
