#!/data/data/com.termux/files/usr/bin/bash
# OpenCode Termux Unlimited Uninstaller
# Clean removal of binaries, daemons, and proxies

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}=== OpenCode Termux Unlimited Uninstaller ===${NC}"

echo "[*] Stopping active background daemons..."
pkill -9 -f "opencode2api" 2>/dev/null || true
pkill -9 -f "openrouter-bridge" 2>/dev/null || true
pkill -9 -f "opencode-bin" 2>/dev/null || true
pkill -9 -f "daemon_spawn.py" 2>/dev/null || true

echo "[*] Removing installed binaries and wrappers..."
rm -f "$HOME/.local/bin/opencode"
rm -f "$HOME/.local/bin/opencode-bin"
rm -f "$HOME/.local/bin/opencode-bin.orig"
rm -f "$HOME/.local/bin/opencode-proxy"
rm -f "$HOME/.local/bin/openrouter-bridge"
rm -f "/data/data/com.termux/files/usr/bin/opencode" 2>/dev/null || true

echo "[*] Removing proxy runtimes and engines..."
rm -rf "$HOME/.opencode-proxy"
rm -rf "$HOME/.local/share/openrouter-bridge"

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
