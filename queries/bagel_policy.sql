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

WITH local_users AS (
    -- Discover all real macOS local users and build their results file paths.
    -- Excludes /Users/Shared (not a user account; no LaunchAgent runs there)
    SELECT
        username,
        directory || '/Library/Logs/fleebag/results.json' AS results_path
    FROM users
    WHERE uid  >= 500              -- Exclude system/service accounts
      AND directory LIKE '/Users/%' -- macOS user home directories only
      AND directory != '/Users/Shared'
),

valid_users AS (
    -- A user is "valid" when all three policy conditions are satisfied.
    SELECT lu.username
    FROM local_users lu

    -- Condition 1 + 2: results file must exist AND be recent.
    -- INNER JOIN on file means: if the file is missing, zero rows → user excluded.
    JOIN file f
        ON f.path = lu.results_path
    WHERE
        -- Condition 2: file was modified within the last 7 days (604800 seconds).
        -- Increase this value to allow a longer scan window, e.g. 1209600 = 14 days.
        (strftime('%s', 'now') - f.mtime) < 604800

        -- Condition 3: no findings with severity = 'critical'.
        -- Severity values in bagel JSON are lowercase (critical, high, medium, low).
        AND NOT EXISTS (
            SELECT 1
            FROM parse_json pj
            WHERE pj.path   = lu.results_path
              AND pj.key    = 'severity'
              AND pj.parent LIKE 'findings/%'  -- Scoped to findings array only
              AND pj.value  = 'critical'        -- Lowercase as per bagel schema
        )
)

-- Return exactly one row when every local user satisfies all conditions.
-- Comparing counts ensures a device with partial compliance (one user OK,
-- another user failing) still results in a FAIL (0 rows returned).
SELECT
    'pass'      AS result,
    vu.username AS username
FROM valid_users vu
WHERE
    -- All local users must be in valid_users.
    (SELECT COUNT(*) FROM valid_users)  = (SELECT COUNT(*) FROM local_users)
    -- Guard: at least one local user must exist (avoids a false PASS on
    -- devices with no uid >= 500 users, which is theoretically impossible
    -- on a managed Mac but defensive to check).
    AND (SELECT COUNT(*) FROM local_users) > 0
LIMIT 1;
