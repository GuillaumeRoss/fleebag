#!/usr/bin/env bash
# =============================================================================
# update_timestamps.sh
# Set fixture file modification times to simulate fresh and stale scan results.
#
# Fresh fixtures  → current time (now)
# Stale fixtures  → 8 days ago (beyond the 7-day policy window)
#
# Works on macOS (BSD date/touch) and Linux (GNU date/touch).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

FRESH_FILES=(
    "$FIXTURES_DIR/no_critical_fresh.json"
    "$FIXTURES_DIR/critical_fresh.json"
)

STALE_FILES=(
    "$FIXTURES_DIR/no_critical_stale.json"
    "$FIXTURES_DIR/critical_stale.json"
)

# ---------------------------------------------------------------------------
# Detect date variant (BSD = macOS, GNU = Linux)
# ---------------------------------------------------------------------------
if date -v-1d >/dev/null 2>&1; then
    DATE_VARIANT="bsd"
else
    DATE_VARIANT="gnu"
fi

# ---------------------------------------------------------------------------
# Compute timestamps
# ---------------------------------------------------------------------------
NOW=$(date +%s)

if [ "$DATE_VARIANT" = "bsd" ]; then
    # macOS: touch -t format is [[CC]YY]MMDDhhmm[.ss]
    STALE_TOUCH=$(date -v-8d +"%Y%m%d%H%M")
    FRESH_HUMAN=$(date)
    STALE_HUMAN=$(date -v-8d)
else
    # GNU/Linux
    STALE_TOUCH="8 days ago"
    FRESH_HUMAN=$(date)
    STALE_HUMAN=$(date -d "8 days ago")
fi

# ---------------------------------------------------------------------------
# Apply timestamps
# ---------------------------------------------------------------------------
echo "==> Setting FRESH timestamps (now: $FRESH_HUMAN)"
for f in "${FRESH_FILES[@]}"; do
    touch "$f"
    echo "    [fresh] $(basename "$f")"
done

echo ""
echo "==> Setting STALE timestamps (8 days ago: $STALE_HUMAN)"
for f in "${STALE_FILES[@]}"; do
    if [ "$DATE_VARIANT" = "bsd" ]; then
        touch -t "$STALE_TOUCH" "$f"
    else
        touch -d "$STALE_TOUCH" "$f"
    fi
    echo "    [stale] $(basename "$f")"
done

echo ""
echo "==> Done. All fixture timestamps updated."
