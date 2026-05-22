# Phase 04: README and Final Polish

This phase writes the comprehensive README that ties the entire project together, and applies finishing touches to make the repo production-ready and easy to use by both developers and Fleet administrators. The README covers prerequisites, PKG build instructions, macOS installation, Fleet query setup (with links to the SQL files), policy configuration guidance, and the test suite. After this phase, the repository is complete and ready for use.

## Tasks

- [x] Read the following before writing anything to ensure the README is accurate:
  - `scripts/build-pkg.sh` — capture the actual usage, flags, and requirements
  - `pkg/payload/etc/bagel/config.toml` — document the config options
  - `pkg/payload/Library/LaunchAgents/io.boostsecurity.bagel.plist` — confirm schedule and paths
  - `pkg/payload/usr/local/libexec/bagel-scan` — confirm output path
  - `queries/bagel_findings.sql` and `queries/bagel_policy.sql` — understand the queries for documentation
  - `tests/run_tests.sh` — capture test usage
  - `Auto Run Docs/Initiation/Working/bagel-research.md` — confirm bagel version/URL for links

- [x] Write the complete `README.md` (replace the existing stub), structured as follows:
  > Note: config path documented as `/etc/bagel/bagel.yaml` (not `config.toml`) per confirmed bagel YAML format from research.

  **Header section:**
  - Project title and one-sentence description
  - Badges (optional, but include a "macOS" badge and a "fleet" badge if easy to add as static shields.io badges)

  **Overview section:**
  - What this repo does: deploy bagel via pkg to scan developer laptops for secrets, surface results in Fleet
  - Architecture diagram (ASCII is fine): `bagel binary → LaunchAgent → results.json → osquery → Fleet`
  - Links to upstream projects: bagel (boostsecurityio/bagel), Fleet (fleetdm/fleet)

  **Prerequisites section:**
  - macOS 12+ (Monterey or later)
  - Xcode Command Line Tools (`xcode-select --install`) for `pkgbuild`
  - `python3` (pre-installed on macOS)
  - Fleet instance with osquery (link to Fleet docs)
  - Optional: `osqueryi` for local query testing

  **Building the PKG section:**
  - Step-by-step instructions to run `scripts/build-pkg.sh`
  - What the script does (downloads latest bagel release, packages it)
  - Note that the bagel binary is NOT stored in this repo — it is always fetched from the latest GitHub release
  - Expected output: `build/bagel-<version>.pkg`
  - How to distribute the pkg (manually, via MDM, via Fleet's software management)

  **Installation section:**
  - What the PKG installs and where:
    - `/usr/local/bin/bagel` — the bagel binary
    - `/usr/local/libexec/bagel-scan` — the scan wrapper script
    - `/etc/bagel/config.toml` — bagel configuration
    - `/Library/LaunchAgents/io.boostsecurity.bagel.plist` — LaunchAgent (runs every 4 hours)
  - Output location: `~/Library/Logs/bagel/results.json`
  - How to manually trigger a scan: `launchctl kickstart -k gui/$(id -u)/io.boostsecurity.bagel`
  - How to check the LaunchAgent status: `launchctl print gui/$(id -u)/io.boostsecurity.bagel`

  **Fleet Queries section:**
  - Short intro: two SQL files in `queries/` designed for Fleet
  - **Findings Query** (`queries/bagel_findings.sql`):
    - Purpose: live query to see all secrets found across your fleet
    - How to add it in Fleet (Settings → Queries → Add Query)
    - Paste the full SQL inline in a fenced code block
    - Describe the output columns
  - **Policy Query** (`queries/bagel_policy.sql`):
    - Purpose: automated policy that fails if any CRITICAL secret detected or scan is stale (>7 days)
    - How to add it as a policy in Fleet (Policies → Add Policy → paste SQL)
    - Paste the full SQL inline in a fenced code block
    - Pass/fail logic explained in plain English:
      - PASS: results file exists, updated within 7 days, no CRITICAL findings
      - FAIL: file missing, stale, or contains CRITICAL-severity secrets
    - Recommended remediation actions in Fleet (notify user, create ticket, etc.)

  **Configuration section:**
  - How to customize `config.toml` (scan paths, excluded paths, enabled rules)
  - How to adjust the scan interval (edit the plist `StartInterval` value before building the pkg)
  - How to change the output path (edit both the wrapper script and the SQL queries)

  **Testing section:**
  - Prerequisites: `osqueryi` installed (`brew install osquery`)
  - Run: `./tests/update_timestamps.sh && ./tests/run_tests.sh`
  - Describe the 4 test fixture scenarios
  - Expected output: all 8 test assertions pass

  **License section:**
  - Reference the LICENSE file

- [x] Final polish pass across all repo files:
  - Ensure `scripts/build-pkg.sh` has a `--help` flag or usage comment at the top
  - Ensure all shell scripts have correct shebangs (`#!/bin/bash`) and are executable
  - Verify `.gitignore` covers `build/`, `pkg/payload/usr/local/bin/`, and `*.pkg`
  - Ensure `tests/fixtures/*.json` files contain no real secrets or identifiable data
  - Remove `Auto Run Docs/Initiation/Working/` scratch files (they were for internal use only and should not be in the final repo): delete `bagel-research.md` and `osquery-research.md`
  - Run `git status` to see all new files, then `git add -A` and `git diff --staged --stat` to review what would be committed — do NOT commit, just show the summary so the user can review
  > Completed 2026-05-21. All scripts executable with `#!/usr/bin/env bash` shebangs. `.gitignore` covers all three patterns. Fixtures use only `REDACTED_...` placeholders — no real secrets. Both Working/ scratch files deleted. 17 files staged; diff stat shown to user for review.
