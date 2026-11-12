# opencode-linux-unlimited

Production-ready OpenCode CLI runtime for Linux with a multi-mode gateway architecture: unlimited free models, automated Cloudflare WARP egress pooling, and an integrated OpenRouter bridge.

Supports `x86_64` and `aarch64` with automatic package-manager detection for Arch, Debian/Ubuntu, Fedora/RHEL, and openSUSE.

---

## Architecture Overview

```
                          ┌──────────────────────────┐
                          │   opencode (Launcher)    │
                          │   Mode 1 / Mode 2 Selector│
                          └─────────────┬────────────┘
                                        │
                 ┌──────────────────────┴──────────────────────┐
                 │                                             │
                 ▼                                             ▼
       [Mode 1: Unlimited Proxy]                     [Mode 2: Dual Gateway]
         127.0.0.1:8080                                127.0.0.1:8085
    ┌───────────────────────────┐                 ┌───────────────────────────┐
    │     opencode2api (Go)     │                 │   openrouter-bridge (Py)  │
    │   Cloudflare WARP Pool    │                 │   Smart Egress Auto-Probe │
    └─────────────┬─────────────┘                 └─────────────┬─────────────┘
                  │                                             │
                  ▼                                             ▼
     Unlimited Free Model Pool                     OpenRouter Frontier APIs
     • DeepSeek V4.1 Flash                         • Claude 3.7 Sonnet
     • GLM 5.3 Flash (Reasoning Unlocked)          • GPT-4o / o3-mini
     • Nemotron 3.5 Lightning / Super-VL           • DeepSeek R1 / V3
     • Flint 40B, Big Pickle, Pulse                • Gemini 2.5 Pro
```

---

## Platform Support

| Platform | Package Manager | Status |
| :--- | :--- | :--- |
| Arch Linux and derivatives (Manjaro, EndeavourOS) | `pacman` | Supported |
| Debian / Ubuntu and derivatives (Mint, Pop!_OS, Kali) | `apt` | Supported |
| Fedora / RHEL and derivatives (Rocky, Alma, CentOS Stream) | `dnf` / `yum` | Supported |
| openSUSE / SLES | `zypper` | Supported |
| Alpine and other musl distros | `apk` + `gcompat` | Best-effort |

- **Architectures**: `x86_64` / `amd64` and `aarch64` / `arm64`. Check with `uname -m`.
- **User-space install**: everything lives under `$HOME` (`~/.local/bin`, `~/.opencode-proxy`, `~/.config`, `~/.local/share`, `~/.local/state`). `sudo` is used only to install missing system packages.

---

## Features

- **Multi-Mode Interactive Launcher**:
  - **Mode 1 (Unlimited Free Proxy)**: Zero-config access to unlimited free models via a local Cloudflare WARP egress pool. No API key required.
  - **Mode 2 (Dual Gateway)**: Runs both the Unlimited Proxy and the dedicated OpenRouter Bridge, allowing simultaneous usage of free models and frontier models (Claude 3.7 Sonnet, GPT-4o, DeepSeek R1/V3) with your own OpenRouter key.
- **GLM 5.3 Reasoning Unlock**: Fixes an upstream OpenCode catalog whitelist bug via an automated 1:1 byte patch to the OpenCode binary, restoring full reasoning effort selection (`low`, `medium`, `high`, `max`) for `glm-5.3-flash-free`.
- **WARP Pool Egress Scaling**: Configured with 6 Cloudflare WARP workers (`preload: 3`, `active: 3`, `standby: 3`) to prevent 429 rate limits under high concurrency.
- **Integrated OpenRouter Autonomous Bridge**: Pure Python 3 standard library daemon with smart multi-egress probing (Wireproxy WARP -> Smart-Proxy -> Direct) and clean HTTP/1.1 SSE streaming.
- **System Doctor & Self-Healing Diagnostics**: Built-in `opencode doctor` command that inspects binary architecture, daemon health, port availability, DNS latency, and configuration validity.
- **Cross-Distro Package Handling**: Detects `pacman`, `apt`, `dnf`, `yum`, `zypper`, or `apk` and installs the right dependency names automatically (`python3` vs `python`, `procps` vs `procps-ng`, etc.).

---

## Prerequisites

The installer auto-detects your package manager and installs anything missing (using `sudo` when not running as root):

- `curl`, `jq`, `python3`, `tar`, `gzip`
- `lsof` (or `fuser`)
- `procps` (`pgrep` / `pkill`)
- `ca-certificates` (SSL roots for WARP/OpenRouter)

If you prefer to install them first:

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install -y curl jq python3 tar gzip lsof procps ca-certificates

# Fedora / RHEL
sudo dnf install -y curl jq python3 tar gzip lsof procps-ng ca-certificates

# Arch Linux
sudo pacman -S --needed curl jq python tar gzip lsof procps-ng ca-certificates

# openSUSE
sudo zypper install curl jq python3 tar gzip lsof procps ca-certificates
```

> **Alpine / musl**: the prebuilt OpenCode CLI is glibc-linked. The installer pulls `gcompat` + `libstdc++`, but musl support is best-effort. A glibc-based distro is recommended.

---

## Quickstart Installation

### One-line installer (recommended)

The bootstrap script clones this repository and runs the full installer:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LycanLD/opencode-linux-unlimited/main/online-install.sh)
```

Or, if you prefer piping into bash:

```bash
curl -fsSL https://raw.githubusercontent.com/LycanLD/opencode-linux-unlimited/main/online-install.sh | bash
```

For a private repository, export a token with `repo` scope first:

```bash
GITHUB_TOKEN=ghp_xxx bash <(curl -fsSL https://raw.githubusercontent.com/LycanLD/opencode-linux-unlimited/main/online-install.sh)
```

### Direct installer

If you already cloned the repository (or want to inspect the script before running it):

```bash
git clone https://github.com/LycanLD/opencode-linux-unlimited.git
cd opencode-linux-unlimited
bash install-linux.sh
```

Or fetch just the installer:

```bash
curl -sSLO https://raw.githubusercontent.com/LycanLD/opencode-linux-unlimited/main/install-linux.sh
less install-linux.sh
bash install-linux.sh
```

Once installed, restart your shell or reload PATH:

```bash
source ~/.bashrc    # or ~/.zshrc, ~/.profile, or: exec $SHELL
```

The installer adds `~/.local/bin` to `.bashrc`, `.bash_profile`, `.zshrc`, `.profile`, and (if present) the Fish config.

---

> [!WARNING]
> ### Do Not Manually Update the OpenCode Binary
>
> Do **not** run `npm update -g opencode`, `npm install -g opencode`, or manually replace `~/.local/bin/opencode-bin` with newer upstream releases (such as `v2.2.5+`).
>
> **Why?**
> - **Client-Server Daemon Collision**: OpenCode v2.0+ decoupled into a client-server model where the CLI spawns a child background daemon via `execve(process.execPath, ["serve"])`.
> - **Broken Pinned Build**: The bundled OpenCode **v1.19.5** is pinned and patched for GLM 5.3 reasoning support. Upstream updates can overwrite the launcher and break proxy routing.
>
> Use `opencode update` / `opencode repair` instead of updating the binary directly.

---

## Usage

### 1. Launching OpenCode

Simply run:

```bash
opencode
```

When run interactively without flags, OpenCode prompts you to choose your operating mode:

```text
================================================================
            OpenCode Linux Launcher - Select Mode
================================================================

  [1] Unlimited Proxy Mode (Default / 100% Free)
      • Runs standalone local proxy on 127.0.0.1:8080.
      • Free unlimited models: DeepSeek V4.1 Flash, GLM 5.3 Flash,
        Nemotron 3.5, Flint 40B, Big Pickle, Pulse.
      • Zero API key required. WARP egress pool enabled.

  [2] Dual Gateway Mode (Unlimited Free + OpenRouter)
      • Runs Unlimited Proxy (8080) AND OpenRouter Bridge (8085).
      • Unlocks frontier models alongside free models:
        Claude 3.7 Sonnet, GPT-4o, DeepSeek R1/V3, Gemini 2.5 Pro.
      • Requires your own OpenRouter API key.
================================================================
Select option [1/2] (Default is 1):
```

### 2. Direct Mode Flags (Bypass Menu)

To bypass the interactive menu in scripts or aliases:

```bash
# Run in Mode 1 directly
opencode -1

# Run in Mode 2 directly
opencode -2

# Pass arguments directly to OpenCode
opencode -1 models
opencode -2 -m anthropic/claude-3.7-sonnet
```

You can also export `OPENCODE_MODE=1` or `OPENCODE_MODE=2` in your shell profile to set a permanent default.

---

## Available Free Models (Mode 1)

All models are served through the local proxy at `http://127.0.0.1:8080/v1`:

| Model ID | Provider Family | Context Window | Capabilities |
| :--- | :--- | :--- | :--- |
| `deepseek-v4.1-flash-free` | DeepSeek | 1,000,000 | Code generation, agent tasks, tools |
| `glm-5.3-flash-free` | Zhipu AI | 1,000,000 | Reasoning effort (`low`, `med`, `high`, `max`), vision |
| `nemotron-3.5-lightning-free` | NVIDIA | 262,144 | Fast instruction following, tool execution |
| `nemotron-3.5-super-vl-free` | NVIDIA | 1,048,576 | Multimodal vision & document analysis |
| `flint-40b-free` | Flint | 128,000 | Balanced reasoning and coding |
| `big-pickle` | Pickle | 200,000 | Deliberate problem solving & planning |
| `pulse-alpha-free` | Pulse | 1,048,576 | High-throughput agent execution |
| `mimo-v2.6-flash-free` | Xiaomi | 262,144 | Low-latency drafting |
| `beam-free` | Reflection | 1,048,576 | Multi-turn reasoning |
| `crouton-alpha-free` | Crouton | 1,048,576 | Long-horizon context |

### Adjusting GLM 5.3 Thinking / Effort

With the binary patch and config variants, you can adjust GLM 5.3 reasoning depth directly inside the OpenCode TUI:
- Use the `/variants` slash command to pick `low`, `medium`, `high`, or `max`.
- Or press `Tab` on the model statusline to cycle through effort levels.

---

## Daemon Management

### Unlimited Proxy (Port 8080)

Manage the local proxy service with `opencode-proxy`:

```bash
opencode-proxy start     # Start daemon
opencode-proxy stop      # Stop daemon
opencode-proxy kill      # Forcefully terminate all proxy engines and port listeners
opencode-proxy restart   # Restart daemon cleanly
opencode-proxy status    # Show PID, WARP status, active models
opencode-proxy test      # Send test request to DeepSeek V4.1
opencode-proxy logs      # View last 35 lines of proxy log
```

Web dashboard is accessible at `http://127.0.0.1:8081` (default credentials: `admin` / `changeme-changeme`).

### OpenRouter Bridge (Port 8085)

Manage the OpenRouter bridge with `openrouter-bridge`:

```bash
openrouter-bridge start     # Start bridge daemon
openrouter-bridge stop      # Stop bridge daemon
openrouter-bridge restart   # Restart bridge daemon
openrouter-bridge status    # Show PID, active egress, upstream target
openrouter-bridge test      # Test model completion via bridge
openrouter-bridge logs      # View bridge access logs
```

---

## Updating

To pull the latest runtime fixes, proxy patches, and improvements directly from GitHub:

```bash
opencode update
```

Alternatively, re-run the bootstrap installer anytime (existing configuration settings are preserved):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/LycanLD/opencode-linux-unlimited/main/online-install.sh)
```

---

## Uninstallation

```bash
curl -sSL https://raw.githubusercontent.com/LycanLD/opencode-linux-unlimited/main/uninstall-linux.sh | bash
```

Or from the installed launcher:

```bash
opencode uninstall
```

Manual removal:

```bash
pkill -9 -f opencode2api; pkill -9 -f openrouter-bridge; pkill -9 -f opencode-bin
rm -rf ~/.opencode-proxy ~/.local/share/openrouter-bridge ~/.local/state/openrouter-bridge \
       ~/.local/bin/opencode ~/.local/bin/opencode-bin ~/.local/bin/opencode-proxy \
       ~/.local/bin/openrouter-bridge /usr/local/bin/opencode
```

---

## Diagnostics & Troubleshooting

Run the built-in system doctor anytime to diagnose potential issues:

```bash
opencode doctor
```

Example output:

```text
=== OpenCode Linux System Diagnostics (Doctor) ===

[*] Checking system architecture... OK (x86_64)
[*] Checking core utilities (curl/jq/python3)... OK
[*] Checking SSL root certificates... OK (/etc/ssl/certs/ca-certificates.crt)
[*] Checking OpenCode database integrity... OK
[*] Checking OpenCode binary... VALID (v1.19.5)
[*] Checking GLM 5.3 reasoning patch... ACTIVE (Unlocked)
[*] Checking launcher/wrapper integrity... OK (Wrapper script)
[*] Checking Unlimited Proxy (127.0.0.1:8080)... RUNNING (WARP: ready, Models: 10)
[*] Checking OpenRouter Bridge (127.0.0.1:8085)... RUNNING (Egress: direct)
[*] Checking DNS resolution (1.1.1.1)... OK
[*] Validating opencode.jsonc... VALID
[*] Validating opencode-unlimited.jsonc... VALID

[✓] All core systems operational.
```

### Common Fixes

1. **Missing packages on Debian/Ubuntu**:
   If the installer could not install prerequisites (for example `sudo` is unavailable), install them manually and re-run:
   ```bash
   sudo apt update && sudo apt install -y curl jq python3 tar gzip lsof procps ca-certificates
   ```

2. **`opencode: command not found` after install**:
   `~/.local/bin` is not on your `PATH` in the current shell. Reload your profile or open a new terminal:
   ```bash
   source ~/.profile    # or ~/.bashrc / ~/.zshrc
   export PATH="$HOME/.local/bin:$PATH"
   ```

3. **DNS Resolution Hangs**:
   If DNS fails when switching networks, check your resolver:
   ```bash
   cat /etc/resolv.conf
   # Optionally use public resolvers (systemd-resolved or your network manager may override this):
   # nameserver 1.1.1.1
   # nameserver 8.8.8.8
   ```

4. **Cannot Connect to API (`ECONNREFUSED`)**:
   The local unlimited proxy on port 8080 is stopped or DNS resolution failed:
   ```bash
   opencode-proxy restart
   opencode-proxy status
   ```

5. **Corrupted OpenCode binary (`Could not find a PHDR`, `Aborted opencode`, etc.)**:
   Run the repair routine:
   ```bash
   opencode repair
   ```
   Or remove and reinstall:
   ```bash
   rm -f ~/.local/bin/opencode-bin
   # then re-run the bootstrap installer
   ```

6. **Alpine / musl errors (`not found` or dynamic linker errors)**:
   The prebuilt OpenCode CLI expects glibc. Install the compatibility layer:
   ```bash
   sudo apk add gcompat libstdc++
   ```
   If it still fails, use a glibc-based distribution (Debian/Ubuntu, Fedora, Arch, openSUSE).

---

## File Structure

```text
~/.local/bin/
├── opencode           # Multi-mode launcher with interactive menu & doctor
├── opencode-bin       # Patched OpenCode binary (v1.19.5 with GLM 5.3 unlock)
├── opencode-proxy     # CLI manager for the unlimited proxy
└── openrouter-bridge  # CLI manager for the OpenRouter bridge

~/.local/share/openrouter-bridge/
└── bridge.py          # Lightweight Python 3 stdlib bridge gateway

~/.local/state/openrouter-bridge/
├── bridge.log         # Bridge access logs
└── bridge.pid         # Bridge PID file

~/.opencode-proxy/
├── bin/opencode2api   # Compiled proxy engine (amd64 / arm64)
├── daemon_spawn.py    # Double-fork background spawner
├── config.json        # Proxy configuration (WARP pool size 6)
├── proxy.log          # Operational proxy logs
├── install-linux.sh   # Cached installer (enables offline update/repair)
└── uninstall-linux.sh # Cached uninstaller (enables offline uninstall)

~/.config/opencode/
├── opencode.jsonc             # OpenCode models and provider configuration
└── opencode-unlimited.jsonc   # Additive profile layered over your own config

~/.config/openrouter-bridge/
└── config.json        # Bridge configuration (egress list, API key)
```

---

## Repository Layout

```text
install-linux.sh      # Direct cross-distro installer
online-install.sh     # One-line bootstrap (clone + install)
uninstall-linux.sh    # Clean uninstaller
config.example.json   # Proxy configuration reference
opencode.example.jsonc# OpenCode provider configuration reference
```

---

## Credits

- Maintained by [LycanLD](https://github.com/LycanLD).
- Architectural design, reverse-engineering, and enhancements contributed by Discord user **leanianstudio**.
- Powered by [OpenCode](https://opencode.ai) and `opencode2api`.

---

## License

This repository is licensed under the [MIT License](LICENSE).
