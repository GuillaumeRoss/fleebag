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
-- HOW IT WORKS
--   parse_json requires a single, plan-time-known path constraint. A per-row
--   correlated expression resolved at runtime triggers:
--     "The parse_json table requires that you specify a single constraint for path"
--   This query therefore uses a glob literal for all parse_json and file lookups:
--     '/Users/*/Library/Logs/fleebag/results.json'
--   The "all users have fresh files" check compares:
--     COUNT of local users (from the users table)
--     COUNT of fresh results files matching the glob (from the file table)
--   If those counts are equal and non-zero, every user has a fresh file.
--
-- CUSTOMISATION
--   To change the stale-scan threshold, replace 604800 with the desired
--   number of seconds (e.g. 86400 = 1 day, 1209600 = 14 days).
--
-- REQUIRES
--   Fleet fleetd agent (parse_json is a Fleet extension, not core osquery)
-- =============================================================================

SELECT 'pass' AS result
WHERE
    -- Guard: at least one local user must exist.
    (SELECT COUNT(*) FROM users
     WHERE uid >= 500
       AND directory LIKE '/Users/%'
       AND directory != '/Users/Shared') > 0

    -- Conditions 1 + 2: every local user must have a fresh results file.
    -- The count of fresh files (via glob) must equal the count of local users.
    -- If any user's file is missing or stale the counts diverge → FAIL.
    AND (SELECT COUNT(*) FROM users
         WHERE uid >= 500
           AND directory LIKE '/Users/%'
           AND directory != '/Users/Shared')
      = (SELECT COUNT(*) FROM file
         WHERE path = '/Users/*/Library/Logs/fleebag/results.json'
           -- Condition 2: modified within the last 7 days (604800 seconds).
           -- Increase this value for a longer window, e.g. 1209600 = 14 days.
           AND (strftime('%s', 'now') - mtime) < 604800)

    -- Condition 3: no findings with severity = 'critical' across any user's file.
    AND 0 = (SELECT COUNT(*) FROM parse_json
             WHERE path   = '/Users/*/Library/Logs/fleebag/results.json'
               AND key    = 'severity'
               AND parent LIKE 'findings/%'
               AND value  = 'critical');
