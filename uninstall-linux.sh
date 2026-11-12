#!/usr/bin/env bash
# OpenCode Unlimited Linux Uninstaller
# Clean removal of binaries, daemons, and proxies

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}=== OpenCode Unlimited Linux Uninstaller ===${NC}"

echo "[*] Stopping active background daemons..."
pkill -9 -f "opencode2api" 2>/dev/null || true
pkill -9 -f "openrouter-bridge" 2>/dev/null || true
pkill -9 -f "opencode-bin" 2>/dev/null || true
pkill -9 -f "daemon_spawn.py" 2>/dev/null || true
pkill -9 -f "bridge.py" 2>/dev/null || true

# Free the service ports in case anything is still holding them
port_pids=""
if command -v lsof >/dev/null 2>&1; then
    port_pids=$(lsof -ti :8080,8081,8085 2>/dev/null || true)
elif command -v fuser >/dev/null 2>&1; then
    port_pids=$(fuser 8080/tcp 8081/tcp 8085/tcp 2>/dev/null || true)
fi
if [ -n "$port_pids" ]; then
    kill -9 $port_pids 2>/dev/null || true
fi

echo "[*] Removing installed binaries and wrappers..."
rm -f "$HOME/.local/bin/opencode"
rm -f "$HOME/.local/bin/opencode-bin"
rm -f "$HOME/.local/bin/opencode-bin.orig"
rm -f "$HOME/.local/bin/opencode-proxy"
rm -f "$HOME/.local/bin/openrouter-bridge"
rm -f "/usr/local/bin/opencode" 2>/dev/null || true

echo "[*] Removing proxy runtimes and engines..."
rm -rf "$HOME/.opencode-proxy"
rm -rf "$HOME/.local/share/openrouter-bridge"
rm -rf "$HOME/.local/state/openrouter-bridge"

echo "[*] Removing PATH entries from shell profiles..."
for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$rc" ] && grep -q 'OpenCode Unlimited' "$rc" 2>/dev/null; then
        # Drop the marker comment line and the export line that follows it.
        python3 - "$rc" << 'PY' 2>/dev/null || true
import sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    lines = f.readlines()
out = []
skip_next = False
for line in lines:
    if skip_next:
        skip_next = False
        if 'HOME/.local/bin' in line:
            continue
    if '# OpenCode Unlimited' in line:
        skip_next = True
        continue
    out.append(line)
with open(path, "w", encoding="utf-8") as f:
    f.writelines(out)
PY
        echo "[*] Cleaned $rc"
    fi
done

echo -e "\n${YELLOW}Do you also want to remove OpenCode configurations and session history (~/.config/opencode)? [y/N]: ${NC}"
read -r -t 10 keep_conf || keep_conf="n"
case "$keep_conf" in
    [yY][eE][sS]|[yY])
        echo "[*] Removing configurations..."
        rm -rf "$HOME/.config/opencode"
        rm -rf "$HOME/.config/openrouter-bridge"
        echo -e "${GREEN}[+] Configurations removed.${NC}"
        ;;
    *)
        echo "[*] Preserving ~/.config/opencode (user configurations and history intact)."
        ;;
esac

echo -e "\n${GREEN}${BOLD}[✓] Uninstallation complete! OpenCode has been removed cleanly.${NC}"
