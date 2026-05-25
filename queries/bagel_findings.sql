-- =============================================================================
-- bagel_findings.sql
-- Fleet live query: Bagel secret-scanning findings across managed Macs
--
-- PURPOSE
--   Returns every finding recorded in each local user's bagel results file,
--   with severity, rule ID, probe, file path, line number, additional
--   locations, and scan timestamp. Paste this query into Fleet → Queries →
--   New query to run it as a live query across your managed fleet.
--
-- FLEET USAGE
--   Live query: yes  |  Policy: no
--   Run this query to get a per-host table of all detected secrets.
--   Fleet aggregates results across all selected hosts in the UI.
--
-- HOW IT WORKS
--   1. Each CTE calls parse_json with a LIKE path covering all users.
--      parse_json requires a single, plan-time-known path constraint.
--      A LIKE literal satisfies this and covers all users at once.
--   2. findings_base: restricts to parent = 'findings/N' (direct finding
--      keys only). The extra NOT LIKE guard excludes sub-objects such as
--      findings/N/metadata and findings/N/locations, which would otherwise
--      produce empty rows containing only a timestamp.
--   3. finding_metadata: pulls line_number from findings[N].metadata.
--   4. finding_locations: pulls the optional locations[] array (additional
--      occurrences of the same secret) and collapses it to a comma-separated
--      string.
--   5. The outer SELECT joins the three CTEs and adds the file mtime.
--
-- NOTES ON BAGEL JSON SCHEMA
--   - findings[].severity          lowercase: critical, high, medium, low
--   - findings[].id                machine-readable rule name
--   - findings[].probe             scanner that found it (e.g. shell_history)
--   - findings[].path              primary file where the secret was found
--   - findings[].metadata.line_number  line in the primary file
--   - findings[].locations[]       optional: all file:path:line occurrences
--
-- REQUIRES
--   Fleet fleetd agent (parse_json is a Fleet extension, not core osquery)
-- =============================================================================

WITH findings_base AS (
    -- One group per finding element: parent is exactly 'findings/N'.
    -- NOT LIKE 'findings/%/%' excludes findings/N/metadata, findings/N/locations, etc.
    -- Without this guard those sub-groups produce NULL-filled rows with only a timestamp.
    SELECT
        pj.path,
        pj.parent,
        MAX(CASE WHEN pj.key = 'severity'    THEN pj.value END) AS severity,
        MAX(CASE WHEN pj.key = 'id'          THEN pj.value END) AS rule_id,
        MAX(CASE WHEN pj.key = 'probe'       THEN pj.value END) AS probe,
        MAX(CASE WHEN pj.key = 'path'        THEN pj.value END) AS file_path,
        MAX(CASE WHEN pj.key = 'fingerprint' THEN pj.value END) AS fingerprint,
        MAX(CASE WHEN pj.key = 'title'       THEN pj.value END) AS title
    FROM parse_json pj
    WHERE pj.path LIKE '/Users/%/Library/Logs/fleebag/results.json'
      AND pj.parent LIKE 'findings/%'
      AND pj.parent NOT LIKE 'findings/%/%'
    GROUP BY pj.path, pj.parent
),

finding_metadata AS (
    -- line_number lives at findings[N].metadata.line_number, not findings[N].line
    SELECT
        pj.path,
        SUBSTR(pj.parent, 1, LENGTH(pj.parent) - LENGTH('/metadata')) AS parent,
        MAX(CASE WHEN pj.key = 'line_number' THEN pj.value END)       AS line_number
    FROM parse_json pj
    WHERE pj.path LIKE '/Users/%/Library/Logs/fleebag/results.json'
      AND pj.parent LIKE 'findings/%/metadata'
    GROUP BY pj.path, pj.parent
),

finding_locations AS (
    -- locations[] is optional; present when the same secret appears in multiple places
    SELECT
        pj.path,
        SUBSTR(pj.parent, 1, LENGTH(pj.parent) - LENGTH('/locations')) AS parent,
        GROUP_CONCAT(pj.value, ', ')                                    AS locations
    FROM parse_json pj
    WHERE pj.path LIKE '/Users/%/Library/Logs/fleebag/results.json'
      AND pj.parent LIKE 'findings/%/locations'
    GROUP BY pj.path, pj.parent
)

SELECT
    REPLACE(REPLACE(fb.path, '/Library/Logs/fleebag/results.json', ''), '/Users/', '') AS username,
    fb.severity,
    fb.rule_id,
    fb.probe,
    fb.file_path,
    m.line_number,
    l.locations,
    fb.title,
    fb.fingerprint,
    datetime(f.mtime, 'unixepoch') AS last_scan
FROM findings_base fb
LEFT JOIN finding_metadata  m ON m.path = fb.path AND m.parent = fb.parent
LEFT JOIN finding_locations l ON l.path = fb.path AND l.parent = fb.parent
LEFT JOIN file f ON f.path = fb.path

ORDER BY
    CASE fb.severity
        WHEN 'critical' THEN 1
        WHEN 'high'     THEN 2
        WHEN 'medium'   THEN 3
        WHEN 'low'      THEN 4
        ELSE                 5
    END,
    fb.path;
