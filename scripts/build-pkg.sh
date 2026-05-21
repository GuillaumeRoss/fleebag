#!/usr/bin/env bash
# =============================================================================
# build-pkg.sh — Build the fleet-bagel macOS installer package
#
# Usage:
#   bash scripts/build-pkg.sh
#
# Requirements:
#   - macOS with pkgbuild (Xcode Command Line Tools)
#   - python3 (pre-installed on macOS)
#   - curl (pre-installed on macOS)
#   - Internet access to api.github.com and github.com
#
# What it does:
#   1. Detects host architecture (arm64 or x86_64)
#   2. Fetches the latest bagel release metadata from the GitHub API
#   3. Downloads the arch-specific bagel tarball and extracts the binary
#   4. Runs pkgbuild to produce build/bagel-<version>.pkg
#
# The resulting .pkg installs:
#   /usr/local/bin/bagel              — bagel binary
#   /usr/local/libexec/bagel-scan     — wrapper scan script
#   /etc/bagel/bagel.yaml             — configuration template
#   /Library/LaunchAgents/io.boostsecurity.bagel.plist
#
# The postinstall script sets permissions and bootstraps the LaunchAgent.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Paths (relative to repo root)
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAYLOAD_DIR="$REPO_ROOT/pkg/payload"
SCRIPTS_DIR="$REPO_ROOT/pkg/scripts"
BIN_DIR="$PAYLOAD_DIR/usr/local/bin"
BUILD_DIR="$REPO_ROOT/build"

GITHUB_API="https://api.github.com/repos/boostsecurityio/bagel/releases/latest"

# ---------------------------------------------------------------------------
# Detect architecture
# ---------------------------------------------------------------------------
ARCH="$(uname -m)"
echo "[build-pkg] Host architecture: $ARCH"

if [[ "$ARCH" != "arm64" && "$ARCH" != "x86_64" ]]; then
  echo "[build-pkg] ERROR: Unsupported architecture '$ARCH'. Expected arm64 or x86_64." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Fetch latest release metadata from GitHub API
# ---------------------------------------------------------------------------
echo "[build-pkg] Fetching latest release metadata from GitHub API..."
RELEASE_JSON="$(curl -fsSL "$GITHUB_API")"

# Parse the tag name (e.g. "v0.7.0") and derive version without leading "v"
VERSION="$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
print(data['tag_name'].lstrip('v'))
" <<< "$RELEASE_JSON")"

echo "[build-pkg] Latest release version: $VERSION"

# Build the expected asset name and find its download URL
ASSET_NAME="bagel_Darwin_${ARCH}.tar.gz"

DOWNLOAD_URL="$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
assets = data.get('assets', [])
name = 'bagel_Darwin_${ARCH}.tar.gz'
for a in assets:
    if a.get('name') == name:
        print(a['browser_download_url'])
        sys.exit(0)
# Fallback: construct URL from tag
tag = data['tag_name']
print(f'https://github.com/boostsecurityio/bagel/releases/download/{tag}/{name}')
" <<< "$RELEASE_JSON")"

echo "[build-pkg] Download URL: $DOWNLOAD_URL"

# ---------------------------------------------------------------------------
# Download and extract the bagel binary
# ---------------------------------------------------------------------------
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

TARBALL="$TMPDIR/$ASSET_NAME"
echo "[build-pkg] Downloading $ASSET_NAME..."
curl -fsSL -o "$TARBALL" "$DOWNLOAD_URL"

echo "[build-pkg] Extracting bagel binary..."
tar -xzf "$TARBALL" -C "$TMPDIR" bagel

# Place binary in payload
mkdir -p "$BIN_DIR"
cp "$TMPDIR/bagel" "$BIN_DIR/bagel"
chmod 755 "$BIN_DIR/bagel"
echo "[build-pkg] Binary placed at $BIN_DIR/bagel"

# ---------------------------------------------------------------------------
# Create build output directory
# ---------------------------------------------------------------------------
mkdir -p "$BUILD_DIR"
PKG_PATH="$BUILD_DIR/bagel-${VERSION}.pkg"

# ---------------------------------------------------------------------------
# Run pkgbuild
# ---------------------------------------------------------------------------
echo "[build-pkg] Running pkgbuild..."
pkgbuild \
  --root "$PAYLOAD_DIR" \
  --scripts "$SCRIPTS_DIR" \
  --identifier "io.boostsecurity.bagel" \
  --version "$VERSION" \
  --install-location "/" \
  "$PKG_PATH"

echo ""
echo "[build-pkg] SUCCESS: Package built at:"
echo "  $PKG_PATH"
