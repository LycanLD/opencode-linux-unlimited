# opencode-termux-unlimited

Production-ready OpenCode CLI runtime environment for Android (Termux aarch64), featuring a multi-mode gateway architecture with unlimited free models, automated Cloudflare WARP egress pooling, and an integrated OpenRouter bridge.

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

## Features

- **Multi-Mode Interactive Launcher**:
  - **Mode 1 (Unlimited Free Proxy)**: Zero-config access to unlimited free models via local Cloudflare WARP egress pool. No API key required.
  - **Mode 2 (Dual Gateway)**: Runs both the Unlimited Proxy and the dedicated OpenRouter Bridge, allowing simultaneous usage of free models and frontier models (Claude 3.7 Sonnet, GPT-4o, DeepSeek R1/V3) with your own OpenRouter key.
- **GLM 5.3 Reasoning Unlock**: Fixes an upstream OpenCode catalog whitelist bug via an automated 1:1 byte patch to `opencode-bin`, restoring full reasoning effort selection (`low`, `medium`, `high`, `max`) for `glm-5.3-flash-free`.
- **WARP Pool Egress Scaling**: Configured with 6 Cloudflare WARP workers (`preload: 3`, `active: 3`, `standby: 3`) to prevent 429 rate limits under high concurrency.
- **Integrated OpenRouter Autonomous Bridge**: Pure Python 3 standard library daemon with smart multi-egress probing (Wireproxy WARP -> Smart-Proxy -> Direct) and clean HTTP/1.1 SSE streaming.
- **System Doctor & Self-Healing Diagnostics**: Built-in `opencode doctor` command that inspects binary architecture, daemon health, port availability, DNS latency, and configuration validity.

---

## Prerequisites

- **Device**: Android phone or tablet running Termux.
- **Architecture**: `aarch64` / `arm64`. Check with `uname -m`.
- **Packages**: `curl`, `jq`, `proot`, `termux-tools`, `python`, `glibc-repo`, `glibc-runner`. Installed automatically by the script.

---

## Quickstart Installation

Run the one-line installer inside Termux:

```bash
curl -sSL https://raw.githubusercontent.com/leangtg123-art/opencode-termux-unlimited/main/install.sh | bash
```

Once installed, restart your shell or reload PATH:

```bash
source ~/.bashrc
```

---

> [!WARNING]
> ### Do Not Manually Update the OpenCode Binary (`v2.x` Incompatibility)
> 
> Do **not** run `npm update -g opencode`, `npm install -g opencode`, or manually replace `~/.local/bin/opencode-bin` with newer upstream releases (such as `v2.2.5+`).
> 
> **Why?**
> - **Client-Server Daemon Collision**: OpenCode v2.0+ decoupled into a client-server model where the CLI spawns a child background daemon via `execve(process.execPath, ["serve"])`.
> - **Android Bionic Linker Crash (Exit Code 127)**: In Termux, child processes spawned via `execve` bypass the parent shell wrapper (`grun`). The Android kernel rejects the binary because the standard glibc dynamic linker (`/lib/ld-linux-aarch64.so.1`) does not exist in Android's root filesystem, causing the server process to immediately crash with exit code `127`.
> - **Bun Asset Trailer Corruption (Exit Code 139)**: Attempting to modify the binary using `patchelf --set-interpreter` corrupts Bun's embedded executable trailer, leading to an immediate `Segmentation fault (core dumped)`.
> 
> The bundled OpenCode **v1.19.5** build runs entirely in-process under `glibc-runner` (`grun`), ensuring maximum performance, zero sub-process crashes, and seamless proxy routing. Only upgrade OpenCode if you are running inside a full PRoot Linux distribution (e.g., Debian/Ubuntu PRoot) where `/lib` is natively mounted.

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
           OpenCode Termux Launcher - Select Mode               
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

You can also export `OPENCODE_MODE=1` or `OPENCODE_MODE=2` in your `~/.bashrc` to set a permanent default.

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

With our binary patch and config variants, you can adjust GLM 5.3 reasoning depth directly inside the OpenCode TUI:
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

Web dashboard is accessible at `http://127.0.0.1:8081` (Default credentials: `admin` / `changeme-changeme`).

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

Alternatively, re-run the one-line installer anytime (existing binary downloads and configuration settings are automatically preserved):

```bash
curl -sSL https://raw.githubusercontent.com/leangtg123-art/opencode-termux-unlimited/main/install.sh | bash
```

---

## Uninstallation

To cleanly remove all OpenCode binaries, proxies, and background daemons from Termux:

```bash
curl -sSL https://raw.githubusercontent.com/leangtg123-art/opencode-termux-unlimited/main/uninstall.sh | bash
```

Or remove manually in one command:

```bash
pkill -9 -f opencode2api; pkill -9 -f openrouter-bridge; pkill -9 -f opencode-bin
rm -rf ~/.opencode-proxy ~/.local/share/openrouter-bridge ~/.local/bin/opencode* ~/.local/bin/openrouter-bridge /data/data/com.termux/files/usr/bin/opencode
```

---

## Diagnostics & Troubleshooting

Run the built-in system doctor anytime to diagnose potential issues:

```bash
opencode doctor
```

Example output:

```text
=== OpenCode Termux System Diagnostics (Doctor) ===

[*] Checking system architecture... OK (aarch64)
[*] Checking glibc-runner (grun)... OK
[*] Checking OpenCode binary... FOUND
[*] Checking GLM 5.3 reasoning patch... ACTIVE (Unlocked)
[*] Checking Unlimited Proxy (127.0.0.1:8080)... RUNNING (WARP: ready, Models: 10)
[*] Checking OpenRouter Bridge (127.0.0.1:8085)... RUNNING (Egress: direct)
[*] Checking DNS resolution (1.1.1.1)... OK
[*] Validating ~/.config/opencode/opencode.jsonc... VALID

[✓] All core systems operational.
```

### Common Fixes

1. **DNS Resolution Hangs**:
   If DNS fails when switching between Wi-Fi and mobile data, update your nameserver:
   ```bash
   echo "nameserver 1.1.1.1" > /data/data/com.termux/files/usr/etc/resolv.conf
   echo "nameserver 8.8.8.8" >> /data/data/com.termux/files/usr/etc/resolv.conf
   ```

2. **Glibc Interpreter Missing or `Unable to locate package glibc-repo`**:
   If Termux mirrors fail to locate `glibc-repo` or report missing `ld-linux-aarch64.so.1`, initialize the glibc repository list directly and install `glibc-runner`:
   ```bash
   mkdir -p $PREFIX/etc/apt/sources.list.d && echo "deb https://packages-cf.termux.dev/apt/termux-glibc/ glibc stable" > $PREFIX/etc/apt/sources.list.d/glibc.list && apt update && pkg install -y glibc-runner
   ```

3. **Cannot Connect to API (`ECONNREFUSED`)**:
   If OpenCode reports `ECONNREFUSED` when sending prompts, the local unlimited proxy daemon on port 8080 is stopped or DNS resolution failed:
   ```bash
   # Ensure DNS nameservers exist
   echo "nameserver 1.1.1.1" > /data/data/com.termux/files/usr/etc/resolv.conf
   # Restart proxy daemon
   opencode-proxy restart
   # Verify health status
   opencode-proxy status
   ```

4. **"Could not find a PHDR: broken executable?" or `Aborted opencode`**:
   This occurs when Android's Bionic dynamic linker (`/system/bin/linker64`) intercepts execution of OpenCode. This usually happens if:
   - A user ran `npm install -g opencode` or `opencode upgrade`, which overwrites the launcher with a raw glibc binary that Android Bionic cannot parse.
   - `opencode-bin` was corrupted or patched by `patchelf` / `grun -c`.
   - The initial binary download was interrupted.

   **Fix**: Run the built-in repair routine (or re-run `install.sh`):
   ```bash
   opencode repair
   ```
   Or manually:
   ```bash
   rm -f ~/.local/bin/opencode-bin
   curl -sSL https://raw.githubusercontent.com/leangtg123-art/opencode-termux-unlimited/main/install.sh | bash
   ```

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

~/.opencode-proxy/
├── bin/opencode2api   # Compiled ARM64 proxy engine
├── daemon_spawn.py    # Double-fork background spawner
├── config.json        # Proxy configuration (WARP pool size 6)
└── proxy.log          # Operational proxy logs

~/.config/opencode/
└── opencode.jsonc     # OpenCode models and provider configuration
```

---

## Credits

- Maintained by [leangtg123-art](https://github.com/leangtg123-art).
- Architectural design, reverse-engineering, and enhancements contributed by Discord user **leanianstudio**.
- Powered by [OpenCode](https://opencode.ai) and `opencode2api`.

---

## License

This repository is licensed under the [MIT License](LICENSE).
