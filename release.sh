#!/bin/bash
set -euo pipefail

VERSION="${1:?Usage: ./release.sh <version>}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/packages/darwinkit-swift"

echo "Building universal binary..."
swift build -c release --arch arm64 --arch x86_64

TARBALL="darwinkit-macos-universal.tar.gz"
tar -czf "$SCRIPT_DIR/$TARBALL" -C .build/apple/Products/Release darwinkit

cd "$SCRIPT_DIR"

echo "Creating GitHub release $VERSION..."
if ! gh release create "$VERSION" "$TARBALL" \
  --title "$VERSION" \
  --generate-notes 2>/dev/null; then
  echo "gh release create failed, falling back to API..."
  gh api repos/{owner}/{repo}/releases \
    -f tag_name="$VERSION" \
    -f name="$VERSION" \
    -F generate_release_notes=true > /dev/null
  gh release upload "$VERSION" "$TARBALL"
fi

rm "$TARBALL"
echo "Released $VERSION"
