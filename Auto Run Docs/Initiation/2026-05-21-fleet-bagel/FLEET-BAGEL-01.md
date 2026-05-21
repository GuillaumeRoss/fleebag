# Phase 01: Repo Structure + PKG Build System

This phase establishes the complete repository layout and delivers the core deliverable: a working `build-pkg.sh` script that downloads the latest `bagel` release from GitHub and packages it as an unsigned macOS `.pkg` with proper filesystem conventions, a LaunchAgent plist, a wrapper scan script, and a bagel config template. By the end of this phase the repo has a coherent structure and a script that produces a functional, installable package.

## Tasks

- [x] Research bagel's release format and CLI interface by fetching the GitHub API and inspecting the release assets:
  - Fetch `https://api.github.com/repos/boostsecurityio/bagel/releases/latest` (use curl or WebFetch) to determine the actual asset naming convention for macOS (arm64 vs universal vs x86_64)
  - Read the bagel README or any linked documentation to confirm the CLI flags for: config file path, output format (JSON), output file path, and the scan subcommand syntax
  - Confirm the exact JSON output schema (top-level keys, finding object shape, severity values including whether "CRITICAL" is the correct string)
  - Save findings in a scratch note at `Auto Run Docs/Initiation/Working/bagel-research.md` with the confirmed asset URL pattern, CLI flags, and JSON schema — this will be used in later phases
  <!-- COMPLETED 2026-05-21: Research saved to Auto Run Docs/Initiation/Working/bagel-research.md. Key findings:
    - Asset pattern: bagel_Darwin_{arm64|x86_64}.tar.gz (no universal binary; tarball, not raw binary)
    - CLI: `bagel scan --config PATH --output FILE --format json` (NO positional scan path — scans full workstation)
    - Config format is YAML (bagel.yaml), NOT TOML — later tasks referencing config.toml should use bagel.yaml
    - Severity values are lowercase: critical/high/medium/low (NOT "CRITICAL")
    - JSON top-level keys: metadata, host, findings
    - Finding shape: id, probe, severity, title, message, path
  -->

- [x] Create the repository directory skeleton:
  - `scripts/` — build and utility scripts
  - `pkg/payload/usr/local/bin/` — bagel binary landing (populated at build time, gitignored)
  - `pkg/payload/usr/local/libexec/` — wrapper scan script
  - `pkg/payload/etc/bagel/` — bagel config template
  - `pkg/payload/Library/LaunchAgents/` — LaunchAgent plist
  - `pkg/scripts/` — PKG pre/postinstall scripts
  - `queries/` — Fleet/osquery SQL files
  - `tests/fixtures/` — anonymized JSON test fixtures
  - `tests/` — test runner scripts
  - Create a `.gitignore` that ignores `pkg/payload/usr/` (downloaded binaries), `*.pkg` build artifacts, and `build/` directory
  <!-- COMPLETED 2026-05-21: All directories created with .gitkeep files to track in git. .gitignore created ignoring pkg/payload/usr/, *.pkg, and build/. Note: subsequent tasks referencing config.toml should use bagel.yaml per research findings. -->

- [ ] Create the bagel configuration template at `pkg/payload/etc/bagel/config.toml`:
  - Use TOML format matching bagel's actual config schema (confirmed from research task above)
  - Configure it to scan the user's home directory (the wrapper script will pass the correct path at runtime, so use a sensible default or leave the scan path configurable via CLI flag)
  - Enable JSON output format if it is a config option
  - Add inline comments explaining each option
  - The config must NOT hardcode any specific username or path that would break on another machine

- [ ] Create the LaunchAgent plist at `pkg/payload/Library/LaunchAgents/io.boostsecurity.bagel.plist`:
  - Label: `io.boostsecurity.bagel`
  - Program: `/usr/local/libexec/bagel-scan` (the wrapper script created below)
  - `StartInterval`: 14400 (every 4 hours)
  - `RunAtLoad`: true (run once at login/load)
  - `StandardOutPath` and `StandardErrorPath` pointing to `~/Library/Logs/bagel/bagel.log` — use the approach that works in `/Library/LaunchAgents/` context (the plist cannot expand `$HOME` directly; use the wrapper script to handle this)
  - Add `ProcessType` of `Background`
  - Note: This plist installs to `/Library/LaunchAgents/` (system-wide, runs per-user session as the logged-in user) — NOT `~/Library/LaunchAgents/`

- [ ] Create the wrapper scan script at `pkg/payload/usr/local/libexec/bagel-scan`:
  - Bash script (no extension), must be executable (`chmod +x`)
  - Creates `$HOME/Library/Logs/bagel/` if it does not exist
  - Runs bagel with the correct CLI flags confirmed in the research task:
    - Config file: `/etc/bagel/config.toml`
    - JSON output to `$HOME/Library/Logs/bagel/results.json`
    - Scans `$HOME` directory
  - Uses `set -euo pipefail` for safety
  - Timestamps the run in the log file
  - The output must be atomic (write to a temp file then `mv` to the final path) so osquery never reads a partial file

- [ ] Create PKG postinstall script at `pkg/scripts/postinstall`:
  - Must be executable (`chmod +x`)
  - Sets correct ownership and permissions on installed files:
    - `/usr/local/bin/bagel`: root:wheel, 755
    - `/usr/local/libexec/bagel-scan`: root:wheel, 755
    - `/etc/bagel/config.toml`: root:wheel, 644
    - `/Library/LaunchAgents/io.boostsecurity.bagel.plist`: root:wheel, 644
  - Attempts to load the LaunchAgent for the currently console-logged-in user using `launchctl bootstrap` (use `scutil` or `who` to detect the current GUI user — standard pattern for MDM postinstall scripts)
  - Prints clear status messages to stdout
  - Does not fail hard if the LaunchAgent load fails (some deployments will rely on login to trigger the load)

- [ ] Create the main PKG build script at `scripts/build-pkg.sh`:
  - Must be executable and fully self-contained (no user input required)
  - Detects host architecture (`uname -m`) and selects the correct bagel binary asset
  - Fetches the latest release from `https://api.github.com/repos/boostsecurityio/bagel/releases/latest` using the GitHub API (no auth token needed for public releases)
  - Parses the download URL from the JSON response using `python3 -c` or `jq` (prefer python3 since it's always present on macOS, make jq optional)
  - Downloads the bagel binary to `pkg/payload/usr/local/bin/bagel` and makes it executable
  - Creates a `build/` directory for output artifacts
  - Runs `pkgbuild` with:
    - `--root pkg/payload` — the payload directory
    - `--scripts pkg/scripts` — pre/postinstall scripts
    - `--identifier io.boostsecurity.bagel`
    - `--version` set to the downloaded release version
    - `--install-location /` — installs relative to filesystem root
    - Output: `build/bagel-<version>.pkg`
  - Prints the path to the built pkg on success
  - Includes a usage/help comment block at the top of the script

- [ ] Verify the build script works end-to-end:
  - Run `bash scripts/build-pkg.sh` from the repo root
  - Confirm it downloads the binary, creates `build/bagel-*.pkg`, and exits cleanly
  - Run `pkgutil --payload-files build/bagel-*.pkg` to confirm the pkg contains the expected files
  - Fix any issues found — the script must produce a working pkg before this phase is complete
  - Do NOT install the pkg on this machine; verification via `pkgutil` is sufficient
