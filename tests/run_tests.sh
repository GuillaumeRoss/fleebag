#!/usr/bin/env bash
# =============================================================================
# run_tests.sh
# Validate fleebag osquery queries against all fixture files.
#
# Tests 4 fixtures × 2 queries = 8 assertions total.
#
# FINDINGS QUERY  — should always return rows (all 4 fixtures)
# POLICY QUERY    — PASS (rows returned) or FAIL (no rows) per fixture:
#
#   Fixture              Findings  Policy
#   no_critical_fresh    rows      PASS  (fresh + no critical)
#   no_critical_stale    rows      FAIL  (stale)
#   critical_fresh       rows      FAIL  (has critical)
#   critical_stale       rows      FAIL  (stale + has critical)
#
# APPROACH
#   Fleet's parse_json virtual table is a Fleet-specific extension not
#   available in stock osqueryi. This runner tests the equivalent logic
#   using Python 3 (standard on macOS) for JSON parsing and shell stat
#   for mtime, mirroring exactly what the production SQL queries do.
#
#   If osqueryi is installed, a quick smoke test is also run to confirm
#   osquery can read the file table for each fixture path.
#
# REQUIRES
#   python3 (standard on macOS 10.15+)
#   stat    (standard BSD/GNU coreutils)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TMP_DIR="/tmp/fleebag-test"

# ---------------------------------------------------------------------------
# Colour helpers (only when stdout is a terminal)
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

pass() { echo -e "  ${GREEN}PASS${NC}  $1"; }
fail() { echo -e "  ${RED}FAIL${NC}  $1"; }
info() { echo -e "  ${YELLOW}INFO${NC}  $1"; }

# ---------------------------------------------------------------------------
# Prerequisite checks
# ---------------------------------------------------------------------------
echo "=== fleebag osquery test runner ==="
echo ""

if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required but not found. Install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

OSQUERYI=""
if command -v osqueryi >/dev/null 2>&1; then
    OSQUERYI=$(command -v osqueryi)
    info "osqueryi found at $OSQUERYI (smoke tests will run)"
else
    info "osqueryi not found — skipping osqueryi smoke tests"
    info "To install: brew install osquery"
fi

echo ""

# ---------------------------------------------------------------------------
# Step 1: Set fixture timestamps
# ---------------------------------------------------------------------------
echo "=== Step 1: Update fixture timestamps ==="
bash "$SCRIPT_DIR/update_timestamps.sh"
echo ""

# ---------------------------------------------------------------------------
# Step 2: Set up temp directory
# ---------------------------------------------------------------------------
mkdir -p "$TMP_DIR"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Helper: count findings in a fixture
# ---------------------------------------------------------------------------
count_findings() {
    local fixture="$1"
    python3 - "$fixture" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
print(len(data.get("findings", [])))
PYEOF
}

# Helper: does fixture contain a critical finding?
has_critical() {
    local fixture="$1"
    python3 - "$fixture" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
findings = data.get("findings", [])
print("yes" if any(f.get("severity") == "critical" for f in findings) else "no")
PYEOF
}

# Helper: list all severities present
list_severities() {
    local fixture="$1"
    python3 - "$fixture" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
sevs = sorted({f.get("severity","?") for f in data.get("findings", [])})
print(", ".join(sevs))
PYEOF
}

# Helper: is the fixture file mtime within the last 7 days?
is_fresh() {
    local fixture="$1"
    local mtime now age
    # BSD stat (macOS) uses -f %m; GNU stat uses -c %Y
    mtime=$(stat -f %m "$fixture" 2>/dev/null || stat -c %Y "$fixture" 2>/dev/null)
    now=$(date +%s)
    age=$(( now - mtime ))
    if [ "$age" -lt 604800 ]; then
        echo "yes"
    else
        echo "no"
    fi
}

# ---------------------------------------------------------------------------
# Test runner state
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
TOTAL=0

assert_pass() {
    local label="$1" actual="$2"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" = "pass" ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        pass "$label"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        fail "$label  (expected PASS, got FAIL)"
    fi
}

assert_fail() {
    local label="$1" actual="$2"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" = "fail" ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        pass "$label"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        fail "$label  (expected FAIL, got PASS)"
    fi
}

assert_rows() {
    local label="$1" count="$2"
    TOTAL=$((TOTAL + 1))
    if [ "$count" -gt 0 ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        pass "$label  ($count findings)"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        fail "$label  (expected findings, got 0 rows)"
    fi
}

# ---------------------------------------------------------------------------
# Per-fixture tests
# ---------------------------------------------------------------------------
run_fixture_tests() {
    local name="$1"         # fixture base name (no .json)
    local expect_policy="$2" # "pass" or "fail"
    local fixture="$FIXTURES_DIR/${name}.json"

    echo "--- $name ---"

    # Copy fixture to well-known test path (mirrors production path symlink approach)
    cp "$fixture" "$TMP_DIR/results.json"

    # --- Findings query test ---
    local findings_count
    findings_count=$(count_findings "$fixture")
    assert_rows "findings query returns rows" "$findings_count"

    # Verify severities for informational output
    local sevs
    sevs=$(list_severities "$fixture")
    echo "        severities present: $sevs"

    # --- Policy query test ---
    # Replicate bagel_policy.sql logic:
    #   PASS = file exists + fresh (< 7 days) + no critical findings
    #   FAIL = any of: missing, stale, has critical
    local fresh critical policy_result
    fresh=$(is_fresh "$fixture")
    critical=$(has_critical "$fixture")

    if [ "$fresh" = "yes" ] && [ "$critical" = "no" ]; then
        policy_result="pass"
    else
        policy_result="fail"
    fi

    local stale_note=""
    [ "$fresh" = "no" ] && stale_note=" [stale]"
    local crit_note=""
    [ "$critical" = "yes" ] && crit_note=" [has-critical]"
    local policy_label="policy query result${stale_note}${crit_note}"

    if [ "$expect_policy" = "pass" ]; then
        assert_pass "$policy_label" "$policy_result"
    else
        assert_fail "$policy_label" "$policy_result"
    fi

    # --- osqueryi smoke test (if available) ---
    if [ -n "$OSQUERYI" ]; then
        # Run a minimal osquery query that exercises the file table on the fixture.
        # parse_json is a Fleet extension so we test what osqueryi CAN do:
        # confirm the file exists and mtime is readable via the file table.
        local smoke_out
        smoke_out=$("$OSQUERYI" --json \
            "SELECT path, mtime, size FROM file WHERE path = '$TMP_DIR/results.json';" \
            2>/dev/null || true)
        if echo "$smoke_out" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
            info "osqueryi file table smoke test passed for $name"
        else
            info "osqueryi file table returned no rows for $name (fixture may not be at expected path)"
        fi
    fi

    echo ""
}

# ---------------------------------------------------------------------------
# Step 3: Run all fixture tests
# ---------------------------------------------------------------------------
echo "=== Step 3: Running 8 assertions (4 fixtures × 2 queries) ==="
echo ""

run_fixture_tests "no_critical_fresh" "pass"
run_fixture_tests "no_critical_stale" "fail"
run_fixture_tests "critical_fresh"    "fail"
run_fixture_tests "critical_stale"    "fail"

# ---------------------------------------------------------------------------
# Step 4: Summary
# ---------------------------------------------------------------------------
echo "=== Results: $PASS_COUNT/$TOTAL passed ==="
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}All $TOTAL assertions passed.${NC}"
    echo ""
    exit 0
else
    echo -e "${RED}$FAIL_COUNT assertion(s) failed.${NC}"
    echo ""
    exit 1
fi
