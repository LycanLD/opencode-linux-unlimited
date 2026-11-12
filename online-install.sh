#!/usr/bin/env bash
# OpenCode Unlimited Linux - one-line bootstrap installer
#
# Downloads this repository (git clone, with a tarball fallback) and runs the
# full cross-distro installer. Everything is installed into the user's home.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/LycanLD/opencode-linux-unlimited/main/online-install.sh)
#   curl -fsSL https://raw.githubusercontent.com/LycanLD/opencode-linux-unlimited/main/online-install.sh | bash
#
# Private repository? Export a token first (needs "repo" scope):
#   GITHUB_TOKEN=ghp_xxx bash <(curl -fsSL ...)
#
# Environment overrides:
#   OPENCODE_REPO_URL     Git clone URL
#   OPENCODE_REPO_BRANCH  Branch to install (default: main)
#   GITHUB_TOKEN          Optional token for private repositories

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

REPO_SLUG="LycanLD/opencode-linux-unlimited"
REPO_BRANCH="${OPENCODE_REPO_BRANCH:-main}"
REPO_URL="${OPENCODE_REPO_URL:-https://github.com/${REPO_SLUG}.git}"

echo -e "${CYAN}${BOLD}=== OpenCode Unlimited Linux Bootstrap ===${NC}"

if [ "$(uname -s)" != "Linux" ]; then
    echo -e "${RED}[!] Error: this installer only supports Linux (detected: $(uname -s)).${NC}"
    exit 1
fi

if ! command -v bash >/dev/null 2>&1; then
    echo -e "${RED}[!] Error: bash is required.${NC}"
    exit 1
fi

if ! command -v tar >/dev/null 2>&1; then
    echo -e "${RED}[!] Error: tar is required.${NC}"
    echo -e "${YELLOW}    Debian/Ubuntu: sudo apt install tar | Fedora: sudo dnf install tar${NC}"
    exit 1
fi

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/opencode-bootstrap.XXXXXX" 2>/dev/null || true)
if [ -z "$TMP_DIR" ]; then
    TMP_DIR="${TMPDIR:-/tmp}/opencode-bootstrap.$$"
    mkdir -p "$TMP_DIR"
fi
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

SRC_DIR=""
TOKEN="${GITHUB_TOKEN:-}"

fetch_with_git() {
    command -v git >/dev/null 2>&1 || return 1
    local clone_url="$REPO_URL"
    if [ -n "$TOKEN" ]; then
        clone_url="https://x-access-token:${TOKEN}@github.com/${REPO_SLUG}.git"
    fi
    echo "[*] Cloning ${REPO_SLUG} (${REPO_BRANCH})..."
    GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$REPO_BRANCH" "$clone_url" "$TMP_DIR/src" >/dev/null 2>&1
}

fetch_with_curl() {
    command -v curl >/dev/null 2>&1 || return 1
    local archive="$TMP_DIR/repo.tar.gz"
    local url="https://codeload.github.com/${REPO_SLUG}/tar.gz/refs/heads/${REPO_BRANCH}"
    local auth=()
    if [ -n "$TOKEN" ]; then auth=(-H "Authorization: Bearer ${TOKEN}"); fi
    echo "[*] Downloading repository archive..."
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 ${auth[@]+"${auth[@]}"} "$url" -o "$archive"
    mkdir -p "$TMP_DIR/src"
    tar -xzf "$archive" -C "$TMP_DIR/src" --strip-components=1
}

fetch_with_wget() {
    command -v wget >/dev/null 2>&1 || return 1
    local archive="$TMP_DIR/repo.tar.gz"
    local url="https://codeload.github.com/${REPO_SLUG}/tar.gz/refs/heads/${REPO_BRANCH}"
    local auth=()
    if [ -n "$TOKEN" ]; then auth=(--header="Authorization: Bearer ${TOKEN}"); fi
    echo "[*] Downloading repository archive..."
    wget -q ${auth[@]+"${auth[@]}"} -O "$archive" "$url"
    mkdir -p "$TMP_DIR/src"
    tar -xzf "$archive" -C "$TMP_DIR/src" --strip-components=1
}

if fetch_with_git || fetch_with_curl || fetch_with_wget; then
    SRC_DIR="$TMP_DIR/src"
else
    echo -e "${RED}[!] Error: could not download the repository.${NC}"
    echo -e "${YELLOW}    Install 'git' or 'curl' (plus 'tar') and re-run.${NC}"
    if [ -z "$TOKEN" ]; then
        echo -e "${YELLOW}    If the repository is private, export GITHUB_TOKEN first.${NC}"
    fi
    exit 1
fi

if [ ! -f "$SRC_DIR/install-linux.sh" ]; then
    echo -e "${RED}[!] Error: install-linux.sh not found in the downloaded repository.${NC}"
    exit 1
fi

echo -e "${GREEN}[+] Repository ready. Starting full installer...${NC}"
echo ""
bash "$SRC_DIR/install-linux.sh" "$@"
