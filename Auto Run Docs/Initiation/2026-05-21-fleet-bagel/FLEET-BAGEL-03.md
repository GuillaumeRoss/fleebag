# Phase 03: Test Fixtures and Validation Scripts

This phase builds the complete test suite: four anonymized bagel JSON fixture files covering all pass and fail scenarios, a script to manipulate fixture file timestamps, and a test runner that validates both osquery queries against every fixture using `osqueryi`. After this phase, anyone can clone the repo and run a single command to confirm the queries work correctly before deploying to Fleet.

## Tasks

- [x] Read the bagel JSON schema from `Auto Run Docs/Initiation/Working/bagel-research.md` and the osquery approach from `Auto Run Docs/Initiation/Working/osquery-research.md` before creating any fixtures — the fixture schema must exactly match real bagel output

- [x] Create four anonymized bagel JSON fixture files in `tests/fixtures/`:
  All files must use realistic but fully anonymized/fake data (no real secrets, no real usernames, no real file paths that could identify a real system). Use placeholder values like `REDACTED_aws_key_example`, `/Users/testuser/`, etc.

  - `no_critical_fresh.json` — contains findings of LOW and HIGH severity only (no CRITICAL); represents a machine with minor issues but passing policy; `scan_time` or equivalent timestamp field should be recent (use a placeholder comment `# TIMESTAMP_PLACEHOLDER` that the timestamp script will replace)
  - `no_critical_stale.json` — same severity profile (LOW/HIGH only, no CRITICAL) but the file itself will be made stale by the timestamp script; content is identical structure to the fresh variant
  - `critical_fresh.json` — contains at least one CRITICAL-severity finding plus some LOW/HIGH findings; file will be kept fresh; should fail policy due to CRITICAL finding
  - `critical_stale.json` — contains CRITICAL finding(s) AND will be made stale; fails policy on both counts

  Each fixture must:
  - Match the exact JSON schema bagel actually outputs (confirmed from research)
  - Contain realistic-looking but fake rule IDs, file paths, and redacted secret values
  - Include at least 3-5 findings per file for realistic test coverage
  - Include all fields bagel outputs (even optional ones, set to null if absent) so queries that reference those fields don't error

- [x] Create the timestamp manipulation script at `tests/update_timestamps.sh`:
  - Must be executable (`chmod +x`)
  - Usage: `./tests/update_timestamps.sh` (no arguments, operates on known fixture files)
  - Sets file modification times using `touch -t` or `touch -d`:
    - `no_critical_fresh.json` → current time (now)
    - `critical_fresh.json` → current time (now)
    - `no_critical_stale.json` → 8 days ago (beyond the 7-day policy window)
    - `critical_stale.json` → 8 days ago
  - Prints confirmation of each timestamp set with the human-readable date applied
  - Works on both macOS BSD `touch` and GNU `touch` (macOS is the target but note the difference)
  - Runs the timestamp updates atomically so the test runner can immediately follow

- [x] Create the osqueryi test runner at `tests/run_tests.sh`:
  - Must be executable (`chmod +x`)
  - Checks for `osqueryi` availability and exits with a clear message if not found (`brew install osquery` hint)
  - Runs `tests/update_timestamps.sh` first to set correct timestamps on all fixtures
  - For each fixture file and each query, runs the query against the fixture by:
    - Temporarily symlinking or copying the fixture to a known test path (e.g., `/tmp/bagel-test/results.json`)
    - Using `osqueryi` with `--line` or `--json` to execute the query
    - Checking whether rows were returned (for the policy query: rows = PASS, no rows = FAIL)
  - Validates and prints the expected vs actual result for each combination:

  | Fixture | Findings query | Policy query |
  |---|---|---|
  | no_critical_fresh | should return findings | should PASS (return rows) |
  | no_critical_stale | should return findings | should FAIL (return no rows) |
  | critical_fresh | should return findings incl. CRITICAL | should FAIL (return no rows) |
  | critical_stale | should return findings incl. CRITICAL | should FAIL (return no rows) |

  - Prints a clear PASS/FAIL for each test case with color (green/red) if the terminal supports it
  - Exits with code 0 if all assertions pass, non-zero if any fail
  - Cleans up any temp files created during the run

- [x] Run `tests/run_tests.sh` and fix any failures:
  - Execute the test runner
  - If osqueryi is not installed, at minimum run `sqlite3` syntax validation against each fixture to confirm the JSON is valid and the query SQL is parseable
  - Fix any query issues in `queries/bagel_findings.sql` or `queries/bagel_policy.sql` based on test results
  - Fix any fixture schema mismatches discovered during testing
  - All 8 test assertions (4 fixtures × 2 queries) must pass before this phase is complete
