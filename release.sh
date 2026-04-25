#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_ONLY=false
NO_PUSH=false
VERSION=""

# Parse flags
for arg in "$@"; do
  case "$arg" in
    --build-only)  BUILD_ONLY=true ;;
    --no-push)     NO_PUSH=true ;;
    --*)           echo "Unknown flag: $arg"; exit 1 ;;
    *)             VERSION="$arg" ;;
  esac
done

if [ "$BUILD_ONLY" = false ] && [ -z "$VERSION" ]; then
  cat <<EOF
Usage: ./release.sh <version> [--no-push]
       ./release.sh --build-only

  --build-only  Build Swift binary + TS SDK locally (no commit, tag, or release)
  --no-push     Bump package.json, commit, build, and tag locally — but
                don't push or create the GitHub release. Use this to stage a
                release for review before pushing.

npm publish is automatic via GitHub Actions when a release is created.
EOF
  exit 1
fi

# Normalize version: accept "0.7.0" or "v0.7.0", store as "0.7.0", tag as "v0.7.0"
if [ -n "$VERSION" ]; then
  VERSION="${VERSION#v}"
  TAG="v$VERSION"
fi

SWIFT_DIR="$SCRIPT_DIR/packages/darwinkit-swift"
SDK_DIR="$SCRIPT_DIR/packages/darwinkit"
PKG_JSON="$SDK_DIR/package.json"
TARBALL="darwinkit-macos-arm64.tar.gz"
GH_REPO="genesiscz/darwinkit-swift"

cd "$SCRIPT_DIR"

# ── Pre-flight (release modes only) ────────────────────
SKIP_BUMP_AND_TAG=false
if [ "$BUILD_ONLY" = false ]; then
  CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  if [ "$CURRENT_BRANCH" != "main" ]; then
    read -p "Not on main (currently '$CURRENT_BRANCH'). Continue? [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
  fi

  # Working tree must be clean (excluding package.json — release.sh manages it).
  # Pathspec is repo-relative; absolute paths don't work with :! exclusions.
  PKG_JSON_REL="packages/darwinkit/package.json"
  if ! git diff --quiet HEAD -- ":!$PKG_JSON_REL"; then
    echo "Working tree has uncommitted changes (excluding package.json):"
    git status --short -- ":!$PKG_JSON_REL"
    echo
    echo "Commit or stash these before releasing."
    exit 1
  fi

  # Resume support: if the tag already exists at HEAD with matching version, skip bump+tag
  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    TAG_SHA="$(git rev-parse "$TAG^{commit}")"
    HEAD_SHA="$(git rev-parse HEAD)"
    TAG_PKG_VERSION="$(git show "$TAG:packages/darwinkit/package.json" | jq -r .version)"
    if [ "$TAG_SHA" = "$HEAD_SHA" ] && [ "$TAG_PKG_VERSION" = "$VERSION" ]; then
      echo "Tag $TAG already exists at HEAD with package.json $VERSION — resuming."
      SKIP_BUMP_AND_TAG=true
    else
      echo "Tag $TAG already exists but doesn't match HEAD/version."
      echo "  tag SHA:        $TAG_SHA"
      echo "  HEAD SHA:       $HEAD_SHA"
      echo "  tag pkg ver:    $TAG_PKG_VERSION"
      echo "  requested ver:  $VERSION"
      read -p "Delete and recreate? [y/N] " -n 1 -r
      echo
      if [[ $REPLY =~ ^[Yy]$ ]]; then
        git tag -d "$TAG"
      else
        echo "Aborted."
        exit 1
      fi
    fi
  fi

  # Bump package.json + commit (idempotent)
  if [ "$SKIP_BUMP_AND_TAG" = false ]; then
    CURRENT_VERSION="$(jq -r .version "$PKG_JSON")"
    if [ "$CURRENT_VERSION" != "$VERSION" ]; then
      echo "Bumping package.json: $CURRENT_VERSION → $VERSION"
      jq --arg v "$VERSION" '.version = $v' "$PKG_JSON" > "$PKG_JSON.tmp" && mv "$PKG_JSON.tmp" "$PKG_JSON"
    fi
    if ! git diff --quiet -- "$PKG_JSON"; then
      git add "$PKG_JSON"
      git commit -m "chore: bump version to $VERSION"
    else
      echo "package.json already at $VERSION (and committed)."
    fi
  fi
fi

# ── Build binary (arm64 only) ──────────────────────────
echo "Building arm64 binary..."
cd "$SWIFT_DIR"
swift build -c release --arch arm64
cd "$SCRIPT_DIR"

BINARY="$SWIFT_DIR/.build/arm64-apple-macosx/release/darwinkit"

if [ ! -f "$BINARY" ]; then
  echo "Error: Binary not found at $BINARY"
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
  cp "$BINARY" "$SDK_DIR/bin/darwinkit"
  chmod 755 "$SDK_DIR/bin/darwinkit"

  echo "Building TypeScript SDK..."
  cd "$SDK_DIR"
  bun install --frozen-lockfile 2>/dev/null || bun install
  bun run build

  echo "Build complete."
  echo "  Binary: $SDK_DIR/bin/darwinkit"
  echo "  App bundle: $SDK_DIR/bin/DarwinKit.app"
  echo "To link into another project: cd $SDK_DIR && bun link"
  exit 0
fi

# ── Tag locally ─────────────────────────────────────────
cd "$SCRIPT_DIR"
if [ "$SKIP_BUMP_AND_TAG" = false ]; then
  echo "Tagging $TAG..."
  git tag "$TAG"
fi

# ── No-push mode: stop here ─────────────────────────────
if [ "$NO_PUSH" = true ]; then
  cat <<EOF

Built and tagged $TAG locally. Nothing pushed.

To complete the release later:
  ./release.sh $VERSION              # pushes commit + tag, creates GH release

To undo:
  git tag -d $TAG
  git reset --hard HEAD~1            # only if the bump commit was just made

EOF
  exit 0
fi

# ── Push commit + tag ───────────────────────────────────
echo "Pushing commit and tag to origin..."
git push origin "$CURRENT_BRANCH"
git push origin "$TAG"

# ── GitHub release ──────────────────────────────────────
echo "Creating tarball..."
tar -czf "$SCRIPT_DIR/$TARBALL" -C "$SWIFT_DIR/.build/arm64-apple-macosx/release" darwinkit

# Check if release already exists
if gh release view "$TAG" --repo "$GH_REPO" &>/dev/null; then
  read -p "Release $TAG already exists. Delete and recreate? [y/N] " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    gh release delete "$TAG" --repo "$GH_REPO" --yes
  else
    echo "Aborted."
    rm -f "$SCRIPT_DIR/$TARBALL"
    exit 1
  fi
fi

echo "Creating GitHub release $TAG..."
gh release create "$TAG" "$SCRIPT_DIR/$TARBALL" \
  --repo "$GH_REPO" \
  --title "$TAG" \
  --generate-notes

rm "$SCRIPT_DIR/$TARBALL"
echo "GitHub release $TAG created. npm publish will be triggered by GitHub Actions."
