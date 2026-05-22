-- =============================================================================
-- bagel_policy.sql
-- Fleet policy query: Bagel scan is current and no critical secrets detected
--
-- PURPOSE
--   Evaluates whether a device is in a healthy posture with respect to
--   bagel secret scanning. Paste this query into Fleet → Policies → New policy.
--
-- FLEET POLICY SEMANTICS
--   PASS  = query returns ≥ 1 row  (host is compliant)
--   FAIL  = query returns 0 rows   (host is non-compliant)
--
-- PASS CONDITIONS (all must be true for every local user on this host)
--   1. results.json exists at ~/Library/Logs/fleebag/results.json
--   2. results.json was modified within the last 7 days (604800 seconds)
--   3. No finding in results.json has severity = 'critical'
--
-- FAIL CONDITIONS (any of the following triggers a fail)
--   - results.json does not exist for any local user (uid >= 500)
--   - results.json has not been modified in > 7 days  (stale / agent not running)
--   - One or more findings with severity = 'critical' are present
--   - No local users exist with uid >= 500 (edge case; treat as fail)
--
-- RETURN VALUE
--   Single row: result = 'pass', username = <first passing user>
--   The row is only returned when ALL local users pass every condition above.
--
-- PER-HOST BEHAVIOUR
--   Fleet runs this query on each host independently. The query does not
--   aggregate across hosts; Fleet handles cross-host policy roll-up in the UI.
--
-- CUSTOMISATION
--   To change the stale-scan threshold, replace 604800 with the desired
--   number of seconds (e.g. 86400 = 1 day, 1209600 = 14 days).
--
-- REQUIRES
--   Fleet fleetd agent (parse_json is a Fleet extension, not core osquery)
-- =============================================================================

-- NOTE: this query avoids CTEs for path generation. Fleet's parse_json virtual
-- table requires a per-row correlated path constraint; a CTE-derived column
-- breaks osquery's constraint pushdown and triggers the error:
--   "The parse_json table requires that you specify a single constraint for path"
-- The path expression is therefore inlined everywhere it is used.

SELECT
    'pass'      AS result,
    u.username  AS username
FROM users u
WHERE u.uid  >= 500
  AND u.directory LIKE '/Users/%'
  AND u.directory != '/Users/Shared'

  -- Condition 1 + 2: results file must exist AND be recent.
  AND EXISTS (
      SELECT 1
      FROM file f
      WHERE f.path = (u.directory || '/Library/Logs/fleebag/results.json')
        -- Condition 2: file was modified within the last 7 days (604800 seconds).
        -- Increase this value to allow a longer scan window, e.g. 1209600 = 14 days.
        AND (strftime('%s', 'now') - f.mtime) < 604800
  )

  -- Condition 3: no findings with severity = 'critical'.
  -- Severity values in bagel JSON are lowercase (critical, high, medium, low).
  AND NOT EXISTS (
      SELECT 1
      FROM parse_json pj
      WHERE pj.path   = (u.directory || '/Library/Logs/fleebag/results.json')
        AND pj.key    = 'severity'
        AND pj.parent LIKE 'findings/%'  -- Scoped to findings array only
        AND pj.value  = 'critical'        -- Lowercase as per bagel schema
  )

  -- All local users must pass: no other user on this device is non-compliant.
  -- A device with partial compliance (one user OK, another failing) is a FAIL.
  AND NOT EXISTS (
      SELECT 1
      FROM users u2
      WHERE u2.uid  >= 500
        AND u2.directory LIKE '/Users/%'
        AND u2.directory != '/Users/Shared'
        AND (
          -- u2 fails condition 1+2: file missing or stale
          NOT EXISTS (
              SELECT 1 FROM file f2
              WHERE f2.path = (u2.directory || '/Library/Logs/fleebag/results.json')
                AND (strftime('%s', 'now') - f2.mtime) < 604800
          )
          OR
          -- u2 fails condition 3: has a critical finding
          EXISTS (
              SELECT 1 FROM parse_json pj2
              WHERE pj2.path   = (u2.directory || '/Library/Logs/fleebag/results.json')
                AND pj2.key    = 'severity'
                AND pj2.parent LIKE 'findings/%'
                AND pj2.value  = 'critical'
          )
        )
  )

LIMIT 1;
