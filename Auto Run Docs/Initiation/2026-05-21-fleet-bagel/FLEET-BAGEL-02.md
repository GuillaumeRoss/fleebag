# Phase 02: Fleet/osquery SQL Queries

This phase creates the two Fleet SQL query files that give the project its operational value. The first query provides a readable table of all secrets bagel has found across managed machines. The second is a policy query that fails if any CRITICAL-severity secret is detected or if the results file has not been updated in the past seven days — giving Fleet operators a clear, auditable signal about the security posture of each device. Both queries are written to work with Fleet's extended osquery capabilities using the `parse_json` virtual table.

## Tasks

- [x] Research Fleet's JSON parsing capabilities for osquery before writing any SQL:
  - Read `Auto Run Docs/Initiation/Working/bagel-research.md` to confirm the bagel JSON output schema (from Phase 01 research)
  - Research how Fleet/osquery reads and parses JSON files — the user specified the `parse_json` table; look for Fleet documentation on this virtual table and its syntax (e.g. `SELECT * FROM parse_json(data, path)` or similar)
  - Confirm the correct osquery table and function for:
    - Reading file contents (likely via the `file` table's `content` column or a Fleet extension)
    - Iterating JSON arrays (`json_each` SQLite function)
    - Getting file modification time (the `stat` table or `file` table `mtime` column)
    - Getting all users' home directories (the `users` table, filtering for real users with `uid >= 500` and a `/Users/` home directory)
  - Document the confirmed approach in `Auto Run Docs/Initiation/Working/osquery-research.md` with the exact syntax that works in Fleet
  - If `parse_json` is a Fleet-specific virtual table, note its exact signature and required columns
  <!-- COMPLETED 2026-05-21: parse_json is confirmed Fleet-specific (fleetd extension, not core osquery).
       Columns: path (required WHERE), key, fullkey, parent, value.
       Uses forward-slash separators: parent='findings/0' for array element 0, key='severity'.
       Correlation between finding fields done via parent column join.
       file table provides mtime (Unix epoch). users table with uid>=500 + LIKE '/Users/%'.
       Full findings documented in Auto Run Docs/Initiation/Working/osquery-research.md. -->

- [x] Create the findings listing query at `queries/bagel_findings.sql`:
  - Query must join the `users` table (real local users, `uid >= 500`, home directory starts with `/Users/`) to discover per-user results file paths
  - For each user, read `<home>/Library/Logs/bagel/results.json` and parse the JSON
  - Use the correct Fleet/osquery JSON reading approach confirmed in research
  - Output columns (human-readable for the Fleet UI):
    - `username` — macOS username
    - `severity` — finding severity (e.g., CRITICAL, HIGH, MEDIUM, LOW)
    - `rule_id` or `rule_name` — type of secret detected
    - `file_path` — the file where the secret was found (from bagel output)
    - `line_number` — line number if available
    - `last_scan` — formatted modification time of the results file (ISO 8601 or Unix timestamp, whichever osquery provides)
  - Handle the case where the results file does not exist (LEFT JOIN or a guard so the query does not error)
  - Add a comment block at the top of the file explaining the query's purpose and expected Fleet usage (paste into Fleet as a live query)
  - Order results by `severity` (CRITICAL first), then `username`
  <!-- COMPLETED 2026-05-21: Created queries/bagel_findings.sql.
       INNER JOIN on parse_json severity row acts as existence guard (no file = no rows, no error).
       parse_json self-joins on parent column correlate rule_id, file_path, line.
       line_number always NULL (not in bagel schema). last_scan via datetime(file.mtime,'unixepoch'). -->

- [x] Create the policy query at `queries/bagel_policy.sql`:
  - This query is used as a Fleet policy: it must return **at least one row** to PASS and **zero rows** to FAIL
  - The policy PASSES (returns 1 row) when ALL of the following are true for the current user:
    - The results file exists at `<home>/Library/Logs/bagel/results.json`
    - The file's modification time is within the last 7 days (604800 seconds)
    - No findings with severity `CRITICAL` are present in the JSON
  - The policy FAILS (returns zero rows) when ANY of the following is true:
    - The results file does not exist
    - The file's mtime is older than 7 days
    - One or more CRITICAL-severity findings exist
  - Return a single row with columns `result` (value: `'pass'`) and `username` when passing — Fleet will count this row as a pass
  - Add a comment block at the top explaining the pass/fail logic and how to interpret the policy in Fleet
  - Include inline SQL comments explaining each condition so operators can modify thresholds easily
  - Note: Policy queries in Fleet run per-host; the query should handle a single device's users (not aggregate across hosts — Fleet handles the per-host aggregation)
  <!-- COMPLETED 2026-05-21: Created queries/bagel_policy.sql.
       Two CTEs: local_users (all uid>=500 users) and valid_users (those meeting all conditions).
       Final SELECT returns 1 row only when COUNT(valid_users) = COUNT(local_users) > 0.
       Severity check uses 'critical' (lowercase) matching bagel's schema. 7-day threshold is
       configurable via inline comment. Handles multi-user Macs correctly. -->

- [x] Validate both queries syntactically:
  - Run each query against a test SQLite database using `osqueryi --line` or `sqlite3` with a minimal schema mock if osqueryi is available on the system
  - At minimum, run `sqlite3 :memory: < queries/bagel_findings.sql` and confirm no syntax errors (even if results are empty without real osquery tables)
  - If osqueryi is installed (`which osqueryi`), run each query with `--json` flag and confirm they parse without error
  - Fix any syntax issues before completing this phase
  <!-- COMPLETED 2026-05-21: Both queries validated with sqlite3 :memory: using mock CREATE TABLE schema.
       Also ran full logic tests with populated mock data confirming:
       - findings query returns results ordered critical-first
       - policy returns 0 rows when critical finding present
       - policy returns 0 rows when scan is 8 days old (> 7-day threshold)
       - policy returns 1 row ('pass') when all conditions met
       Note: parse_json is Fleet-only so osqueryi returns "no such table: parse_json" — expected. -->
