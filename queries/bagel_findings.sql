-- =============================================================================
-- bagel_findings.sql
-- Fleet live query: Bagel secret-scanning findings across managed Macs
--
-- PURPOSE
--   Returns every finding recorded in each local user's bagel results file,
--   with severity, rule ID, file path, and scan timestamp. Paste this query
--   into Fleet → Queries → New query to run it as a live query across your
--   managed fleet.
--
-- FLEET USAGE
--   Live query: yes  |  Policy: no
--   Run this query to get a per-host table of all detected secrets.
--   Fleet aggregates results across all selected hosts in the UI.
--
-- HOW IT WORKS
--   1. Calls parse_json ONCE with a glob path covering all users.
--      parse_json requires a single, plan-time-known path constraint; a
--      per-row correlated expression (e.g. from a JOIN with users) is
--      resolved too late and triggers:
--        "The parse_json table requires that you specify a single constraint for path"
--      A glob literal satisfies this requirement and covers all users.
--   2. Groups rows by (path, parent) — one group = one finding array element
--      (e.g. parent = 'findings/0') — and pivots key→value pairs into columns.
--   3. Extracts the username from the resolved path string.
--   4. Users with no results file produce no rows.
--
-- NOTES ON BAGEL JSON SCHEMA
--   - findings[].severity values are lowercase: critical, high, medium, low
--   - findings[].id  is the machine-readable rule name
--   - findings[].path is the file/config location where the secret was found
--   - findings[].line is NOT in bagel's schema; line_number will be NULL
--
-- REQUIRES
--   Fleet fleetd agent (parse_json is a Fleet extension, not core osquery)
-- =============================================================================

SELECT
    -- Extract username from the resolved path: /Users/USERNAME/Library/Logs/...
    REPLACE(REPLACE(pj.path, '/Library/Logs/fleebag/results.json', ''), '/Users/', '') AS username,
    MAX(CASE WHEN pj.key = 'severity' THEN pj.value END) AS severity,
    MAX(CASE WHEN pj.key = 'id'       THEN pj.value END) AS rule_id,
    MAX(CASE WHEN pj.key = 'path'     THEN pj.value END) AS file_path,
    MAX(CASE WHEN pj.key = 'line'     THEN pj.value END) AS line_number,  -- NULL: not in bagel schema
    datetime(f.mtime, 'unixepoch')                        AS last_scan
FROM parse_json pj

-- LEFT JOIN on the exact resolved path (not a glob) — one row per file.
LEFT JOIN file f ON f.path = pj.path

-- Single glob constraint: parse_json expands this to all matching files.
WHERE pj.path   = '/Users/*/Library/Logs/fleebag/results.json'
  AND pj.parent LIKE 'findings/%'

-- One group = one finding array element across all its key-value pairs.
GROUP BY pj.path, pj.parent

ORDER BY
    CASE MAX(CASE WHEN pj.key = 'severity' THEN pj.value END)
        WHEN 'critical' THEN 1
        WHEN 'high'     THEN 2
        WHEN 'medium'   THEN 3
        WHEN 'low'      THEN 4
        ELSE                 5
    END,
    pj.path;
