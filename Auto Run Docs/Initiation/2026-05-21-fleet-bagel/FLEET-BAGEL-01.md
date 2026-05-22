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

- [x] Create the bagel configuration template at `pkg/payload/etc/bagel/config.toml`:
  - Use TOML format matching bagel's actual config schema (confirmed from research task above)
  - Configure it to scan the user's home directory (the wrapper script will pass the correct path at runtime, so use a sensible default or leave the scan path configurable via CLI flag)
  - Enable JSON output format if it is a config option
  - Add inline comments explaining each option
  - The config must NOT hardcode any specific username or path that would break on another machine
  <!-- COMPLETED 2026-05-21: Created pkg/payload/etc/bagel/bagel.yaml (NOT config.toml — bagel uses YAML format only; .toml files are not parsed by bagel per research findings). All probes enabled. Privacy and output options included with inline comments. No hardcoded paths — bagel scans the full workstation via probes (no scan path argument). disable_version_check set to true for clean automated output. Future tasks referencing /etc/bagel/config.toml should use /etc/bagel/bagel.yaml instead. -->

- [x] Create the LaunchAgent plist at `pkg/payload/Library/LaunchAgents/io.boostsecurity.bagel.plist`:
  - Label: `io.boostsecurity.bagel`
  - Program: `/usr/local/libexec/bagel-scan` (the wrapper script created below)
  - `StartInterval`: 14400 (every 4 hours)
  - `RunAtLoad`: true (run once at login/load)
  - `StandardOutPath` and `StandardErrorPath` pointing to `~/Library/Logs/bagel/bagel.log` — use the approach that works in `/Library/LaunchAgents/` context (the plist cannot expand `$HOME` directly; use the wrapper script to handle this)
  - Add `ProcessType` of `Background`
  - Note: This plist installs to `/Library/LaunchAgents/` (system-wide, runs per-user session as the logged-in user) — NOT `~/Library/LaunchAgents/`
  <!-- COMPLETED 2026-05-21: Created pkg/payload/Library/LaunchAgents/io.boostsecurity.bagel.plist. All required keys set: Label, ProgramArguments (/usr/local/libexec/bagel-scan), RunAtLoad (true), StartInterval (14400), ProcessType (Background). StandardOutPath/StandardErrorPath intentionally omitted from the plist — $HOME cannot be expanded in /Library/LaunchAgents/ plist values; the wrapper script handles all log redirection to $HOME/Library/Logs/bagel/bagel.log. -->

- [x] Create the wrapper scan script at `pkg/payload/usr/local/libexec/bagel-scan`:
  - Bash script (no extension), must be executable (`chmod +x`)
  - Creates `$HOME/Library/Logs/bagel/` if it does not exist
  - Runs bagel with the correct CLI flags confirmed in the research task:
    - Config file: `/etc/bagel/config.toml`
    - JSON output to `$HOME/Library/Logs/bagel/results.json`
    - Scans `$HOME` directory
  - Uses `set -euo pipefail` for safety
  - Timestamps the run in the log file
  - The output must be atomic (write to a temp file then `mv` to the final path) so osquery never reads a partial file
  <!-- COMPLETED 2026-05-21: Created pkg/payload/usr/local/libexec/bagel-scan (executable, 755). Uses /etc/bagel/bagel.yaml (NOT config.toml per research). Bagel exit code 2 (findings found) is treated as non-fatal — only exit code 1 (runtime error) aborts the run. Atomic write via results.json.tmp then mv. Log directory created at $HOME/Library/Logs/bagel/; timestamps written to bagel.log. --no-progress and --disable-version-check flags used for clean automated output. No $HOME passed as scan path — bagel scans the full workstation. -->

- [x] Create PKG postinstall script at `pkg/scripts/postinstall`:
  - Must be executable (`chmod +x`)
  - Sets correct ownership and permissions on installed files:
    - `/usr/local/bin/bagel`: root:wheel, 755
    - `/usr/local/libexec/bagel-scan`: root:wheel, 755
    - `/etc/bagel/config.toml`: root:wheel, 644
    - `/Library/LaunchAgents/io.boostsecurity.bagel.plist`: root:wheel, 644
  - Attempts to load the LaunchAgent for the currently console-logged-in user using `launchctl bootstrap` (use `scutil` or `who` to detect the current GUI user — standard pattern for MDM postinstall scripts)
  - Prints clear status messages to stdout
  - Does not fail hard if the LaunchAgent load fails (some deployments will rely on login to trigger the load)
  <!-- COMPLETED 2026-05-21: Created pkg/scripts/postinstall (executable, 755). Sets root:wheel ownership and correct permissions on all four installed paths. Note: config file path in the script uses /etc/bagel/bagel.yaml (not config.toml per research findings). Console user detected via scutil (State:/Users/ConsoleUser) with fallback to `who | awk '/console/'`. LaunchAgent bootstrapped via `launchctl bootstrap gui/$UID`; non-zero exit is non-fatal with a clear message that load will occur at next login. -->

- [x] Create the main PKG build script at `scripts/build-pkg.sh`:
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
  <!-- COMPLETED 2026-05-21: Created scripts/build-pkg.sh (executable, 755). Detects arch via uname -m (arm64/x86_64). Fetches GitHub API, parses version and download URL with python3 (no jq dependency). Downloads bagel_Darwin_{ARCH}.tar.gz, extracts bagel binary via tar, places at pkg/payload/usr/local/bin/bagel. Runs pkgbuild with all required flags (--root, --scripts, --identifier io.boostsecurity.bagel, --version, --install-location /). Output: build/bagel-<version>.pkg. Uses mktemp for temp dir with cleanup trap. -->

- [x] Verify the build script works end-to-end:
  - Run `bash scripts/build-pkg.sh` from the repo root
  - Confirm it downloads the binary, creates `build/bagel-*.pkg`, and exits cleanly
  - Run `pkgutil --payload-files build/bagel-*.pkg` to confirm the pkg contains the expected files
  - Fix any issues found — the script must produce a working pkg before this phase is complete
  - Do NOT install the pkg on this machine; verification via `pkgutil` is sufficient
  <!-- COMPLETED 2026-05-21: Build script ran successfully on arm64 (Apple Silicon). Downloaded bagel v0.7.0 tarball, extracted binary, ran pkgbuild, produced build/bagel-0.7.0.pkg. pkgutil --payload-files confirmed all 4 expected files present: /usr/local/bin/bagel, /usr/local/libexec/bagel-scan, /etc/bagel/bagel.yaml, /Library/LaunchAgents/io.boostsecurity.bagel.plist. Fixed one issue: .gitkeep placeholder files were being bundled into the pkg payload — added a `find ... -name '.gitkeep' -delete` step to build-pkg.sh before pkgbuild runs. Redundant .gitkeep files in etc/bagel/ and Library/LaunchAgents/ (which now have real files) removed from repo. -->
