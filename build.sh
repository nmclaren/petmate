#!/usr/bin/env bash
#
# Build script for Petmate.
#
# Usage:
#   ./build.sh X.Y.Z          install deps, build, and package a macOS .dmg into dist/
#   ./build.sh build X.Y.Z    same as above
#   ./build.sh dev            install deps and launch the app in development mode
#   ./build.sh deps           install deps (and repair the Electron binary) only
#
# X.Y.Z (required for packaged builds) sets the app version.  The build
# number shown in parentheses in the About window is the git commit count.
#
# Requires Node (any modern version; the legacy-OpenSSL flag needed by the
# old webpack 4 toolchain is already baked into the package.json scripts).
set -euo pipefail
cd "$(dirname "$0")"

# Use plain yarn if installed, otherwise go through corepack (ships with Node).
if command -v yarn >/dev/null 2>&1; then
  YARN=yarn
else
  YARN="corepack yarn"
fi

install_deps() {
  echo "==> Installing dependencies"
  # fsevents is optional and fails to compile on Node 17+; that's fine.
  # Skip Electron's own binary postinstall: it flakes on modern Node (e.g.
  # EEXIST re-extracting its framework symlink), which would abort under
  # 'set -e'.  repair_electron fetches the real binary right after.
  ELECTRON_SKIP_BINARY_DOWNLOAD=1 $YARN install
  repair_electron
}

# Electron 12's postinstall extraction breaks silently on modern Node,
# leaving a stub instead of the real app bundle. Re-download and extract
# it manually when that happens.
repair_electron() {
  local edir=node_modules/electron
  if [ -f "$edir/path.txt" ] && [ -e "$edir/dist/Electron.app/Contents/MacOS/Electron" ] && [ -f "$edir/dist/version" ]; then
    return
  fi
  echo "==> Repairing Electron binary install"
  local zip
  zip=$(cd "$edir" && node -e "
    const { downloadArtifact } = require('@electron/get');
    const { version } = require('./package.json');
    downloadArtifact({ version, artifactName: 'electron', platform: process.platform, arch: process.arch })
      .then(p => console.log(p))
      .catch(e => { console.error(e.message); process.exit(1); });
  ")
  rm -rf "$edir/dist"
  mkdir "$edir/dist"
  ditto -x -k "$zip" "$edir/dist"
  printf 'Electron.app/Contents/MacOS/Electron' > "$edir/path.txt"
  echo "==> Electron $(cat "$edir/dist/version") installed"
}

# A bare version number as the first argument means a packaged build.
MODE="${1:-build}"
VERSION="${2:-}"
if [[ "$MODE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  VERSION="$MODE"
  MODE=build
fi

case "$MODE" in
  deps)
    install_deps
    ;;
  dev)
    install_deps
    echo "==> Launching Petmate (dev mode, Ctrl-C to quit)"
    $YARN start
    ;;
  build)
    if [ -z "$VERSION" ]; then
      echo "A version number is required for packaged builds." >&2
      echo "Usage: $0 X.Y.Z   (e.g. $0 1.0.0)" >&2
      exit 1
    fi
    if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "Invalid version '$VERSION' (expected X.Y.Z)" >&2
      exit 1
    fi
    install_deps
    echo "==> Building production bundle"
    $YARN build
    echo "==> Packaging macOS app"
    # electron-builder notarizes when Apple credentials are in the environment,
    # but it expects the app-specific password as APPLE_APP_SPECIFIC_PASSWORD.
    if [ -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ] && [ -n "${APPSTORE_PASSWORD:-}" ]; then
      export APPLE_APP_SPECIFIC_PASSWORD="$APPSTORE_PASSWORD"
    fi
    if [ -z "${APPLE_TEAM_ID:-}" ]; then
      # Derive the team ID from the Developer ID Application cert in the keychain,
      # e.g. 'Developer ID Application: Nicholas McLaren (KGKP8W8M28)' -> KGKP8W8M28
      APPLE_TEAM_ID=$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*Developer ID Application: .*(\([A-Z0-9]\{10\}\))".*/\1/p' | head -1)
      if [ -n "$APPLE_TEAM_ID" ]; then
        export APPLE_TEAM_ID
      fi
    fi
    # Build number = git commit count; shown as "(N)" in the About window
    # (buildVersion also becomes CFBundleVersion in the .app).
    BUILD_NUMBER=$(git rev-list --count HEAD)
    EB_ARGS=(
      --c.buildVersion="$BUILD_NUMBER"
      --c.extraMetadata.buildNumber="$BUILD_NUMBER"
      --c.extraMetadata.version="$VERSION"
    )
    echo "==> Version: $VERSION build $BUILD_NUMBER"
    $YARN dist-macos "${EB_ARGS[@]}"
    echo "==> Done. Installer is in dist/:"
    ls -lh dist/*.dmg
    ;;
  *)
    echo "Usage: $0 [build|dev|deps] [X.Y.Z]" >&2
    exit 1
    ;;
esac
