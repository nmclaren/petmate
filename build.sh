#!/usr/bin/env bash
#
# Build script for Petmate.
#
# Usage:
#   ./build.sh          install deps, build, and package a macOS .dmg into dist/
#   ./build.sh dev      install deps and launch the app in development mode
#   ./build.sh deps     install deps (and repair the Electron binary) only
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
  $YARN install
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

case "${1:-build}" in
  deps)
    install_deps
    ;;
  dev)
    install_deps
    echo "==> Launching Petmate (dev mode, Ctrl-C to quit)"
    $YARN start
    ;;
  build)
    install_deps
    echo "==> Building production bundle"
    $YARN build
    echo "==> Packaging macOS app"
    # electron-builder notarizes when Apple credentials are in the environment,
    # but it expects the app-specific password as APPLE_APP_SPECIFIC_PASSWORD.
    if [ -z "${APPLE_APP_SPECIFIC_PASSWORD:-}" ] && [ -n "${APPSTORE_PASSWORD:-}" ]; then
      export APPLE_APP_SPECIFIC_PASSWORD="$APPSTORE_PASSWORD"
    fi
    $YARN dist-macos
    echo "==> Done. Installer is in dist/:"
    ls -lh dist/*.dmg
    ;;
  *)
    echo "Usage: $0 [build|dev|deps]" >&2
    exit 1
    ;;
esac
