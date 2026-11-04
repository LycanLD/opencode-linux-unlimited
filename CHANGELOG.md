# Changelog

All notable changes to `opencode-termux-unlimited` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
