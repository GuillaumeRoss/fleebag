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
-- PASS CONDITIONS (both must be true)
--   1. At least one results.json under /Users/ was modified within the last
--      1 week — confirming the fleebag agent ran recently for some user.
--   2. No results.json under /Users/ contains a finding with severity = 'critical'.
--
-- FAIL CONDITIONS (any of the following triggers a fail)
--   - No results.json exists for any user
--   - The most recent results.json is older than 1 week (stale / agent not running)
--   - Any results.json contains a finding with severity = 'critical'
--
-- HOW IT WORKS
--   parse_json requires a single, plan-time-known path constraint. A per-row
--   correlated expression resolved at runtime triggers:
--     "The parse_json table requires that you specify a single constraint for path"
--   This query therefore uses a glob literal for all parse_json and file lookups:
--     '/Users/*/Library/Logs/fleebag/results.json'
--
--   Condition 1 is satisfied when the file table glob returns at least one
--   row with mtime within the last week — i.e. the agent ran recently.
--   Condition 2 is satisfied when parse_json finds zero severity=critical rows.
--
-- CUSTOMISATION
--   To change the stale-scan threshold, replace 604800 with the desired
--   number of seconds (e.g. 86400 = 1 day, 1209600 = 2 weeks).
--
-- REQUIRES
--   Fleet fleetd agent (parse_json is a Fleet extension, not core osquery)
-- =============================================================================

SELECT 1
WHERE
    -- Condition 1: at least one results file was written within the last 1 week.
    -- 604800 = 7 * 24 * 3600 (1 week in seconds).
    EXISTS (
        SELECT 1 FROM file
        WHERE path = '/Users/*/Library/Logs/fleebag/results.json'
          AND (strftime('%s', 'now') - mtime) < 604800
    )

    -- Condition 2: no critical findings in any user's results file.
    AND NOT EXISTS (
        SELECT 1 FROM parse_json
        WHERE path   = '/Users/*/Library/Logs/fleebag/results.json'
          AND key    = 'severity'
          AND parent LIKE 'findings/%'
          AND value  = 'critical'
    );
