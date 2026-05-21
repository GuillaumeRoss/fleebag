---
type: research
title: Bagel Release Format, CLI Interface, and JSON Output Schema
created: 2026-05-21
tags:
  - bagel
  - research
  - fleet
related:
  - '[[FLEET-BAGEL-01]]'
---

# Bagel Research Notes

Source: GitHub API + README for `boostsecurityio/bagel` (v0.7.0, latest as of 2026-05-21)

---

## 1. Asset Naming Convention

macOS release assets follow this pattern:

| Architecture | Asset filename |
|---|---|
| Apple Silicon (arm64) | `bagel_Darwin_arm64.tar.gz` |
| Intel (x86_64) | `bagel_Darwin_x86_64.tar.gz` |

**Pattern**: `bagel_Darwin_{ARCH}.tar.gz`
- `Darwin` is capitalized (matches Go's `runtime.GOOS` titlecase convention used by GoReleaser)
- Architecture strings: `arm64` (Apple Silicon) and `x86_64` (Intel)
- `uname -m` on Apple Silicon returns `arm64`; on Intel returns `x86_64`

**No universal/fat binary** is published — select the correct arch-specific asset.

**Full download URL pattern**:
```
https://github.com/boostsecurityio/bagel/releases/download/v{VERSION}/bagel_Darwin_{ARCH}.tar.gz
```

Example for v0.7.0 arm64:
```
https://github.com/boostsecurityio/bagel/releases/download/v0.7.0/bagel_Darwin_arm64.tar.gz
```

---

## 2. CLI Flags

### Scan subcommand

```
bagel scan [flags]
```

**IMPORTANT**: `bagel scan` does NOT accept a directory path as a positional argument.
It scans the entire workstation (all probes scan their fixed system locations).

| Flag | Short | Description |
|---|---|---|
| `--config PATH` | | Path to configuration file |
| `--output FILE` | `-o` | Write output to file (default: stdout) |
| `--format FORMAT` | `-f` | Output format: `json` (default) or `table` |
| `--strict` | | Exit code 2 if any findings detected |
| `--no-cache` | | Force rebuild of file index cache |
| `--no-progress` | | Disable progress bars |
| `--verbose` | `-v` | Enable debug logging |
| `--disable-version-check` | | Skip release update check |

### Example invocations

```bash
# Run with config, write JSON output to file
bagel scan --config /etc/bagel/bagel.yaml --output /tmp/results.json

# Human-readable table output
bagel scan -f table

# Strict mode for CI
bagel scan --strict -o findings.json
```

---

## 3. Configuration File

**Format**: YAML (NOT TOML)
**Default filename**: `bagel.yaml`
**Search order**:
1. Path passed to `--config`
2. `./bagel.yaml` (current directory)
3. `~/.config/bagel/bagel.yaml` (Unix)

> **Note for build tasks**: The task specification references `config.toml` but bagel
> uses YAML. The installed config should be named `bagel.yaml` (or the `--config` flag
> used to point to a file with a `.yaml` extension). Using `.toml` will not be parsed
> by bagel. Adjust install path to `/etc/bagel/bagel.yaml`.

### Full schema

```yaml
version: 1
probes:
  git:
    enabled: true
  ssh:
    enabled: true
  npm:
    enabled: true
  env:
    enabled: true
  shell_history:
    enabled: true
  cloud:
    enabled: true
  jetbrains:
    enabled: true
  gh:
    enabled: true
  ai_credentials:
    enabled: true
  ai_chats:
    enabled: true
privacy:
  redact_paths: []
  exclude_env_prefixes: []
output:
  include_file_hashes: false
  include_file_content: false
disable_version_check: false
```

---

## 4. JSON Output Schema

### Top-level keys

```json
{
  "metadata": { ... },
  "host": { ... },
  "findings": [ ... ]
}
```

### `metadata` object

```json
{
  "version": "0.7.0",
  "timestamp": "2026-05-21T12:00:00Z",
  "duration": "1.234s"
}
```

### `host` object

```json
{
  "hostname": "dev-laptop",
  "os": "darwin",
  "arch": "arm64",
  "username": "dev",
  "system": {
    "os_version": "15.x",
    "kernel_version": "Darwin 25.x.x",
    "cpu_model": "Apple M-series",
    "cpu_cores": 8,
    "ram_total_gb": 16
  }
}
```

### Finding object shape

```json
{
  "id": "git-ssl-verify-disabled",
  "probe": "git",
  "severity": "high",
  "title": "Git SSL Verification Disabled",
  "message": "Detailed description of the finding...",
  "path": "git-config:http.sslverify"
}
```

### Severity values

**Lowercase strings**: `critical`, `high`, `medium`, `low`

> **Note**: Severity values are lowercase. "CRITICAL" (uppercase) is NOT correct.

---

## 5. Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success; no findings (or `--strict` not set) |
| 1 | Runtime error |
| 2 | Findings detected (only when `--strict` flag used) |

---

## 6. Key Implications for Build Tasks

1. **Config file extension**: Use `.yaml`, not `.toml`. Suggested path: `/etc/bagel/bagel.yaml`
2. **No scan path argument**: The wrapper script should NOT pass `$HOME` as an argument to `bagel scan` — bagel scans the full workstation regardless.
3. **Binary is inside a tarball**: The download is a `.tar.gz` archive; must extract to get the `bagel` binary.
4. **arch mapping**: `uname -m` returns `arm64` on Apple Silicon (matches asset name directly); returns `x86_64` on Intel (also matches directly). No remapping needed.
