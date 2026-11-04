# OpenCode Termux Unlimited

A turnkey setup for running the OpenCode CLI on Android (Termux) with rotating Cloudflare WARP egress to bypass the free tier IP-based rate limit.

## Credits & Upstream Projects

This project combines work from several upstream projects:

- [ebouther/opencode-unlimited-proxy](https://github.com/ebouther/opencode-unlimited-proxy): Research and blueprint for routing OpenCode free-tier requests through Cloudflare WARP pools and reproducing client gate headers.
- [jasonxu114514/opencode2api](https://github.com/jasonxu114514/opencode2api): The Go proxy engine that handles session minting, request fingerprinting, and automatic exit rotation on HTTP 429/403.
- [OpenCode](https://opencode.ai): The open-source AI terminal agent.

## Why This Exists

OpenCode provides an anonymous free tier for several AI models. However, requests hit two constraints:

1. Request fingerprinting: Calls require specific client headers (User-Agent versioning, timestamped session IDs, and custom tools).
2. Rate limits: Quotas are tracked by egress IP block (/64 on IPv6, /32 on IPv4). Once an address exhausts its daily quota, upstream returns HTTP 429.

Upstream documentation recommends Docker Compose, which does not run natively on non-rooted Android devices.

This repository packages the statically linked ARM64 Go engine (`opencode2api`) and runs it directly inside Termux using `termux-chroot` to resolve Android DNS issues. When a model returns HTTP 429, the engine automatically replaces the WARP exit IP and retries the request.

## One-Command Quick Start

Open Termux on an ARM64 Android device and run:

```bash
curl -fsSL https://raw.githubusercontent.com/leangtg123-art/opencode-termux-unlimited/main/install.sh | bash
```

The script performs the following tasks:
- Installs necessary Termux packages (`proot`, `jq`, `glibc-runner`, `curl`).
- Downloads and configures the `opencode2api` engine.
- Sets up an automatic WARP IPv6 rotation pool.
- Installs the OpenCode CLI binary and sets up a glibc runner wrapper.
- Generates `~/.config/opencode/opencode.jsonc` preconfigured for the local proxy.
- Launches the proxy background daemon and runs a health check.

Once the installer finishes, run:

```bash
opencode
```

This launches the interactive OpenCode terminal interface.

## Manual Step-by-Step Installation

If you prefer setting up everything by hand without running the one-line installer, follow these steps.

### Step 1: Install Dependencies

```bash
pkg update -y
pkg install -y curl jq proot termux-tools python glibc-repo
pkg install -y glibc-runner
```

### Step 2: Download the Engine

```bash
mkdir -p ~/.opencode-proxy/bin ~/.local/bin ~/.config/opencode
cd ~/.opencode-proxy

curl -sSL "https://github.com/jasonxu114514/opencode2api/releases/download/v1.4.6/opencode2api_v1.4.6_linux_arm64.tar.gz" -o engine.tar.gz
tar -zxvf engine.tar.gz -C bin/ --strip-components=1 opencode2api_v1.4.6_linux_arm64/opencode2api
chmod +x bin/opencode2api
rm -f engine.tar.gz
```

### Step 3: Configure the Proxy

Save this file to `~/.opencode-proxy/config.json`:

```json
{
  "listen": "127.0.0.1:8080",
  "server_keys": ["local-test-key"],
  "anonymous": true,
  "warp": {
    "enabled": true,
    "pool_size": 4,
    "stack": "ipv6"
  },
  "proxies": ["direct"],
  "upstream": {
    "anonymous": "https://opencode.ai/inference"
  },
  "retry": {
    "max_attempts": 6,
    "timeout_seconds": 180
  },
  "models": {
    "refresh_seconds": 300,
    "free_only": true
  },
  "webui": {
    "enabled": true,
    "listen": "127.0.0.1:8081",
    "username": "admin",
    "password": "changeme-changeme"
  }
}
```

### Step 4: Run the Engine

Because standard Android does not provide `/etc/resolv.conf`, the Go runtime defaults to `127.0.0.1:53` which fails on Android. Wrapping the command in `termux-chroot` maps Termux's DNS configuration into `/etc/resolv.conf`.

Start the proxy using:

```bash
termux-chroot ~/.opencode-proxy/bin/opencode2api -config ~/.opencode-proxy/config.json
```

To run it in the background as a daemon, use the `opencode-proxy` script included in this repository.

### Step 5: Install OpenCode CLI

Download the standalone OpenCode Linux ARM64 binary:

```bash
curl -sSL "https://registry.npmjs.org/opencode-linux-arm64/-/opencode-linux-arm64-1.19.5.tgz" -o opencode.tgz
tar -zxvf opencode.tgz -C ~/.local/bin/ --strip-components=2 package/bin/opencode
mv ~/.local/bin/opencode ~/.local/bin/opencode-bin
chmod +x ~/.local/bin/opencode-bin
rm -f opencode.tgz
```

Create an executable wrapper at `~/.local/bin/opencode`:

```bash
cat << 'EOF' > ~/.local/bin/opencode
#!/data/data/com.termux/files/usr/bin/bash
exec /data/data/com.termux/files/usr/bin/grun "$HOME/.local/bin/opencode-bin" "$@"
EOF
chmod +x ~/.local/bin/opencode
```

Make sure `~/.local/bin` is in your PATH.

### Step 6: Configure OpenCode Profile

Write the following to `~/.config/opencode/opencode.jsonc`:

```jsonc
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
        "beam-free": {},
        "big-pickle": {},
        "crouton-alpha-free": {},
        "deepseek-v4.1-flash-free": {},
        "flint-40b-free": {},
        "glm-5.3-flash-free": {},
        "mimo-v2.6-flash-free": {},
        "nemotron-3.5-lightning-free": {},
        "nemotron-3.5-super-vl-free": {},
        "pulse-alpha-free": {}
      }
    }
  }
}
```

## Managing the Gateway

The `opencode-proxy` command provides management operations:

```bash
# Check status, models count, and active WARP exits
opencode-proxy status

# Start the background proxy service
opencode-proxy start

# Stop the proxy service
opencode-proxy stop

# Restart the service
opencode-proxy restart

# Test an API call through the proxy
opencode-proxy test deepseek-v4.1-flash-free

# Follow live output logs
opencode-proxy logs
```

## Available Free Models

The gateway exposes free tier models provided by upstream:

| Model ID | Description |
|---|---|
| `deepseek-v4.1-flash-free` | Fast coding and logic analysis |
| `big-pickle` | General reasoning model |
| `crouton-alpha-free` | Large multimodal context (1M tokens) |
| `nemotron-3.5-super-vl-free` | NVIDIA Vision-Language (1M tokens) |
| `nemotron-3.5-lightning-free` | High speed, low latency |
| `glm-5.3-flash-free` | General knowledge |
| `beam-free` | Code reasoning |
| `mimo-v2.6-flash-free` | Lightweight assistant |
| `flint-40b-free` | Open weights model |
| `pulse-alpha-free` | Multimodal model |

Inside the OpenCode TUI, change models anytime with:

```text
/model opencode-unlimited-proxy/deepseek-v4.1-flash-free
```

## Using with Other Tools

Because the gateway exposes a standard OpenAI-compatible API at `http://127.0.0.1:8080/v1`, you can connect other tools (such as Continue, Cline, or custom scripts) using:

- Base URL: `http://127.0.0.1:8080/v1`
- API Key: `local-test-key`

## License

MIT
