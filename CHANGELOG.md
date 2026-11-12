# Changelog

All notable changes to `opencode-linux-unlimited` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.7] - 2026-11-09

### Fixed
- **Bionic Linker Crash & PHDR Error Defense (`Could not find a PHDR: broken executable?`)**:
  - Implements binary size and execution preflight validation (>50MB, verified via `grun --version`) before skipping download, preventing broken/truncated binaries from persisting.
  - Adds runtime preflight auto-recovery inside the launcher: detects corrupted or broken binaries on startup and automatically re-fetches a clean monolithic build without crashing.
  - Guards `$PREFIX/bin/opencode` against npm/bun overwrites (e.g. `npm install -g opencode-ai` or `opencode upgrade`), stripping hijacked ELF binaries and restoring the managed wrapper symlink.
  - Automatically exports `OPENCODE_DISABLE_AUTOUPDATE=true` and sets `"autoupdate": false` in `opencode.jsonc` to block background update routines that pull unpatched glibc binaries.
- **Added `opencode repair` & Safe `opencode upgrade` Routing**:
  - Adds `opencode repair` subcommand for one-shot environment restoration (reinstalls `glibc-runner`, purges corrupted binary, re-runs full verification).
  - Routes `opencode upgrade` / `opencode update` safely through `install.sh` pipeline instead of raw npm.
  - Adds wrapper integrity verification to `opencode doctor`.

## [2.0.6] - 2026-11-06

### Fixed
- **Cloudflare WARP IPv6 Stack Lock (`"stack": "ipv6"`)**:
  - Switches WARP pool egress from `dual` to `ipv6` by default. Under dual-stack, requests route via shared Cloudflare IPv4 NAT ranges (`104.28.x.x`), triggering global upstream `HTTP 429 Free usage limit reached` rate limits. Dedicated IPv6 unicast exits (`2a09:bac1:...` / `2a09:bac5:...`) bypass shared congestion with fresh per-IP quotas.
- **SQLite 429 Session Lockout Auto-Inoculation**:
  - Enhances `repair_opencode_db` to automatically detect and purge stuck session entries marked with `Free usage limit` from `~/.local/share/opencode/opencode.db`. Prevents the CLI from entering recursive 21-hour retry loops when restarting after a rate-limit event.

## [2.0.5] - 2026-11-04

### Fixed
- **Glibc Repository GPG Verification Bypass (`[trusted=yes]`)**:
  - Adds `[trusted=yes]` to `sources.list.d/glibc.list` and installs `termux-keyring`, resolving `NO_PUBKEY 5A897D96E57CF20C` and apt repo disabling errors on devices with outdated keyrings.
- **Root SSL CA Certificates for glibc (`ca-certificates-glibc`) & `SSL_CERT_FILE` Propagation**:
  - Automatically installs `ca-certificates-glibc` alongside `glibc-runner` and links `$PREFIX/etc/tls/cert.pem` to glibc SSL paths.
  - Exports `SSL_CERT_FILE` and `SSL_CERT_DIR` across `opencode-proxy`, `daemon_spawn.py`, and `opencode` launcher, fixing `tls: failed to verify certificate: x509: certificate signed by unknown authority` during Cloudflare WARP client registration.
- **Corrupted SQLite Database Auto-Repair (`Database is not empty and has no session table`)**:
  - Implements automatic integrity verification and backup-reset of corrupted `~/.local/share/opencode/opencode.db` upon launch or proxy kill.
- **Zombie Proxy Detection and Guard**:
  - Replaces naive PID presence check in `opencode-proxy` with active HTTP `/healthz` polling, purging dead or hanging proxy daemons automatically. Aborts cleanly before launching OpenCode if the backend proxy fails to initialize.

## [2.0.4] - 2026-11-04

### Added
- **Global Proxy Purge Subsystem (`opencode-proxy kill` / `opencode kill-proxy`)**:
  - Adds dedicated kill subcommands to forcefully kill all proxy engines (`opencode2api`, `proxy.py`, `bridge.py`, `daemon_spawn.py`), clear any processes holding ports 8080/8081/8085 via `lsof`/`fuser`, and delete all stale PID files.

## [2.0.3] - 2026-11-04

### Fixed
- **Valid Dual-Stack WARP Configuration (`stack: "dual"`)**:
  - Corrected WARP configuration schema from invalid `"auto"` to official `"dual"` mode, resolving `unsupported WARP stack "auto"` runtime fatal error. Verified live dual-stack routing (IPv4 exit: 104.28.204.161).
- **Prerequisite Package Detection Optimization**:
  - Replaced binary check for metapackage `termux-tools` with `termux-open` / `termux-reload-settings`, preventing redundant apt updates on repeated installer runs.
- **Conflicting Proxy Process Termination**:
  - Automatically terminates orphan or conflicting proxy processes holding port 8080 or 8081 before starting the gateway daemon.
- **Interactive Diagnostics in Launcher**:
  - Replaced silent startup redirects with real-time logging and automatic log dumps if the proxy daemon does not report ready within 25 seconds.

## [2.0.2] - 2026-11-04

### Added
- **Integrated `opencode update` Command**:
  - Allows users to seamlessly pull and apply the latest repository fixes and improvements with `opencode update`.

### Fixed
- **DNS Resolver Auto-Provisioning & `termux-chroot` Daemon Binding**:
  - Automatically provisions fallback nameservers (`1.1.1.1`, `8.8.8.8`) into `$PREFIX/etc/resolv.conf`.
  - Executes `opencode2api` proxy engine under `termux-chroot` (when available) to ensure Go's pure-Go DNS resolver correctly discovers `/etc/resolv.conf` on Android.
  - Eliminates `[::1]:53 connection refused` lookup failures during Cloudflare WARP initialization, permanently preventing `ECONNREFUSED` connection crashes in OpenCode TUI.
  - Added self-healing recovery hints and documentation for `ECONNREFUSED` in `README.md` and launcher diagnostics.

## [2.0.1] - 2026-11-04

### Fixed
- **Self-Healing Glibc Repository Provisioning**:
  - Automatically provisions `$PREFIX/etc/apt/sources.list.d/glibc.list` pointing directly to Cloudflare and fallback Termux glibc mirrors if `glibc-repo` is not indexed by local apt caches.
  - Resolves `Unable to locate package glibc-repo` failure during automated dependency installation on fresh or un-updated Termux installations.
- **Legacy Stub Collision Resolution**:
  - Automatically removes obsolete or conflicting wrappers at `$PREFIX/bin/opencode` (such as legacy `opencode-native-termux` stubs) and establishes a direct symlink to the multi-mode launcher for global terminal execution regardless of PATH precedence.
- **Diagnostics Doctor Update**:
  - Updated `opencode doctor` glibc check to provide instant 1-line self-healing recovery commands.

## [2.0.0] - 2026-11-04

### Added
- **Interactive Multi-Mode Launcher**:
  - `opencode` now provides an interactive startup menu with two operational modes:
    - **Mode 1**: Standalone Unlimited Free Proxy (Port 8080) with local Cloudflare WARP egress pool.
    - **Mode 2**: Dual Gateway Mode running both Unlimited Proxy (8080) and OpenRouter Autonomous Bridge (8085).
  - CLI flags `--mode 1` (`-1`) and `--mode 2` (`-2`) to bypass the menu in automated or scripted workflows.
  - Interactive OpenRouter API key validator and secure storage (`chmod 600`).
- **OpenRouter Autonomous Gateway Bridge**:
  - Zero-dependency Python 3 standard library daemon listening on `127.0.0.1:8085`.
  - Smart multi-egress probing: automatically probes Wireproxy WARP, Smart-Proxy, and Direct connections with sub-100ms failover.
  - Pure HTTP/1.1 SSE line-by-line streaming without chunk framing corruption.
  - Dedicated controller CLI: `openrouter-bridge` (`start`, `stop`, `restart`, `status`, `test`, `logs`).
- **GLM 5.3 Reasoning Unlock**:
  - Automated 1:1 byte patch during install that fixes upstream OpenCode's hardcoded whitelist in `opencode-bin`.
  - Fully unlocks reasoning effort levels (`low`, `medium`, `high`, `max`) for `glm-5.3-flash-free`.
- **System Doctor & Self-Healing Diagnostics**:
  - Added `opencode doctor` command for instantaneous system diagnosis:
    - Validates ARM64 CPU architecture and `glibc-runner` (`grun`).
    - Checks OpenCode binary integrity and GLM 5.3 patch state.
    - Tests Unlimited Proxy (8080) health and WARP status.
    - Tests OpenRouter Bridge (8085) health and egress reachability.
    - Measures DNS latency to `1.1.1.1` and flags local resolver hangs.
    - Validates `opencode.jsonc` syntax.

### Changed
- **WARP Pool Optimization**:
  - Scaled Cloudflare WARP pool size from 4 to 6 workers (`preload: 3`, `active: 3`, `standby: 3`) to eliminate 429 rate-limit starvation under concurrent model requests.
- **Config Hardening**:
  - Removed corrupted `"rotation"` block with null order values in proxy configuration that previously caused `opencode2api` startup panics.
  - Standardized JSON schemas for both proxy and OpenCode configurations.
- **Termux Runtime Stability**:
  - Standardized on OpenCode v1.19.5 monolithic in-process architecture, avoiding sub-daemon linker failures (exit code 127) observed in v2.x decoupled client-server models on Android.

---

## [1.0.0] - 2026-11-04

### Added
- Initial automated installer for OpenCode on Android Termux ARM64.
- Integration with `opencode2api` Go engine and Cloudflare WARP pool.
- Background double-fork daemon spawner (`daemon_spawn.py`).
- Basic `opencode-proxy` service manager CLI (`start`, `stop`, `restart`, `status`, `test`, `logs`).
- Preconfigured `opencode.jsonc` with 10 free model endpoints.
