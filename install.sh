#!/data/data/com.termux/files/usr/bin/bash
# OpenCode Termux Unlimited Installer
# Multi-mode deployment: Unlimited Free Proxy + OpenRouter Autonomous Bridge
# Target Architecture: aarch64 (ARM64 Android / Termux)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}=== OpenCode Termux Unlimited Installer ===${NC}"

ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
    echo -e "${RED}[!] Error: Architecture '$ARCH' is not supported. This installer requires aarch64 (ARM64).${NC}"
    exit 1
fi

# 1. Dependency Verification & Installation
echo "[*] Checking prerequisite packages..."
NEEDED_PKGS=()
for pkg in curl jq proot termux-tools python; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
        NEEDED_PKGS+=("$pkg")
    fi
done

if [ ${#NEEDED_PKGS[@]} -gt 0 ]; then
    echo "[*] Installing missing base utilities: ${NEEDED_PKGS[*]}"
    pkg update -y || apt-get update -y || true
    pkg install -y "${NEEDED_PKGS[@]}" || apt-get install -y --no-install-recommends "${NEEDED_PKGS[@]}" || true
fi

# 1.1 Self-healing Termux glibc runtime environment setup
echo "[*] Verifying Termux glibc runtime environment..."
if ! command -v grun >/dev/null 2>&1 || [ ! -f "$PREFIX/glibc/lib/ld-linux-aarch64.so.1" ]; then
    echo "[*] Initializing Termux glibc repository configuration..."
    mkdir -p "$PREFIX/etc/apt/sources.list.d"
    GLIBC_SOURCE_FILE="$PREFIX/etc/apt/sources.list.d/glibc.list"

    if [ ! -f "$GLIBC_SOURCE_FILE" ] || ! grep -q "termux-glibc" "$GLIBC_SOURCE_FILE" 2>/dev/null; then
        cat << 'EOF' > "$GLIBC_SOURCE_FILE"
# The glibc termux repository, with cloudflare cache
deb https://packages-cf.termux.dev/apt/termux-glibc/ glibc stable
# The glibc termux repository, fallback mirror
deb https://packages.termux.dev/apt/termux-glibc/ glibc stable
EOF
    fi

    echo "[*] Refreshing package indexes..."
    apt-get update -y -o Acquire::Retries=3 || pkg update -y || true

    echo "[*] Installing glibc-runner..."
    if ! pkg install -y glibc-runner 2>/dev/null; then
        echo "[*] Retrying glibc-runner installation via apt-get..."
        apt-get install -y --no-install-recommends glibc-repo glibc-runner || true
    fi

    if ! command -v grun >/dev/null 2>&1; then
        echo -e "${RED}[!] Error: Failed to setup glibc-runner automatically.${NC}"
        echo -e "${YELLOW}Please run manually:${NC}"
        echo "  mkdir -p \$PREFIX/etc/apt/sources.list.d && echo \"deb https://packages-cf.termux.dev/apt/termux-glibc/ glibc stable\" > \$PREFIX/etc/apt/sources.list.d/glibc.list && apt update && pkg install -y glibc-runner"
        exit 1
    fi
    echo -e "${GREEN}[+] glibc-runner successfully configured.${NC}"
else
    echo -e "${GREEN}[+] glibc-runner is already installed and verified.${NC}"
fi

# 1.2 Termux DNS resolver verification
if [ ! -s "$PREFIX/etc/resolv.conf" ]; then
    echo "[*] Initializing fallback DNS nameservers in $PREFIX/etc/resolv.conf..."
    cat << 'EOF' > "$PREFIX/etc/resolv.conf"
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 1.0.0.1
EOF
fi

INSTALL_DIR="$HOME/.opencode-proxy"
BIN_DIR="$INSTALL_DIR/bin"
LOCAL_BIN="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/opencode"
BRIDGE_DIR="$HOME/.local/share/openrouter-bridge"
BRIDGE_CONFIG_DIR="$HOME/.config/openrouter-bridge"

mkdir -p "$BIN_DIR" "$LOCAL_BIN" "$CONFIG_DIR" "$BRIDGE_DIR" "$BRIDGE_CONFIG_DIR"

# 2. Download and setup opencode2api engine
OPENCODE2API_VER="v1.4.6"
ENGINE_URL="https://github.com/jasonxu114514/opencode2api/releases/download/${OPENCODE2API_VER}/opencode2api_${OPENCODE2API_VER}_linux_arm64.tar.gz"

echo "[*] Downloading opencode2api engine (${OPENCODE2API_VER})..."
TMP_ARCHIVE="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/opencode2api.tar.gz"
curl -sSL "$ENGINE_URL" -o "$TMP_ARCHIVE"
tar -zxvf "$TMP_ARCHIVE" -C "$BIN_DIR" --strip-components=1 opencode2api_${OPENCODE2API_VER}_linux_arm64/opencode2api
chmod +x "$BIN_DIR/opencode2api"
rm -f "$TMP_ARCHIVE"

# 3. Create daemon double-fork spawner
cat << 'EOF' > "$INSTALL_DIR/daemon_spawn.py"
#!/data/data/com.termux/files/usr/bin/python3
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

# 4. Create Unlimited Proxy configuration (Port 8080)
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

# 5. Install opencode-proxy manager CLI
cat << 'EOF' > "$LOCAL_BIN/opencode-proxy"
#!/data/data/com.termux/files/usr/bin/bash
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

start_proxy() {
    if get_pid >/dev/null 2>&1; then
        echo "[*] OpenCode Proxy is already running (PID: $(get_pid))"
        return 0
    fi
    echo "[*] Starting OpenCode Proxy daemon on 127.0.0.1:8080..."
    local runner=()
    if command -v termux-chroot >/dev/null 2>&1; then
        runner=("termux-chroot")
    fi
    python3 "$SPAWNER" "$PID_FILE" "$LOG_FILE" "${runner[@]}" "$BIN" -config "$CONFIG"
    sleep 2
    if get_pid >/dev/null 2>&1; then
        echo "[+] OpenCode Proxy started successfully (PID: $(get_pid))"
    else
        echo "[-] Failed to start OpenCode Proxy. Check logs at: $LOG_FILE"
        exit 1
    fi
}

stop_proxy() {
    local pid
    pid=$(get_pid 2>/dev/null) || true
    if [ -n "$pid" ]; then
        echo "[*] Stopping OpenCode Proxy (PID: $pid)..."
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -9 "$pid" 2>/dev/null || true
        rm -f "$PID_FILE"
        echo "[+] Proxy stopped."
    else
        echo "[*] Proxy is not running."
    fi
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
    start)   start_proxy ;;
    stop)    stop_proxy ;;
    restart) stop_proxy; sleep 1; start_proxy ;;
    status)  status_proxy ;;
    test)    test_chat "$2" ;;
    logs)    show_logs ;;
    *)
        echo "Usage: opencode-proxy {start|stop|restart|status|test [model]|logs}"
        exit 1
        ;;
esac
EOF
chmod +x "$LOCAL_BIN/opencode-proxy"

# 6. Install OpenRouter Bridge Subsystem (Port 8085)
cat << 'EOF' > "$BRIDGE_DIR/bridge.py"
#!/data/data/com.termux/files/usr/bin/python3
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
            "X-Title": "OpenCode Termux Autonomous Bridge"
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

# 7. Install openrouter-bridge controller CLI
cat << 'EOF' > "$LOCAL_BIN/openrouter-bridge"
#!/data/data/com.termux/files/usr/bin/bash
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

# 8. Create default bridge configuration
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
    "X-Title": "OpenCode Termux Autonomous Bridge"
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

# 9. Download OpenCode CLI (v1.19.5 - Optimized monolithic build for Termux glibc-runner)
if [ ! -f "$LOCAL_BIN/opencode-bin" ]; then
    echo "[*] Downloading OpenCode CLI binary (v1.19.5)..."
    TMP_CLI="${TMPDIR:-/data/data/com.termux/files/usr/tmp}/opencode-cli.tgz"
    curl -sSL "https://registry.npmjs.org/opencode-linux-arm64/-/opencode-linux-arm64-1.19.5.tgz" -o "$TMP_CLI"
    tar -zxvf "$TMP_CLI" -C "$LOCAL_BIN" --strip-components=2 package/bin/opencode
    mv "$LOCAL_BIN/opencode" "$LOCAL_BIN/opencode-bin"
    chmod +x "$LOCAL_BIN/opencode-bin"
    rm -f "$TMP_CLI"

    # Apply GLM 5.3 Reasoning Unlock patch
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

# 10. Install Interactive Multi-Mode Launcher
cat << 'EOF' > "$LOCAL_BIN/opencode"
#!/data/data/com.termux/files/usr/bin/bash
# OpenCode Multi-Mode Launcher for Termux (Android)
# Mode 1: Unlimited Free Proxy
# Mode 2: Dual Gateway (Unlimited Proxy + OpenRouter Bridge)

set -e

CONFIG_DIR="$HOME/.config/opencode"
OPENROUTER_CONFIG="$HOME/.config/openrouter-bridge/config.json"
BRIDGE_CLI="$HOME/.local/bin/openrouter-bridge"
PROXY_CLI="$HOME/.local/bin/opencode-proxy"
OPENCODE_BIN="$HOME/.local/bin/opencode-bin"
GRUN="/data/data/com.termux/files/usr/bin/grun"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

run_doctor() {
    echo -e "${CYAN}${BOLD}=== OpenCode Termux System Diagnostics (Doctor) ===${NC}\n"
    local issues=0

    echo -n "[*] Checking system architecture... "
    ARCH=$(uname -m)
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
        echo -e "${GREEN}OK ($ARCH)${NC}"
    else
        echo -e "${RED}FAIL (Unsupported: $ARCH)${NC}"
        issues=$((issues + 1))
    fi

    echo -n "[*] Checking glibc-runner (grun)... "
    if command -v grun >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}MISSING (Fix: echo 'deb https://packages-cf.termux.dev/apt/termux-glibc/ glibc stable' > \$PREFIX/etc/apt/sources.list.d/glibc.list && apt update && pkg install -y glibc-runner)${NC}"
        issues=$((issues + 1))
    fi

    echo -n "[*] Checking OpenCode binary... "
    if [ -f "$OPENCODE_BIN" ]; then
        echo -e "${GREEN}FOUND${NC}"
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
        echo -e "${RED}UNREACHABLE (Check /data/data/com.termux/files/usr/etc/resolv.conf)${NC}"
        issues=$((issues + 1))
    fi

    echo -n "[*] Validating ~/.config/opencode/opencode.jsonc... "
    if [ -f "$CONFIG_DIR/opencode.jsonc" ]; then
        if python3 -c "import json; json.load(open('$CONFIG_DIR/opencode.jsonc'))" 2>/dev/null; then
            echo -e "${GREEN}VALID${NC}"
        else
            echo -e "${RED}SYNTAX ERROR${NC}"
            issues=$((issues + 1))
        fi
    else
        echo -e "${YELLOW}NOT FOUND${NC}"
    fi

    echo ""
    if [ $issues -eq 0 ]; then
        echo -e "${GREEN}${BOLD}[✓] All core systems operational.${NC}"
    else
        echo -e "${RED}${BOLD}[!] Found $issues potential issue(s).${NC}"
    fi
    exit $issues
}

start_proxy_if_needed() {
    if ! curl -s --max-time 1 http://127.0.0.1:8080/healthz >/dev/null 2>&1; then
        echo -e "${YELLOW}[*] Starting OpenCode Unlimited Proxy (Port 8080)...${NC}"
        "$PROXY_CLI" start >/dev/null 2>&1 || true

        local max_wait=15
        local waited=0
        while [ $waited -lt $max_wait ]; do
            if curl -s --max-time 1 http://127.0.0.1:8080/healthz >/dev/null 2>&1; then
                echo -e "${GREEN}[+] Unlimited Proxy ready.${NC}"
                return 0
            fi
            sleep 1
            waited=$((waited + 1))
        done
        echo -e "${RED}[-] Warning: Proxy on port 8080 did not report ready within 15s.${NC}"
        echo -e "${YELLOW}[!] If models fail with ECONNREFUSED, run: opencode-proxy status / opencode-proxy logs${NC}"
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
        read -r input_key
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

if [ "$1" = "update" ] || [ "$1" = "--update" ]; then
    echo -e "${CYAN}[*] Fetching and applying latest OpenCode Termux Unlimited updates from GitHub...${NC}"
    curl -sSL https://raw.githubusercontent.com/leangtg123-art/opencode-termux-unlimited/main/install.sh | bash
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
    echo -e "${CYAN}${BOLD}           OpenCode Termux Launcher - Select Mode               ${NC}"
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
    read -r choice
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

exec "$GRUN" "$OPENCODE_BIN" "${PASSTHROUGH_ARGS[@]}"
EOF
chmod +x "$LOCAL_BIN/opencode"

# Clean legacy conflicting wrappers in $PREFIX/bin or system paths
if [ -f "$PREFIX/bin/opencode" ] || [ -L "$PREFIX/bin/opencode" ]; then
    if [ "$(realpath "$PREFIX/bin/opencode" 2>/dev/null)" != "$LOCAL_BIN/opencode" ]; then
        echo "[*] Cleaning legacy conflicting wrapper at $PREFIX/bin/opencode..."
        rm -f "$PREFIX/bin/opencode" 2>/dev/null || true
    fi
fi

# Ensure global PATH execution by symlinking to $PREFIX/bin/opencode
ln -sf "$LOCAL_BIN/opencode" "$PREFIX/bin/opencode" 2>/dev/null || true

# 11. Create OpenCode CLI configuration profile
if [ ! -f "$CONFIG_DIR/opencode.jsonc" ]; then
    echo "[*] Writing OpenCode CLI profile..."
    cat << 'EOF' > "$CONFIG_DIR/opencode.jsonc"
{
  "$schema": "https://opencode.ai/config.json",
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

# 12. Update PATH in ~/.bashrc
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    if ! grep -q 'HOME/.local/bin' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    export PATH="$HOME/.local/bin:$PATH"
fi

# 13. Pre-start Unlimited Proxy daemon
echo "[*] Initializing background gateway..."
"$LOCAL_BIN/opencode-proxy" start

echo -e "\n${GREEN}${BOLD}[✓] Installation complete!${NC}"
echo "Run 'opencode' to launch the interactive selector."
echo "Run 'opencode doctor' to verify system health anytime."
echo "Run 'opencode update' to pull the latest fixes and improvements."
