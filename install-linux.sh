#!/usr/bin/env bash
# OpenCode Unlimited Linux Installer
# Multi-mode deployment: Unlimited Free Proxy + OpenRouter Autonomous Bridge
#
# Supported (x86_64 / aarch64):
#   - Arch Linux and derivatives        (pacman)
#   - Debian / Ubuntu and derivatives   (apt)
#   - Fedora / RHEL and derivatives     (dnf / yum)
#   - openSUSE / SLES                   (zypper)
#   - Alpine and other musl systems     (apk, best-effort via gcompat)
#
# Ported from opencode-termux-unlimited for native Linux (no glibc-runner,
# no PRoot, no Termux prefix). Installs entirely into the user's home directory.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}=== OpenCode Unlimited Linux Installer ===${NC}"

# Allow overriding the upstream repo used by `opencode update` / `opencode repair`.
REPO_RAW="${OPENCODE_REPO_RAW:-https://raw.githubusercontent.com/leangtg123-art/opencode-termux-unlimited/main}"
INSTALL_SCRIPT_URL="$REPO_RAW/install-linux.sh"
UNINSTALL_SCRIPT_URL="$REPO_RAW/uninstall-linux.sh"

OPENCODE2API_VER="v1.4.6"
OPENCODE_CLI_VER="1.19.5"

# ---------------------------------------------------------------------------
# 0. Platform / architecture detection
# ---------------------------------------------------------------------------
if [ "$(uname -s)" != "Linux" ]; then
    echo -e "${RED}[!] Error: This installer targets Linux (detected: $(uname -s)).${NC}"
    echo -e "${YELLOW}    On Android/Termux use install.sh instead.${NC}"
    exit 1
fi

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        GOARCH="amd64"
        NPM_PKG="opencode-linux-x64"
        ;;
    aarch64|arm64)
        GOARCH="arm64"
        NPM_PKG="opencode-linux-arm64"
        ;;
    *)
        echo -e "${RED}[!] Error: Architecture '$ARCH' is not supported (need x86_64 or aarch64).${NC}"
        exit 1
        ;;
esac
echo -e "${GREEN}[+] Platform: Linux $ARCH (engine arch: $GOARCH)${NC}"

# ---------------------------------------------------------------------------
# 1. Distribution + package manager detection
# ---------------------------------------------------------------------------
DISTRO_ID="unknown"
DISTRO_NAME="unknown"
if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release 2>/dev/null || true
    DISTRO_ID="${ID:-unknown}"
    DISTRO_NAME="${PRETTY_NAME:-${NAME:-$DISTRO_ID}}"
fi
echo -e "${GREEN}[+] Distribution: ${DISTRO_NAME}${NC}"

# Detect musl systems (Alpine et al.): the prebuilt OpenCode CLI is a glibc
# binary, so it needs a glibc compatibility layer to run there.
LIBC="glibc"
if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
    LIBC="musl"
elif ls /lib/ld-musl-*.so.1 >/dev/null 2>&1; then
    LIBC="musl"
fi

SUDO=""
if [ "$(id -u)" != "0" ]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    else
        echo -e "${YELLOW}[!] Warning: not running as root and 'sudo' is unavailable.${NC}"
        echo -e "${YELLOW}    Missing packages cannot be installed automatically.${NC}"
    fi
fi

if command -v pacman >/dev/null 2>&1; then
    PM="pacman"
elif command -v apt-get >/dev/null 2>&1; then
    PM="apt"
elif command -v dnf >/dev/null 2>&1; then
    PM="dnf"
elif command -v yum >/dev/null 2>&1; then
    PM="yum"
elif command -v zypper >/dev/null 2>&1; then
    PM="zypper"
elif command -v apk >/dev/null 2>&1; then
    PM="apk"
else
    PM="unknown"
fi
echo -e "${GREEN}[+] Package manager: ${PM}${NC}"

# Map generic dependency tokens to the actual package name per distro.
map_pkg() {
    local name="$1"
    case "$PM:$name" in
        pacman:python3) echo "python" ;;
        pacman:procps)  echo "procps-ng" ;;
        dnf:procps|yum:procps) echo "procps-ng" ;;
        *) echo "$name" ;;
    esac
}

pkg_install() {
    # $@ = generic package tokens
    local pkgs=()
    local p
    for p in "$@"; do
        pkgs+=("$(map_pkg "$p")")
    done
    [ ${#pkgs[@]} -eq 0 ] && return 0
    case "$PM" in
        pacman)
            $SUDO pacman -S --needed --noconfirm "${pkgs[@]}" \
                || $SUDO pacman -Sy --needed --noconfirm "${pkgs[@]}" ;;
        apt)
            # Non-interactive so piped installs (curl | bash) never hang.
            $SUDO env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get update -y || true
            $SUDO env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y \
                --no-install-recommends "${pkgs[@]}" ;;
        dnf)    $SUDO dnf install -y "${pkgs[@]}" ;;
        yum)    $SUDO yum install -y "${pkgs[@]}" ;;
        zypper) $SUDO zypper --non-interactive --auto-agree-with-licenses install "${pkgs[@]}" ;;
        apk)    $SUDO apk add --no-cache "${pkgs[@]}" ;;
        *)
            echo -e "${RED}[!] Unknown package manager. Please install manually: ${pkgs[*]}${NC}"
            return 1
            ;;
    esac
}

echo "[*] Checking prerequisite packages..."
NEEDED_PKGS=()
command -v curl    >/dev/null 2>&1 || NEEDED_PKGS+=("curl")
command -v jq      >/dev/null 2>&1 || NEEDED_PKGS+=("jq")
command -v python3 >/dev/null 2>&1 || NEEDED_PKGS+=("python3")
command -v tar     >/dev/null 2>&1 || NEEDED_PKGS+=("tar")
command -v gzip    >/dev/null 2>&1 || NEEDED_PKGS+=("gzip")
command -v lsof    >/dev/null 2>&1 || command -v fuser >/dev/null 2>&1 || NEEDED_PKGS+=("lsof")
if ! command -v pgrep >/dev/null 2>&1 || ! command -v pkill >/dev/null 2>&1; then
    NEEDED_PKGS+=("procps")
fi

if [ "$LIBC" = "musl" ]; then
    echo -e "${YELLOW}[!] musl libc detected (${DISTRO_NAME}).${NC}"
    echo -e "${YELLOW}    The prebuilt OpenCode CLI is glibc-linked; installing a compatibility layer.${NC}"
    if [ "$PM" = "apk" ]; then
        NEEDED_PKGS+=("gcompat" "libstdc++")
    fi
fi

CA_BUNDLE=""
for f in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt \
         /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem /usr/local/etc/openssl/cert.pem; do
    if [ -f "$f" ]; then CA_BUNDLE="$f"; break; fi
done
if [ -z "$CA_BUNDLE" ]; then
    NEEDED_PKGS+=("ca-certificates")
fi

if [ ${#NEEDED_PKGS[@]} -gt 0 ]; then
    echo "[*] Installing missing base utilities: ${NEEDED_PKGS[*]}"
    pkg_install "${NEEDED_PKGS[@]}" || true
fi

# Re-verify core tools (fail loudly if still missing).
for cmd in curl jq python3 tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}[!] Error: required command '$cmd' is unavailable.${NC}"
        echo -e "${YELLOW}    Install it with your package manager and re-run the installer.${NC}"
        echo -e "${YELLOW}    Debian/Ubuntu: sudo apt install curl jq python3 tar gzip lsof procps ca-certificates${NC}"
        exit 1
    fi
done

# Process management is optional; warn instead of blocking basic proxy use.
for cmd in pgrep pkill; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${YELLOW}[!] Warning: '$cmd' not found; process cleanup will be limited.${NC}"
        echo -e "${YELLOW}    Debian/Ubuntu: sudo apt install procps${NC}"
    fi
done

if [ -z "$CA_BUNDLE" ]; then
    for f in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt \
             /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem; do
        if [ -f "$f" ]; then CA_BUNDLE="$f"; break; fi
    done
fi

# ---------------------------------------------------------------------------
# 2. Directory layout
# ---------------------------------------------------------------------------
INSTALL_DIR="$HOME/.opencode-proxy"
BIN_DIR="$INSTALL_DIR/bin"
LOCAL_BIN="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/opencode"
BRIDGE_DIR="$HOME/.local/share/openrouter-bridge"
BRIDGE_CONFIG_DIR="$HOME/.config/openrouter-bridge"
BRIDGE_STATE_DIR="$HOME/.local/state/openrouter-bridge"

mkdir -p "$BIN_DIR" "$LOCAL_BIN" "$CONFIG_DIR" "$BRIDGE_DIR" "$BRIDGE_CONFIG_DIR" "$BRIDGE_STATE_DIR"

# Persist a copy of this installer so `opencode update`/`opencode repair` work offline.
if [ -f "$0" ] && [ "$(basename "$0")" != "bash" ] && [ "$(basename "$0")" != "sh" ]; then
    cp -f "$0" "$INSTALL_DIR/install-linux.sh" 2>/dev/null || true
    chmod +x "$INSTALL_DIR/install-linux.sh" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 3. Download and setup opencode2api engine
# ---------------------------------------------------------------------------
ENGINE_URL="https://github.com/jasonxu114514/opencode2api/releases/download/${OPENCODE2API_VER}/opencode2api_${OPENCODE2API_VER}_linux_${GOARCH}.tar.gz"

echo "[*] Downloading opencode2api engine (${OPENCODE2API_VER}, linux_${GOARCH})..."
TMP_ARCHIVE="${TMPDIR:-/tmp}/opencode2api.$$.tar.gz"
curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 20 "$ENGINE_URL" -o "$TMP_ARCHIVE"
# Upstream archives have shipped both a flat binary and a versioned subfolder.
tar -xzf "$TMP_ARCHIVE" -C "$BIN_DIR" --strip-components=1 "opencode2api_${OPENCODE2API_VER}_linux_${GOARCH}/opencode2api" 2>/dev/null \
    || tar -xzf "$TMP_ARCHIVE" -C "$BIN_DIR" 2>/dev/null \
    || true
rm -f "$TMP_ARCHIVE"
if [ ! -f "$BIN_DIR/opencode2api" ]; then
    echo -e "${RED}[!] Error: failed to extract the opencode2api engine.${NC}"
    exit 1
fi
chmod +x "$BIN_DIR/opencode2api"
echo -e "${GREEN}[+] opencode2api engine installed.${NC}"

# ---------------------------------------------------------------------------
# 4. Create daemon double-fork spawner
# ---------------------------------------------------------------------------
cat << 'EOF' > "$INSTALL_DIR/daemon_spawn.py"
#!/usr/bin/env python3
import os
import sys

def daemonize(cmd, log_file, pid_file):
    if os.fork() > 0:
        sys.exit(0)
    os.setsid()
    if os.fork() > 0:
        sys.exit(0)

    sys.stdout.flush()
    sys.stderr.flush()

    with open(os.devnull, 'r') as devnull:
        os.dup2(devnull.fileno(), sys.stdin.fileno())

    log_fd = open(log_file, 'a')
    os.dup2(log_fd.fileno(), sys.stdout.fileno())
    os.dup2(log_fd.fileno(), sys.stderr.fileno())

    with open(pid_file, 'w') as f:
        f.write(str(os.getpid()))

    try:
        os.execvp(cmd[0], cmd)
    except Exception as e:
        sys.stderr.write(f"Failed to exec {cmd}: {e}\n")
        sys.exit(1)

if __name__ == '__main__':
    if len(sys.argv) < 4:
        sys.exit(1)
    daemonize(sys.argv[3:], sys.argv[2], sys.argv[1])
EOF
chmod +x "$INSTALL_DIR/daemon_spawn.py"

# ---------------------------------------------------------------------------
# 5. Create Unlimited Proxy configuration (Port 8080)
# ---------------------------------------------------------------------------
cat << 'EOF' > "$INSTALL_DIR/config.json"
{
  "listen": "127.0.0.1:8080",
  "server_keys": [
    "local-test-key"
  ],
  "zen_keys": [],
  "go_keys": [],
  "anonymous": true,
  "warp": {
    "enabled": true,
    "pool_size": 6,
    "stack": "ipv6",
    "source_ipv6": ""
  },
  "proxies": [
    "direct"
  ],
  "proxyfile": "",
  "upstream": {
    "zen": "https://opencode.ai/zen",
    "go": "https://opencode.ai/zen/go",
    "anonymous": "https://opencode.ai/inference"
  },
  "retry": {
    "max_attempts": 6,
    "timeout_seconds": 180
  },
  "models": {
    "refresh_seconds": 300,
    "protocols": {},
    "free_only": true
  },
  "performance": {
    "max_idle_conns": 256,
    "max_idle_conns_per_host": 64,
    "max_conns_per_host": 0,
    "idle_conn_timeout_seconds": 60,
    "connect_timeout_seconds": 10,
    "failure_cooldown_seconds": 15,
    "attempt_timeout_seconds": 0,
    "first_event_timeout_seconds": 0
  },
  "logging": {
    "level": "info",
    "ring_size": 1000,
    "dump_request_bodies": false
  },
  "webui": {
    "enabled": true,
    "listen": "127.0.0.1:8081",
    "username": "admin",
    "password": "changeme-changeme",
    "session_ttl_minutes": 720
  }
}
EOF

# ---------------------------------------------------------------------------
# 6. Install opencode-proxy manager CLI
# ---------------------------------------------------------------------------
cat << 'EOF' > "$LOCAL_BIN/opencode-proxy"
#!/usr/bin/env bash
BASE_DIR="$HOME/.opencode-proxy"
BIN="$BASE_DIR/bin/opencode2api"
CONFIG="$BASE_DIR/config.json"
PID_FILE="$BASE_DIR/proxy.pid"
LOG_FILE="$BASE_DIR/proxy.log"
SPAWNER="$BASE_DIR/daemon_spawn.py"
API_URL="http://127.0.0.1:8080"
API_KEY="local-test-key"

get_pid() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi
    local found
    found=$(pgrep -f "$BIN" | head -n 1)
    if [ -n "$found" ]; then
        echo "$found" > "$PID_FILE"
        echo "$found"
        return 0
    fi
    return 1
}

detect_ca_bundle() {
    for f in "${SSL_CERT_FILE:-}" /etc/ssl/certs/ca-certificates.crt \
             /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem; do
        if [ -n "$f" ] && [ -f "$f" ]; then echo "$f"; return 0; fi
    done
    return 1
}

kill_all_proxies() {
    echo "[*] Forcefully terminating all proxy engines, daemons, and port listeners..."
    pkill -9 -f "opencode2api" 2>/dev/null || true
    pkill -9 -f "proxy.py" 2>/dev/null || true
    pkill -9 -f "openrouter-bridge" 2>/dev/null || true
    pkill -9 -f "bridge.py" 2>/dev/null || true
    pkill -9 -f "daemon_spawn.py" 2>/dev/null || true

    local port_pids
    port_pids=$(lsof -ti :8080,8081,8085 2>/dev/null || fuser 8080/tcp 8081/tcp 8085/tcp 2>/dev/null || true)
    if [ -n "$port_pids" ]; then
        kill -9 $port_pids 2>/dev/null || true
    fi

    rm -f "$PID_FILE" "$HOME/.opencode-proxy/proxy.pid" "$HOME/.config/openrouter-bridge/bridge.pid" "$HOME/.local/share/openrouter-bridge/bridge.pid" "$HOME/.local/state/openrouter-bridge/bridge.pid"

    # Self-heal corrupted OpenCode SQLite database
    python3 - << 'PY' 2>/dev/null || true
import os, sqlite3
db = os.path.expanduser("~/.local/share/opencode/opencode.db")
if os.path.isfile(db):
    try:
        conn = sqlite3.connect(db, timeout=1.0)
        conn.cursor().execute("SELECT count(*) FROM session;")
        conn.close()
    except Exception:
        try:
            os.rename(db, db + f".corrupted.{int(os.times()[4])}")
            for ext in ["-wal", "-shm"]:
                p = db + ext
                if os.path.exists(p): os.remove(p)
        except Exception:
            pass
PY

    sleep 0.5
    echo "[+] All proxy processes and port bindings have been completely terminated."
}

start_proxy() {
    if get_pid >/dev/null 2>&1; then
        if curl -s --max-time 1.5 http://127.0.0.1:8080/healthz >/dev/null 2>&1; then
            echo "[*] OpenCode Proxy is already running (PID: $(get_pid))"
            return 0
        else
            echo "[!] Detected dead or unresponsive proxy daemon (PID: $(get_pid)). Forcefully purging..."
            kill_all_proxies
        fi
    fi

    pkill -9 -f "proxy.py" 2>/dev/null || true
    pkill -9 -f "$BIN" 2>/dev/null || true
    rm -f "$PID_FILE"
    sleep 0.5

    local ca
    ca=$(detect_ca_bundle 2>/dev/null) && export SSL_CERT_FILE="$ca" || true

    echo "[*] Starting OpenCode Proxy daemon on 127.0.0.1:8080..."
    python3 "$SPAWNER" "$PID_FILE" "$LOG_FILE" "$BIN" -config "$CONFIG"
    sleep 2
    if get_pid >/dev/null 2>&1; then
        echo "[+] OpenCode Proxy started successfully (PID: $(get_pid))"
    else
        echo "[-] Failed to start OpenCode Proxy. Check logs at: $LOG_FILE"
        [ -f "$LOG_FILE" ] && tail -n 8 "$LOG_FILE"
        exit 1
    fi
}

stop_proxy() {
    kill_all_proxies
}

status_proxy() {
    local pid
    pid=$(get_pid 2>/dev/null) || true
    if [ -n "$pid" ]; then
        echo "[+] OpenCode Proxy: RUNNING (PID: $pid)"
        local health
        health=$(curl -s --max-time 2 "$API_URL/healthz" 2>/dev/null)
        if [ -n "$health" ]; then
            local warp_stat models_stat exposed_stat
            warp_stat=$(echo "$health" | jq -r '.warp | "\(.status) (active: \(.active), standby: \(.standby))"' 2>/dev/null)
            models_stat=$(echo "$health" | jq -r '.models.total' 2>/dev/null)
            exposed_stat=$(echo "$health" | jq -r '.models.exposed' 2>/dev/null)
            echo "    WARP Status : $warp_stat"
            echo "    Free Models : $exposed_stat active ($models_stat total upstream)"
            echo "    API Base    : $API_URL/v1"
            echo "    Dashboard   : http://127.0.0.1:8081"
        else
            echo "    API Check   : Initializing or unreachable"
        fi
    else
        echo "[-] OpenCode Proxy: STOPPED"
    fi
}

test_chat() {
    local model="${1:-deepseek-v4.1-flash-free}"
    echo "[*] Sending test prompt to '$model'..."
    curl -s -N -H "Authorization: Bearer $API_KEY" \
         -H "Content-Type: application/json" \
         -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Ping test.\"}],\"stream\":true}" \
         "$API_URL/v1/chat/completions" | while read -r line; do
             if [[ "$line" =~ ^data:\ (.*) ]]; then
                 local json_data="${BASH_REMATCH[1]}"
                 if [ "$json_data" = "[DONE]" ]; then
                     echo -e "\n[+] Stream completed."
                     break
                 fi
                 local content
                 content=$(echo "$json_data" | jq -r '.choices[0].delta.content // empty' 2>/dev/null)
                 if [ -n "$content" ]; then
                     echo -n "$content"
                 fi
             fi
         done
    echo ""
}

show_logs() {
    if [ -f "$LOG_FILE" ]; then
        tail -n 35 "$LOG_FILE"
    else
        echo "[-] No log file found."
    fi
}

case "$1" in
    start)          start_proxy ;;
    stop)           stop_proxy ;;
    kill|kill-all)  kill_all_proxies ;;
    restart)        kill_all_proxies; sleep 1; start_proxy ;;
    status)         status_proxy ;;
    test)           test_chat "$2" ;;
    logs)           show_logs ;;
    *)
        echo "Usage: opencode-proxy {start|stop|kill|restart|status|test [model]|logs}"
        exit 1
        ;;
esac
EOF
chmod +x "$LOCAL_BIN/opencode-proxy"

# ---------------------------------------------------------------------------
# 7. Install OpenRouter Bridge subsystem (Port 8085)
# ---------------------------------------------------------------------------
cat << 'EOF' > "$BRIDGE_DIR/bridge.py"
#!/usr/bin/env python3
"""
OpenCode Autonomous OpenRouter Gateway Bridge
Zero-latency HTTP/1.1 SSE streaming, smart multi-egress probing,
and header normalization for OpenCode.
"""

import sys
import os
import json
import time
import socket
import logging
import urllib.request
import urllib.error
from urllib.parse import urlparse
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn

CONFIG_PATH = os.path.expanduser("~/.config/openrouter-bridge/config.json")
LOG_PATH = os.path.expanduser("~/.local/state/openrouter-bridge/bridge.log")

def load_config():
    default_config = {
        "listen": "127.0.0.1",
        "port": 8085,
        "upstream_url": "https://openrouter.ai/api/v1",
        "proxies": [
            "http://127.0.0.1:2081",
            "http://127.0.0.1:8888",
            "direct"
        ],
        "timeout_seconds": 60,
        "retry_attempts": 3,
        "inject_headers": {
            "HTTP-Referer": "https://opencode.ai",
            "X-Title": "OpenCode Linux Autonomous Bridge"
        },
        "system_prompt_override": {
            "enabled": False,
            "mode": "replace",
            "prompt_file": "~/.config/openrouter-bridge/custom_system_prompt.md"
        }
    }
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                loaded = json.load(f)
                default_config.update(loaded)
        except Exception as e:
            sys.stderr.write(f"Warning: Failed reading config {CONFIG_PATH}: {e}\n")
    return default_config

config = load_config()

os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
logging.basicConfig(
    filename=LOG_PATH,
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S"
)
logger = logging.getLogger("OpenRouterBridge")

def is_port_open(host, port, timeout=0.08):
    try:
        with socket.create_connection((host, int(port)), timeout=timeout):
            return True
    except (socket.timeout, ConnectionRefusedError, OSError):
        return False

def select_working_egress():
    proxies = config.get("proxies", ["direct"])
    for p in proxies:
        if p == "direct":
            return None, "direct"
        parsed = urlparse(p)
        host = parsed.hostname or "127.0.0.1"
        port = parsed.port or 80
        if is_port_open(host, port):
            return p, f"proxy({p})"
    return None, "direct"

class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

class BridgeRequestHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format, *args):
        logger.info(f"{self.client_address[0]} - {format % args}")

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.end_headers()

    def do_GET(self):
        if self.path in ("/healthz", "/health"):
            proxy_url, egress_label = select_working_egress()
            payload = {
                "status": "ok",
                "ready": True,
                "service": "openrouter-bridge",
                "version": "1.0.0",
                "active_egress": egress_label,
                "target": config.get("upstream_url")
            }
            body = json.dumps(payload, indent=2).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        self._forward_request("GET")

    def do_POST(self):
        self._forward_request("POST")

    def _forward_request(self, method):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else None

        path = self.path
        if path.startswith("/v1/"):
            target_subpath = path[3:]
        elif path.startswith("/"):
            target_subpath = path
        else:
            target_subpath = "/" + path

        upstream_base = config.get("upstream_url", "https://openrouter.ai/api/v1").rstrip("/")
        upstream_url = upstream_base + target_subpath

        # Handle system prompt dump and custom override
        if method == "POST" and target_subpath == "/chat/completions" and body:
            try:
                payload = json.loads(body.decode("utf-8"))
                if "messages" in payload and isinstance(payload["messages"], list):
                    dump_file = os.path.expanduser("~/.config/openrouter-bridge/last_intercepted_prompt.md")
                    for msg in payload["messages"]:
                        if msg.get("role") == "system":
                            try:
                                with open(dump_file, "w", encoding="utf-8") as df:
                                    df.write(msg.get("content", ""))
                            except Exception:
                                pass
                            break

                    custom_prompt_file = os.path.expanduser("~/.config/openrouter-bridge/custom_system_prompt.md")
                    override_cfg = config.get("system_prompt_override", {})
                    if override_cfg.get("enabled", False) and os.path.exists(custom_prompt_file):
                        with open(custom_prompt_file, "r", encoding="utf-8") as pf:
                            custom_prompt = pf.read().strip()
                        if custom_prompt:
                            mode = override_cfg.get("mode", "replace")
                            found = False
                            for msg in payload["messages"]:
                                if msg.get("role") == "system":
                                    if mode == "replace":
                                        msg["content"] = custom_prompt
                                    elif mode == "prepend":
                                        msg["content"] = custom_prompt + "\n\n" + msg["content"]
                                    found = True
                                    break
                            if not found:
                                payload["messages"].insert(0, {"role": "system", "content": custom_prompt})

                            body = json.dumps(payload).encode("utf-8")
            except Exception as pe:
                logger.warning(f"Error handling request body: {pe}")

        req_headers = {}
        for k, v in self.headers.items():
            k_lower = k.lower()
            if k_lower not in ("host", "content-length", "connection", "accept-encoding"):
                req_headers[k] = v

        req_headers["Accept-Encoding"] = "identity"

        for ik, iv in config.get("inject_headers", {}).items():
            if ik not in req_headers:
                req_headers[ik] = iv

        if "Authorization" not in req_headers and "authorization" not in req_headers:
            env_key = os.environ.get("OPENROUTER_API_KEY", "") or config.get("default_api_key", "")
            if env_key:
                req_headers["Authorization"] = f"Bearer {env_key}"

        max_retries = config.get("retry_attempts", 3)
        for attempt in range(max_retries):
            proxy_url, egress_label = select_working_egress()
            opener = self._build_opener(proxy_url)
            req = urllib.request.Request(upstream_url, data=body, headers=req_headers, method=method)

            try:
                resp = opener.open(req, timeout=config.get("timeout_seconds", 60))
                self._stream_response(resp)
                return
            except urllib.error.HTTPError as e:
                err_body = e.read()
                self.send_response(e.code)
                for hk, hv in e.headers.items():
                    if hk.lower() in ("content-type", "x-openrouter-error-origin"):
                        self.send_header(hk, hv)
                self.send_header("Access-Control-Allow-Origin", "*")
                self.send_header("Content-Length", str(len(err_body)))
                self.end_headers()
                self.wfile.write(err_body)
                return
            except Exception as e:
                logger.warning(f"Attempt {attempt+1} via {egress_label} failed: {e}")
                time.sleep(0.5)

        self.send_response(502)
        self.send_header("Content-Type", "application/json")
        err_msg = json.dumps({"error": {"message": "All egress paths failed to reach upstream."}}).encode("utf-8")
        self.send_header("Content-Length", str(len(err_msg)))
        self.end_headers()
        self.wfile.write(err_msg)

    def _build_opener(self, proxy_url):
        if not proxy_url or proxy_url == "direct":
            return urllib.request.build_opener(urllib.request.ProxyHandler({}))
        return urllib.request.build_opener(urllib.request.ProxyHandler({"http": proxy_url, "https": proxy_url}))

    def _stream_response(self, resp):
        self.send_response(resp.status)
        is_sse = False
        content_type = ""
        for k, v in resp.headers.items():
            k_lower = k.lower()
            if k_lower == "content-type":
                content_type = v
                if "text/event-stream" in v:
                    is_sse = True
            if k_lower not in ("transfer-encoding", "connection"):
                self.send_header(k, v)

        self.send_header("Access-Control-Allow-Origin", "*")

        if is_sse:
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            while True:
                line = resp.readline()
                if not line:
                    break
                self.wfile.write(line)
                self.wfile.flush()
        else:
            body = resp.read()
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

def main():
    listen_host = config.get("listen", "127.0.0.1")
    listen_port = int(config.get("port", 8085))
    server = ThreadedHTTPServer((listen_host, listen_port), BridgeRequestHandler)
    print(f"OpenRouter Bridge running on http://{listen_host}:{listen_port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

if __name__ == "__main__":
    main()
EOF
chmod +x "$BRIDGE_DIR/bridge.py"

# ---------------------------------------------------------------------------
# 8. Install openrouter-bridge controller CLI
# ---------------------------------------------------------------------------
cat << 'EOF' > "$LOCAL_BIN/openrouter-bridge"
#!/usr/bin/env bash
BRIDGE_DIR="$HOME/.local/share/openrouter-bridge"
SCRIPT="$BRIDGE_DIR/bridge.py"
PID_FILE="$HOME/.local/state/openrouter-bridge/bridge.pid"
LOG_FILE="$HOME/.local/state/openrouter-bridge/bridge.log"
CONFIG_FILE="$HOME/.config/openrouter-bridge/config.json"
API_URL="http://127.0.0.1:8085"

get_pid() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            echo "$pid"
            return 0
        fi
    fi
    local found
    found=$(pgrep -f "$SCRIPT" | head -n 1)
    if [ -n "$found" ]; then
        echo "$found" > "$PID_FILE"
        echo "$found"
        return 0
    fi
    return 1
}

start_bridge() {
    if get_pid >/dev/null 2>&1; then
        echo "[*] OpenRouter Bridge is already running (PID: $(get_pid))"
        return 0
    fi
    mkdir -p "$(dirname "$PID_FILE")"
    echo "[*] Starting OpenRouter Bridge daemon on 127.0.0.1:8085..."
    nohup python3 "$SCRIPT" >> "$LOG_FILE" 2>&1 &
    local new_pid=$!
    echo "$new_pid" > "$PID_FILE"
    sleep 1

    local max_wait=5
    local waited=0
    while [ $waited -lt $max_wait ]; do
        if curl -s --max-time 1 "$API_URL/healthz" >/dev/null 2>&1; then
            local egress
            egress=$(curl -s "$API_URL/healthz" | jq -r '.active_egress // "direct"' 2>/dev/null)
            echo "[+] OpenRouter Bridge active (PID: $new_pid, Egress: $egress)"
            return 0
        fi
        sleep 1
        waited=$((waited + 1))
    done
    echo "[-] Bridge failed to start. Check logs at: $LOG_FILE"
    exit 1
}

stop_bridge() {
    local pid
    pid=$(get_pid 2>/dev/null) || true
    if [ -n "$pid" ]; then
        echo "[*] Stopping OpenRouter Bridge (PID: $pid)..."
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -9 "$pid" 2>/dev/null || true
        rm -f "$PID_FILE"
        echo "[+] Bridge stopped."
    else
        echo "[*] Bridge is not running."
    fi
}

status_bridge() {
    local pid
    pid=$(get_pid 2>/dev/null) || true
    if [ -n "$pid" ]; then
        echo "[+] OpenRouter Bridge: RUNNING (PID: $pid)"
        local health
        health=$(curl -s --max-time 2 "$API_URL/healthz" 2>/dev/null)
        if [ -n "$health" ]; then
            local egress target
            egress=$(echo "$health" | jq -r '.active_egress' 2>/dev/null)
            target=$(echo "$health" | jq -r '.target' 2>/dev/null)
            echo "    Active Egress: $egress"
            echo "    Target URL   : $target"
            echo "    Local Base   : $API_URL/v1"
        else
            echo "    Health Check : Initializing or unreachable"
        fi
    else
        echo "[-] OpenRouter Bridge: STOPPED"
    fi
}

test_chat() {
    local model="${1:-liquid/lfm-2.5-2.6b:free}"
    echo "[*] Testing completion through bridge with model '$model'..."
    curl -s -N -H "Content-Type: application/json" \
         -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Ping.\"}],\"stream\":true,\"max_tokens\":15}" \
         "$API_URL/v1/chat/completions" | while read -r line; do
             if [[ "$line" =~ ^data:\ (.*) ]]; then
                 local json_data="${BASH_REMATCH[1]}"
                 if [ "$json_data" = "[DONE]" ]; then
                     echo -e "\n[+] Stream completed successfully."
                     break
                 fi
                 local content
                 content=$(echo "$json_data" | jq -r '.choices[0].delta.content // empty' 2>/dev/null)
                 if [ -n "$content" ]; then
                     echo -n "$content"
                 fi
             fi
         done
    echo ""
}

show_logs() {
    if [ -f "$LOG_FILE" ]; then
        tail -n 35 "$LOG_FILE"
    else
        echo "[-] No log file found at $LOG_FILE"
    fi
}

case "$1" in
    start)   start_bridge ;;
    stop)    stop_bridge ;;
    restart) stop_bridge; sleep 1; start_bridge ;;
    status)  status_bridge ;;
    test)    test_chat "$2" ;;
    logs)    show_logs ;;
    *)
        echo "Usage: openrouter-bridge {start|stop|restart|status|test [model]|logs}"
        exit 1
        ;;
esac
EOF
chmod +x "$LOCAL_BIN/openrouter-bridge"

# ---------------------------------------------------------------------------
# 9. Create default bridge configuration
# ---------------------------------------------------------------------------
cat << 'EOF' > "$BRIDGE_CONFIG_DIR/config.json"
{
  "listen": "127.0.0.1",
  "port": 8085,
  "upstream_url": "https://openrouter.ai/api/v1",
  "proxies": [
    "http://127.0.0.1:2081",
    "http://127.0.0.1:8888",
    "direct"
  ],
  "timeout_seconds": 60,
  "retry_attempts": 3,
  "inject_headers": {
    "HTTP-Referer": "https://opencode.ai",
    "X-Title": "OpenCode Linux Autonomous Bridge"
  },
  "default_api_key": "",
  "system_prompt_override": {
    "enabled": false,
    "mode": "replace",
    "prompt_file": "~/.config/openrouter-bridge/custom_system_prompt.md"
  }
}
EOF
chmod 600 "$BRIDGE_CONFIG_DIR/config.json"

# ---------------------------------------------------------------------------
# 10. Download OpenCode CLI (monolithic glibc build, runs natively on Linux)
# ---------------------------------------------------------------------------
BIN_VALID=false
if [ -f "$LOCAL_BIN/opencode-bin" ]; then
    BIN_SIZE=$(wc -c < "$LOCAL_BIN/opencode-bin" 2>/dev/null || echo 0)
    if [ "$BIN_SIZE" -gt 50000000 ] && "$LOCAL_BIN/opencode-bin" --version >/dev/null 2>&1; then
        BIN_VALID=true
    else
        echo -e "${YELLOW}[!] Existing opencode-bin is corrupted or incomplete (${BIN_SIZE} bytes). Re-downloading clean build...${NC}"
        rm -f "$LOCAL_BIN/opencode-bin"
    fi
fi

if [ "$BIN_VALID" != "true" ]; then
    echo "[*] Downloading OpenCode CLI binary (v${OPENCODE_CLI_VER}, ${NPM_PKG})..."
    TMP_CLI="${TMPDIR:-/tmp}/opencode-cli.$$.tgz"
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 "https://registry.npmjs.org/${NPM_PKG}/-/${NPM_PKG}-${OPENCODE_CLI_VER}.tgz" -o "$TMP_CLI"
    tar -xzf "$TMP_CLI" -C "$LOCAL_BIN" --strip-components=2 package/bin/opencode
    mv "$LOCAL_BIN/opencode" "$LOCAL_BIN/opencode-bin"
    chmod +x "$LOCAL_BIN/opencode-bin"
    rm -f "$TMP_CLI"

    if ! "$LOCAL_BIN/opencode-bin" --version >/dev/null 2>&1; then
        echo -e "${RED}[!] Error: Downloaded opencode-bin failed to execute.${NC}"
    else
        echo -e "${GREEN}[+] OpenCode CLI binary verified and operational.${NC}"
    fi

    # Apply GLM 5.3 Reasoning Unlock patch (1:1 byte replacement)
    echo "[*] Applying GLM 5.3 reasoning capability patch..."
    python3 -c "
target = b'[\"glm-5.2\",\"glm-5-2\",\"glm-5p2\"]'
replacement = b'[\"glm-5.2\",\"glm-5.3\",\"glm-5p3\"]'
bin_path = '$LOCAL_BIN/opencode-bin'
with open(bin_path, 'r+b') as f:
    content = f.read()
    if target in content:
        assert len(target) == len(replacement)
        content = content.replace(target, replacement)
        f.seek(0)
        f.write(content)
        f.truncate()
        print('[+] GLM 5.3 reasoning unlocked.')
" || true
fi

# ---------------------------------------------------------------------------
# 11. Install Interactive Multi-Mode Launcher
# ---------------------------------------------------------------------------
cat << 'EOF' > "$LOCAL_BIN/opencode"
#!/usr/bin/env bash
# OpenCode Multi-Mode Launcher for Linux
# Mode 1: Unlimited Free Proxy
# Mode 2: Dual Gateway (Unlimited Proxy + OpenRouter Bridge)

set -e

LOCAL_BIN="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/opencode"
OPENROUTER_CONFIG="$HOME/.config/openrouter-bridge/config.json"
BRIDGE_CLI="$HOME/.local/bin/openrouter-bridge"
PROXY_CLI="$HOME/.local/bin/opencode-proxy"
OPENCODE_BIN="$HOME/.local/bin/opencode-bin"
INSTALL_DIR="$HOME/.opencode-proxy"
REPO_RAW="${OPENCODE_REPO_RAW:-https://raw.githubusercontent.com/leangtg123-art/opencode-termux-unlimited/main}"
INSTALL_SCRIPT_URL="${OPENCODE_INSTALL_URL:-$REPO_RAW/install-linux.sh}"
UNINSTALL_SCRIPT_URL="${OPENCODE_UNINSTALL_URL:-$REPO_RAW/uninstall-linux.sh}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

detect_ca_bundle() {
    for f in "${SSL_CERT_FILE:-}" /etc/ssl/certs/ca-certificates.crt \
             /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/ca-bundle.pem /etc/ssl/cert.pem; do
        if [ -n "$f" ] && [ -f "$f" ]; then echo "$f"; return 0; fi
    done
    return 1
}

jsonc_valid() {
    python3 - "$1" << 'PY' 2>/dev/null
import json, re, sys

def strip_jsonc(text):
    out = []
    i = 0
    n = len(text)
    in_str = False
    escape = False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if escape:
                escape = False
            elif c == '\\':
                escape = True
            elif c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        if c == '/' and i + 1 < n and text[i+1] == '/':
            while i < n and text[i] not in ('\n', '\r'):
                i += 1
            continue
        if c == '/' and i + 1 < n and text[i+1] == '*':
            i += 2
            while i + 1 < n and not (text[i] == '*' and text[i+1] == '/'):
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1
    return re.sub(r',(\s*[}\]])', r'\1', ''.join(out))

with open(sys.argv[1], 'r', encoding='utf-8') as f:
    raw = f.read()
json.loads(strip_jsonc(raw))
PY
}

run_installer() {
    # Prefer the locally cached installer (works offline), fall back to upstream.
    if [ -f "$INSTALL_DIR/install-linux.sh" ]; then
        bash "$INSTALL_DIR/install-linux.sh"
    else
        curl -sSL "$INSTALL_SCRIPT_URL" | bash
    fi
}

run_doctor() {
    echo -e "${CYAN}${BOLD}=== OpenCode Linux System Diagnostics (Doctor) ===${NC}\n"
    local issues=0

    echo -n "[*] Checking system architecture... "
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64|aarch64|arm64) echo -e "${GREEN}OK ($ARCH)${NC}" ;;
        *) echo -e "${RED}FAIL (Unsupported: $ARCH)${NC}"; issues=$((issues + 1)) ;;
    esac

    echo -n "[*] Checking core utilities (curl/jq/python3)... "
    if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}MISSING (install curl, jq, python3)${NC}"
        issues=$((issues + 1))
    fi

    echo -n "[*] Checking SSL root certificates... "
    if detect_ca_bundle >/dev/null 2>&1; then
        echo -e "${GREEN}OK ($(detect_ca_bundle))${NC}"
    else
        echo -e "${RED}MISSING (install ca-certificates)${NC}"
        issues=$((issues + 1))
    fi

    echo -n "[*] Checking OpenCode database integrity... "
    local db_file="$HOME/.local/share/opencode/opencode.db"
    if [ -f "$db_file" ]; then
        if python3 -c "
import sqlite3, sys
try:
    conn = sqlite3.connect('$db_file', timeout=1.0)
    cur = conn.cursor()
    cur.execute('SELECT count(*) FROM session;')
    conn.close()
    sys.exit(0)
except Exception:
    sys.exit(1)
" 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${YELLOW}CORRUPTED (Auto-repair available)${NC}"
            issues=$((issues + 1))
        fi
    else
        echo -e "${GREEN}CLEAN${NC}"
    fi

    echo -n "[*] Checking OpenCode binary... "
    if [ -f "$OPENCODE_BIN" ]; then
        if "$OPENCODE_BIN" --version >/dev/null 2>&1; then
            VER=$("$OPENCODE_BIN" --version 2>/dev/null | tr -d '\r\n')
            echo -e "${GREEN}VALID (v$VER)${NC}"
        else
            echo -e "${RED}CORRUPTED (Run: opencode repair)${NC}"
            issues=$((issues + 1))
        fi
        echo -n "[*] Checking GLM 5.3 reasoning patch... "
        if python3 -c "
with open('$OPENCODE_BIN', 'rb') as f:
    data = f.read()
target = b'[\"glm-5.2\",\"glm-5.3\",\"glm-5p3\"]'
exit(0 if target in data else 1)
" 2>/dev/null; then
            echo -e "${GREEN}ACTIVE (Unlocked)${NC}"
        else
            echo -e "${YELLOW}NOT PATCHED${NC}"
        fi
    else
        echo -e "${RED}MISSING ($OPENCODE_BIN)${NC}"
        issues=$((issues + 1))
    fi

    echo -n "[*] Checking launcher/wrapper integrity... "
    if [ -L "$LOCAL_BIN/opencode" ]; then
        local tgt; tgt=$(readlink "$LOCAL_BIN/opencode" 2>/dev/null || true)
        echo -e "${YELLOW}SYMLINK -> $tgt (expected a script)${NC}"
    elif [ -f "$LOCAL_BIN/opencode" ]; then
        if head -c 4 "$LOCAL_BIN/opencode" 2>/dev/null | grep -q "ELF"; then
            echo -e "${RED}HIJACKED BY RAW ELF (Run: opencode repair)${NC}"
            issues=$((issues + 1))
        else
            echo -e "${GREEN}OK (Wrapper script)${NC}"
        fi
    else
        echo -e "${RED}MISSING ($LOCAL_BIN/opencode)${NC}"
        issues=$((issues + 1))
    fi

    echo -n "[*] Checking for conflicting 'opencode' on PATH... "
    local which_oc; which_oc=$(command -v opencode 2>/dev/null || true)
    if [ -n "$which_oc" ] && [ "$which_oc" != "$LOCAL_BIN/opencode" ]; then
        echo -e "${YELLOW}$which_oc (ensure ~/.local/bin precedes it in PATH)${NC}"
    else
        echo -e "${GREEN}OK${NC}"
    fi

    echo -n "[*] Checking Unlimited Proxy (127.0.0.1:8080)... "
    if curl -s --max-time 1.5 http://127.0.0.1:8080/healthz >/dev/null 2>&1; then
        WARP_STAT=$(curl -s http://127.0.0.1:8080/healthz | jq -r '.warp.status // "unknown"' 2>/dev/null)
        MODELS_COUNT=$(curl -s http://127.0.0.1:8080/healthz | jq -r '.models.exposed // 0' 2>/dev/null)
        echo -e "${GREEN}RUNNING (WARP: $WARP_STAT, Models: $MODELS_COUNT)${NC}"
    else
        echo -e "${YELLOW}STOPPED / UNREACHABLE${NC}"
    fi

    echo -n "[*] Checking OpenRouter Bridge (127.0.0.1:8085)... "
    if curl -s --max-time 1.5 http://127.0.0.1:8085/healthz >/dev/null 2>&1; then
        EGRESS=$(curl -s http://127.0.0.1:8085/healthz | jq -r '.active_egress // "direct"' 2>/dev/null)
        echo -e "${GREEN}RUNNING (Egress: $EGRESS)${NC}"
    else
        echo -e "${YELLOW}STOPPED / STANDBY${NC}"
    fi

    echo -n "[*] Checking DNS resolution (1.1.1.1)... "
    if python3 -c "import socket; socket.create_connection(('1.1.1.1', 53), timeout=1.0)" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}UNREACHABLE (check your network / /etc/resolv.conf)${NC}"
        issues=$((issues + 1))
    fi

    for cfgfile in "$CONFIG_DIR/opencode.jsonc" "$CONFIG_DIR/opencode-unlimited.jsonc"; do
        echo -n "[*] Validating $(basename "$cfgfile")... "
        if [ -f "$cfgfile" ]; then
            if jsonc_valid "$cfgfile"; then
                echo -e "${GREEN}VALID${NC}"
            else
                echo -e "${RED}SYNTAX ERROR${NC}"
                issues=$((issues + 1))
            fi
        else
            echo -e "${YELLOW}NOT FOUND${NC}"
        fi
    done

    echo ""
    if [ $issues -eq 0 ]; then
        echo -e "${GREEN}${BOLD}[✓] All core systems operational.${NC}"
    else
        echo -e "${RED}${BOLD}[!] Found $issues potential issue(s).${NC}"
    fi
    exit $issues
}

repair_opencode_db() {
    python3 - << 'PY' 2>/dev/null || true
import os, sqlite3

db_path = os.path.expanduser("~/.local/share/opencode/opencode.db")
if os.path.isfile(db_path):
    corrupted = False
    if os.path.getsize(db_path) == 0:
        corrupted = True
    else:
        try:
            conn = sqlite3.connect(db_path, timeout=1.0)
            cur = conn.cursor()
            cur.execute("SELECT count(*) FROM session;")
            dead = [r[0] for r in cur.execute("SELECT DISTINCT session_id FROM message WHERE data LIKE '%Free usage limit%'").fetchall()]
            for sid in dead:
                cur.execute("DELETE FROM session WHERE id = ?;", (sid,))
                cur.execute("DELETE FROM session_message WHERE session_id = ?;", (sid,))
                cur.execute("DELETE FROM message WHERE session_id = ?;", (sid,))
                cur.execute("DELETE FROM part WHERE session_id = ?;", (sid,))
            if dead:
                conn.commit()
            conn.close()
        except Exception:
            corrupted = True
    if corrupted:
        bak = db_path + f".corrupted.{int(os.times()[4])}"
        try:
            os.rename(db_path, bak)
            for ext in ["-wal", "-shm"]:
                f = db_path + ext
                if os.path.exists(f):
                    os.remove(f)
            print("[+] Repaired corrupted OpenCode database (old backed up).")
        except Exception:
            pass
PY
}

start_proxy_if_needed() {
    repair_opencode_db
    if ! curl -s --max-time 1 http://127.0.0.1:8080/healthz >/dev/null 2>&1; then
        echo -e "${YELLOW}[*] Starting OpenCode Unlimited Proxy (Port 8080)...${NC}"
        "$PROXY_CLI" start || true

        local max_wait=45
        local waited=0
        while [ $waited -lt $max_wait ]; do
            if curl -s --max-time 1 http://127.0.0.1:8080/healthz >/dev/null 2>&1; then
                echo -e "\r${GREEN}[+] Unlimited Proxy ready.                                  ${NC}"
                return 0
            fi
            sleep 1
            waited=$((waited + 1))
            echo -ne "\r${CYAN}[*] Waiting for proxy and WARP egress initialization (${waited}/${max_wait}s)...${NC}"
        done
        echo ""
        echo -e "${RED}[-] Warning: Proxy on port 8080 did not report ready within ${max_wait}s.${NC}"
        echo -e "${YELLOW}[*] Diagnostic proxy logs (last 8 lines):${NC}"
        "$PROXY_CLI" logs 2>/dev/null | tail -n 8 || true
        echo -e "${RED}[!] Error: Unlimited Proxy failed to start on port 8080. Cannot proceed to OpenCode without working backend.${NC}"
        echo -e "${CYAN}[!] Tip: Run 'opencode-proxy restart' or check network/DNS connectivity.${NC}"
        exit 1
    fi
}

start_openrouter_if_needed() {
    local api_key=""
    if [ -f "$OPENROUTER_CONFIG" ]; then
        api_key=$(jq -r '.default_api_key // empty' "$OPENROUTER_CONFIG" 2>/dev/null)
    fi
    if [ -z "$api_key" ] && [ -n "$OPENROUTER_API_KEY" ]; then
        api_key="$OPENROUTER_API_KEY"
    fi

    if [ -z "$api_key" ]; then
        echo -e "\n${YELLOW}${BOLD}[!] OpenRouter API Key required for Mode 2.${NC}"
        echo -n "Please enter your OpenRouter API Key (sk-or-v1-...): "
        read -r input_key || input_key=""
        input_key=$(echo "$input_key" | tr -d '[:space:]')
        if [[ ! "$input_key" =~ ^sk-or-v1-[a-zA-Z0-9]{20,} ]]; then
            echo -e "${RED}[-] Invalid OpenRouter API key format. Aborting.${NC}"
            exit 1
        fi
        api_key="$input_key"

        mkdir -p "$(dirname "$OPENROUTER_CONFIG")"
        if [ -f "$OPENROUTER_CONFIG" ]; then
            python3 -c "
import json
with open('$OPENROUTER_CONFIG') as f: cfg = json.load(f)
cfg['default_api_key'] = '$api_key'
with open('$OPENROUTER_CONFIG', 'w') as f: json.dump(cfg, f, indent=2)
"
        else
            echo "{\"default_api_key\": \"$api_key\"}" > "$OPENROUTER_CONFIG"
        fi
        chmod 600 "$OPENROUTER_CONFIG"
        echo -e "${GREEN}[+] OpenRouter API key saved securely.${NC}"
    fi

    if ! curl -s --max-time 1 http://127.0.0.1:8085/healthz >/dev/null 2>&1; then
        echo -e "${YELLOW}[*] Starting OpenRouter Bridge (Port 8085)...${NC}"
        "$BRIDGE_CLI" start >/dev/null 2>&1 || true

        local max_wait=10
        local waited=0
        while [ $waited -lt $max_wait ]; do
            if curl -s --max-time 1 http://127.0.0.1:8085/healthz >/dev/null 2>&1; then
                echo -e "${GREEN}[+] OpenRouter Bridge ready.${NC}"
                return 0
            fi
            sleep 1
            waited=$((waited + 1))
        done
        echo -e "${RED}[-] Warning: OpenRouter Bridge on port 8085 did not respond within 10s.${NC}"
    fi
}

if [ "$1" = "doctor" ] || [ "$1" = "--doctor" ]; then
    run_doctor
fi

if [ "$1" = "repair" ] || [ "$1" = "--repair" ]; then
    echo -e "${CYAN}[*] Starting deep self-healing repair of OpenCode binary...${NC}"
    rm -f "$OPENCODE_BIN"
    run_installer
    exit 0
fi

if [ "$1" = "update" ] || [ "$1" = "--update" ] || [ "$1" = "upgrade" ] || [ "$1" = "--upgrade" ]; then
    echo -e "${CYAN}[*] Safely updating OpenCode Linux Unlimited via installer pipeline...${NC}"
    rm -f "$OPENCODE_BIN"
    run_installer
    exit 0
fi

if [ "$1" = "uninstall" ] || [ "$1" = "--uninstall" ]; then
    echo -e "${YELLOW}[*] Launching OpenCode uninstaller...${NC}"
    if [ -f "$INSTALL_DIR/uninstall-linux.sh" ]; then
        bash "$INSTALL_DIR/uninstall-linux.sh"
    else
        curl -sSL "$UNINSTALL_SCRIPT_URL" | bash
    fi
    exit 0
fi

if [ "$1" = "kill" ] || [ "$1" = "--kill" ] || [ "$1" = "kill-proxy" ]; then
    "$PROXY_CLI" kill
    exit 0
fi

MODE=""
PASSTHROUGH_ARGS=()

while [ $# -gt 0 ]; do
    case "$1" in
        --mode|-m)
            MODE="$2"
            shift 2
            ;;
        -1)
            MODE="1"
            shift 1
            ;;
        -2)
            MODE="2"
            shift 1
            ;;
        *)
            PASSTHROUGH_ARGS+=("$1")
            shift 1
            ;;
    esac
done

if [ -n "$OPENCODE_MODE" ] && [ -z "$MODE" ]; then
    MODE="$OPENCODE_MODE"
fi

if [ -z "$MODE" ] && [ ${#PASSTHROUGH_ARGS[@]} -gt 0 ]; then
    MODE="1"
fi

if [ -z "$MODE" ]; then
    clear 2>/dev/null || true
    echo -e "${CYAN}${BOLD}================================================================${NC}"
    echo -e "${CYAN}${BOLD}            OpenCode Linux Launcher - Select Mode               ${NC}"
    echo -e "${CYAN}${BOLD}================================================================${NC}"
    echo ""
    echo -e "  ${BOLD}[1] Unlimited Proxy Mode (Default / 100% Free)${NC}"
    echo -e "      ${BLUE}•${NC} Runs standalone local proxy on 127.0.0.1:8080."
    echo -e "      ${BLUE}•${NC} Free unlimited models: DeepSeek V4.1 Flash, GLM 5.3 Flash,"
    echo -e "        Nemotron 3.5, Flint 40B, Big Pickle, Pulse."
    echo -e "      ${BLUE}•${NC} Zero API key required. WARP egress pool enabled."
    echo ""
    echo -e "  ${BOLD}[2] Dual Gateway Mode (Unlimited Free + OpenRouter)${NC}"
    echo -e "      ${BLUE}•${NC} Runs Unlimited Proxy (8080) AND OpenRouter Bridge (8085)."
    echo -e "      ${BLUE}•${NC} Unlocks frontier models alongside free models:"
    echo -e "        Claude 3.7 Sonnet, GPT-4o, DeepSeek R1/V3, Gemini 2.5 Pro."
    echo -e "      ${BLUE}•${NC} Requires your own OpenRouter API key."
    echo ""
    echo -e "${CYAN}================================================================${NC}"
    echo -n "Select option [1/2] (Default is 1): "
    read -r choice || choice=""
    case "$choice" in
        2) MODE="2" ;;
        *) MODE="1" ;;
    esac
fi

if [ "$MODE" = "2" ]; then
    echo -e "${CYAN}[*] Initializing Dual Gateway Mode (Unlimited Proxy + OpenRouter)...${NC}"
    start_proxy_if_needed
    start_openrouter_if_needed
else
    echo -e "${CYAN}[*] Initializing Unlimited Proxy Mode (Free Tier)...${NC}"
    start_proxy_if_needed
fi

# Ensure SSL root certs are visible to the Bun/Go runtimes
CA_BUNDLE=$(detect_ca_bundle 2>/dev/null) && export SSL_CERT_FILE="$CA_BUNDLE" || true
export OPENCODE_DISABLE_AUTOUPDATE=true
repair_opencode_db

# Preflight check before exec to auto-heal corrupted binaries
if ! "$OPENCODE_BIN" --version >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] OpenCode binary is missing or corrupted. Running auto-recovery...${NC}"
    rm -f "$OPENCODE_BIN"
    case "$(uname -m)" in
        x86_64|amd64) NPM_PKG="opencode-linux-x64" ;;
        aarch64|arm64) NPM_PKG="opencode-linux-arm64" ;;
    esac
    TMP_CLI="${TMPDIR:-/tmp}/opencode-cli.$$.tgz"
    curl -fL --retry 3 "https://registry.npmjs.org/${NPM_PKG}/-/${NPM_PKG}-1.19.5.tgz" -o "$TMP_CLI"
    tar -xzf "$TMP_CLI" -C "$LOCAL_BIN" --strip-components=2 package/bin/opencode
    mv "$LOCAL_BIN/opencode" "$OPENCODE_BIN"
    chmod +x "$OPENCODE_BIN"
    rm -f "$TMP_CLI"
    echo -e "${GREEN}[+] OpenCode binary restored successfully.${NC}"
fi

# Merge our providers into the user's existing config without touching it.
# OPENCODE_CONFIG is layered on top of ~/.config/opencode/opencode.jsonc.
EXTRA_CONFIG="$CONFIG_DIR/opencode-unlimited.jsonc"
if [ -f "$EXTRA_CONFIG" ]; then
    export OPENCODE_CONFIG="$EXTRA_CONFIG"
fi

exec "$OPENCODE_BIN" "${PASSTHROUGH_ARGS[@]}"
EOF
chmod +x "$LOCAL_BIN/opencode"

# ---------------------------------------------------------------------------
# 12. Optional global symlink (only when /usr/local/bin is writable)
# ---------------------------------------------------------------------------
GLOBAL_BIN="/usr/local/bin"
if [ -d "$GLOBAL_BIN" ] && [ -w "$GLOBAL_BIN" ]; then
    rm -f "$GLOBAL_BIN/opencode" 2>/dev/null || true
    ln -sf "$LOCAL_BIN/opencode" "$GLOBAL_BIN/opencode" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 13. OpenCode CLI configuration profile
# ---------------------------------------------------------------------------
if [ ! -f "$CONFIG_DIR/opencode.jsonc" ]; then
    echo "[*] Writing OpenCode CLI profile..."
    cat << 'EOF' > "$CONFIG_DIR/opencode.jsonc"
{
  "$schema": "https://opencode.ai/config.json",
  "autoupdate": false,
  "model": "opencode-unlimited-proxy/deepseek-v4.1-flash-free",
  "permission": {
    "*": "allow",
    "bash": "allow",
    "read": "allow",
    "write": "allow",
    "edit": "allow",
    "glob": "allow",
    "grep": "allow",
    "list": "allow",
    "websearch": "allow"
  },
  "provider": {
    "opencode-unlimited-proxy": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "opencode-unlimited-proxy",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1",
        "apiKey": "local-test-key"
      },
      "models": {
        "deepseek-v4.1-flash-free": {},
        "glm-5.3-flash-free": {
          "variants": {
            "low": { "reasoningEffort": "low" },
            "medium": { "reasoningEffort": "medium" },
            "high": { "reasoningEffort": "high" },
            "max": { "reasoningEffort": "max" }
          }
        },
        "nemotron-3.5-lightning-free": {},
        "nemotron-3.5-super-vl-free": {},
        "flint-40b-free": {},
        "big-pickle": {},
        "crouton-alpha-free": {},
        "beam-free": {},
        "mimo-v2.6-flash-free": {},
        "pulse-alpha-free": {}
      }
    },
    "openrouter": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "openrouter",
      "options": {
        "baseURL": "http://127.0.0.1:8085/v1"
      },
      "models": {
        "anthropic/claude-3.7-sonnet": {},
        "anthropic/claude-3.5-sonnet": {},
        "openai/gpt-4o": {},
        "openai/o3-mini": {},
        "deepseek/deepseek-chat": {},
        "google/gemini-2.5-pro": {},
        "meta-llama/llama-3.3-70b-instruct": {}
      }
    }
  }
}
EOF
fi

# Always (re)write the additive profile. The launcher exports OPENCODE_CONFIG to
# point here, so the unlimited providers are merged on top of the user's own
# ~/.config/opencode/opencode.jsonc (which is never modified).
echo "[*] Writing OpenCode Unlimited additive profile..."
cat << 'EOF' > "$CONFIG_DIR/opencode-unlimited.jsonc"
{
  "$schema": "https://opencode.ai/config.json",
  "model": "opencode-unlimited-proxy/deepseek-v4.1-flash-free",
  "provider": {
    "opencode-unlimited-proxy": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "opencode-unlimited-proxy",
      "options": {
        "baseURL": "http://127.0.0.1:8080/v1",
        "apiKey": "local-test-key"
      },
      "models": {
        "deepseek-v4.1-flash-free": {},
        "glm-5.3-flash-free": {
          "variants": {
            "low": { "reasoningEffort": "low" },
            "medium": { "reasoningEffort": "medium" },
            "high": { "reasoningEffort": "high" },
            "max": { "reasoningEffort": "max" }
          }
        },
        "nemotron-3.5-lightning-free": {},
        "nemotron-3.5-super-vl-free": {},
        "flint-40b-free": {},
        "big-pickle": {},
        "crouton-alpha-free": {},
        "beam-free": {},
        "mimo-v2.6-flash-free": {},
        "pulse-alpha-free": {}
      }
    },
    "openrouter": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "openrouter",
      "options": {
        "baseURL": "http://127.0.0.1:8085/v1"
      },
      "models": {
        "anthropic/claude-3.7-sonnet": {},
        "anthropic/claude-3.5-sonnet": {},
        "openai/gpt-4o": {},
        "openai/o3-mini": {},
        "deepseek/deepseek-chat": {},
        "google/gemini-2.5-pro": {},
        "meta-llama/llama-3.3-70b-instruct": {}
      }
    }
  }
}
EOF

# ---------------------------------------------------------------------------
# 14. Update PATH in shell profiles
# ---------------------------------------------------------------------------
add_path_to_rc() {
    local rc="$1"
    if [ ! -f "$rc" ]; then
        # Create the standard login profile if the distro did not ship one.
        [ "$rc" = "$HOME/.profile" ] || return 0
        : > "$rc"
    fi
    if ! grep -q 'HOME/.local/bin' "$rc" 2>/dev/null; then
        printf '\n# OpenCode Unlimited\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
        echo "[*] Added ~/.local/bin to PATH in $rc"
    fi
}
add_path_to_rc "$HOME/.bashrc"
add_path_to_rc "$HOME/.bash_profile"
add_path_to_rc "$HOME/.zshrc"
add_path_to_rc "$HOME/.profile"

add_fish_path() {
    local fish_dir="$HOME/.config/fish"
    local cfg="$fish_dir/config.fish"
    [ -d "$fish_dir" ] || return 0
    if ! grep -q 'HOME/.local/bin' "$cfg" 2>/dev/null; then
        printf '\n# OpenCode Unlimited\nfish_add_path -g "$HOME/.local/bin"\n' >> "$cfg"
        echo "[*] Added ~/.local/bin to PATH in $cfg"
    fi
}
add_fish_path

export PATH="$HOME/.local/bin:$PATH"

# ---------------------------------------------------------------------------
# 15. Pre-start Unlimited Proxy daemon
# ---------------------------------------------------------------------------
echo "[*] Initializing background gateway..."
"$LOCAL_BIN/opencode-proxy" start || true

echo -e "\n${GREEN}${BOLD}[✓] Installation complete!${NC}"
echo "Run 'opencode' to launch the interactive selector."
echo "Run 'opencode doctor' to verify system health anytime."
echo "Run 'opencode update' to pull the latest fixes and improvements."
echo ""
echo -e "${YELLOW}Note: run 'source ~/.bashrc' (or open a new terminal) if 'opencode' is not found.${NC}"
