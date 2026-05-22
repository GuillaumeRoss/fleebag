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
--   1. Discovers real local users (uid >= 500, home under /Users/).
--   2. For each user, reads ~/Library/Logs/fleebag/results.json via parse_json.
--   3. Correlates finding fields (severity, id, path) via the parent column,
--      which identifies each finding array element (e.g. parent = 'findings/0').
--   4. Users with no results file or zero findings produce no rows — the query
--      does not error; parse_json simply returns nothing for missing paths.
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
    u.username,
    sev.value                                   AS severity,
    rid.value                                   AS rule_id,
    fp.value                                    AS file_path,
    ln.value                                    AS line_number,  -- NULL: not in bagel schema
    datetime(f.mtime, 'unixepoch')              AS last_scan
FROM users u

-- Each row from parse_json (aliased sev) is one leaf key-value pair.
-- Filtering on key = 'severity' and parent LIKE 'findings/%' gives one row
-- per finding. This join also acts as the "file exists" guard — if
-- results.json is missing, parse_json returns no rows and the user is skipped.
--
-- NOTE: the path expression is inlined here (not via a CTE) so that
-- osquery can push the per-row constraint directly to parse_json's virtual
-- table implementation. A CTE-derived column breaks constraint pushdown.
JOIN parse_json sev
    ON  sev.path   = (u.directory || '/Library/Logs/fleebag/results.json')
    AND sev.key    = 'severity'
    AND sev.parent LIKE 'findings/%'

-- Correlate the rule id for the same finding array element via parent match.
JOIN parse_json rid
    ON  rid.path   = (u.directory || '/Library/Logs/fleebag/results.json')
    AND rid.key    = 'id'
    AND rid.parent = sev.parent

-- File path of the affected config/file (present for most findings).
LEFT JOIN parse_json fp
    ON  fp.path   = (u.directory || '/Library/Logs/fleebag/results.json')
    AND fp.key    = 'path'
    AND fp.parent = sev.parent

-- Line number — not in bagel's documented schema; included for future-proofing.
LEFT JOIN parse_json ln
    ON  ln.path   = (u.directory || '/Library/Logs/fleebag/results.json')
    AND ln.key    = 'line'
    AND ln.parent = sev.parent

-- File metadata for the results file (modification time = last scan time).
-- LEFT JOIN so the query still returns rows even if the stat is unavailable.
LEFT JOIN file f
    ON f.path = (u.directory || '/Library/Logs/fleebag/results.json')

WHERE u.uid >= 500
  AND u.directory LIKE '/Users/%'
  AND u.directory != '/Users/Shared'

ORDER BY
    -- Sort critical findings first, then by descending severity.
    CASE sev.value
        WHEN 'critical' THEN 1
        WHEN 'high'     THEN 2
        WHEN 'medium'   THEN 3
        WHEN 'low'      THEN 4
        ELSE                 5
    END,
    u.username;
