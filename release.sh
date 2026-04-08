#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_ONLY=false
VERSION=""

# Parse flags
for arg in "$@"; do
  case "$arg" in
    --build-only)  BUILD_ONLY=true ;;
    --*)           echo "Unknown flag: $arg"; exit 1 ;;
    *)             VERSION="$arg" ;;
  esac
done

if [ "$BUILD_ONLY" = false ] && [ -z "$VERSION" ]; then
  echo "Usage: ./release.sh <version> [--build-only]"
  echo ""
  echo "  --build-only  Build Swift binary + TS SDK only (no GitHub release)"
  echo ""
  echo "npm publish is automatic via GitHub Actions when a release is created."
  exit 1
fi

SWIFT_DIR="$SCRIPT_DIR/packages/darwinkit-swift"
SDK_DIR="$SCRIPT_DIR/packages/darwinkit"
TARBALL="darwinkit-macos-arm64.tar.gz"
GH_REPO="genesiscz/darwinkit-swift"

# ── Build binary (arm64 only) ──────────────────────────
{
  echo "Building arm64 binary..."
  cd "$SWIFT_DIR"
  swift build -c release --arch arm64
  cd "$SCRIPT_DIR"
}

BINARY="$SWIFT_DIR/.build/arm64-apple-macosx/release/darwinkit"

if [ ! -f "$BINARY" ]; then
  echo "Error: Binary not found at $BINARY"
  echo "Run without --npm-only first, or build manually."
  exit 1
fi

# ── Create .app bundle ──────────────────────────────────
# UNUserNotificationCenter requires a .app bundle with Info.plist
# for notification permissions to work on macOS.
create_app_bundle() {
  local src_binary="$1"
  local dest_dir="$2"
  local app_dir="$dest_dir/DarwinKit.app/Contents"

  echo "Creating .app bundle..."
  mkdir -p "$app_dir/MacOS"
  cp "$src_binary" "$app_dir/MacOS/darwinkit"
  chmod 755 "$app_dir/MacOS/darwinkit"
  cp "$SWIFT_DIR/Sources/DarwinKit/Info.plist" "$app_dir/Info.plist"

  # Ad-hoc codesign so macOS accepts the bundle
  codesign --force --sign - "$app_dir/MacOS/darwinkit" 2>/dev/null || true

  echo "App bundle created: $dest_dir/DarwinKit.app"
}

# ── Build-only mode ───────────────────────────────────
if [ "$BUILD_ONLY" = true ]; then
  echo "Copying binary to SDK..."
  mkdir -p "$SDK_DIR/bin"
  create_app_bundle "$BINARY" "$SDK_DIR/bin"
  # Also keep standalone binary for backward compat
  cp "$BINARY" "$SDK_DIR/bin/darwinkit"
  chmod 755 "$SDK_DIR/bin/darwinkit"

  echo "Building TypeScript SDK..."
  cd "$SDK_DIR"
  bun install --frozen-lockfile 2>/dev/null || bun install
  bun run build

  echo "Build complete. Binary: $SDK_DIR/bin/darwinkit"
  echo "App bundle: $SDK_DIR/bin/DarwinKit.app"
  echo "To link into another project: cd $SDK_DIR && bun link"
  exit 0
fi

# ── GitHub release ──────────────────────────────────────
if [ "$BUILD_ONLY" = false ]; then
  echo "Creating tarball..."
  tar -czf "$SCRIPT_DIR/$TARBALL" -C "$SWIFT_DIR/.build/arm64-apple-macosx/release" darwinkit

  # Check if release already exists
  if gh release view "$VERSION" --repo "$GH_REPO" &>/dev/null; then
    read -p "Release $VERSION already exists. Delete and recreate? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      gh release delete "$VERSION" --repo "$GH_REPO" --yes
      git push origin --delete "$VERSION" 2>/dev/null || true
    else
      echo "Aborted."
      exit 1
    fi
  fi

  echo "Creating GitHub release $VERSION..."
  gh release create "$VERSION" "$SCRIPT_DIR/$TARBALL" \
    --repo "$GH_REPO" \
    --title "$VERSION" \
    --generate-notes

  rm "$SCRIPT_DIR/$TARBALL"
  echo "GitHub release $VERSION created."
fi

# ── npm publish (handled by GitHub Actions on release) ──
echo "Done. npm publish will be triggered automatically by GitHub Actions."
