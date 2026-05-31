#!/usr/bin/env bash
# Check the latest upstream openchamber and opencode releases against the
# pinned version files and emit machine-readable outputs for GitHub Actions.
#
# Outputs (when run under GH Actions):
#   openchamber_version  — newest upstream openchamber release version
#   opencode_version     — newest upstream opencode release version
#   openchamber_current  — value of .openchamber-version at script start
#   opencode_current     — value of .opencode-version at script start
#   update_needed        — "true" iff either upstream version differs

set -euo pipefail

OPENCHAMBER_REPO="openchamber/openchamber"
OPENCODE_REPO="anomalyco/opencode"

OPENCHAMBER_VERSION_FILE=".openchamber-version"
OPENCODE_VERSION_FILE=".opencode-version"

for file in "$OPENCHAMBER_VERSION_FILE" "$OPENCODE_VERSION_FILE"; do
    if [ ! -f "$file" ]; then
        echo "ERROR: $file not found in repo root" >&2
        exit 1
    fi
done

openchamber_current="$(tr -d '[:space:]' < "$OPENCHAMBER_VERSION_FILE")"
opencode_current="$(tr -d '[:space:]' < "$OPENCODE_VERSION_FILE")"

auth_header=()
if [ -n "${GITHUB_TOKEN:-}" ]; then
    auth_header=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

fetch_latest() {
    local repo="$1"
    local url="https://api.github.com/repos/${repo}/releases/latest"
    local response
    response="$(curl -fsSL "${auth_header[@]}" "$url")"
    local tag
    tag="$(printf '%s' "$response" | jq -r '.tag_name')"
    if [ -z "$tag" ] || [ "$tag" = "null" ]; then
        echo "ERROR: could not parse tag_name from $url" >&2
        exit 1
    fi
    printf '%s' "${tag#v}"
}

openchamber_latest="$(fetch_latest "$OPENCHAMBER_REPO")"
opencode_latest="$(fetch_latest "$OPENCODE_REPO")"

update_needed="false"
if [ "$openchamber_latest" != "$openchamber_current" ] || [ "$opencode_latest" != "$opencode_current" ]; then
    update_needed="true"
fi

# Verify openchamber source tarball exists (guards against partial releases).
if [ "$update_needed" = "true" ]; then
    tarball_url="https://github.com/${OPENCHAMBER_REPO}/archive/refs/tags/v${openchamber_latest}.tar.gz"
    if ! curl -fsI -o /dev/null "$tarball_url"; then
        echo "WARN: source tarball not yet available: $tarball_url" >&2
        update_needed="false"
    fi
fi

echo "openchamber_current=${openchamber_current}"
echo "openchamber_version=${openchamber_latest}"
echo "opencode_current=${opencode_current}"
echo "opencode_version=${opencode_latest}"
echo "update_needed=${update_needed}"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
    {
        echo "openchamber_current=${openchamber_current}"
        echo "openchamber_version=${openchamber_latest}"
        echo "opencode_current=${opencode_current}"
        echo "opencode_version=${opencode_latest}"
        echo "update_needed=${update_needed}"
    } >> "${GITHUB_OUTPUT}"
fi
