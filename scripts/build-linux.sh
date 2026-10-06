#!/usr/bin/env bash
# Build the IntelliPilot Linux desktop app and package it as .deb and .rpm.
#
# Builds for the machine it runs on (x86_64 or aarch64): Flutter does not
# cross-compile Linux desktop, so the release workflow runs this once per
# architecture.
#
# Usage:
#   ./scripts/build-linux.sh                  # release build + packages
#   ./scripts/build-linux.sh -- --dart-define=FOO=bar   # extra build args
#
# Output (in dist/):
#   intellipilot_<version>-<build>_<amd64|arm64>.deb
#   intellipilot-<version>-<build>.<x86_64|aarch64>.rpm
#
# Requires the Flutter Linux toolchain (clang, cmake, ninja, pkg-config,
# GTK 3 and libsecret development headers) and either nfpm on PATH or Go,
# which runs the pinned nfpm without installing it.
#
# Environment overrides:
#   FLUTTER_BIN   Explicit Flutter binary (skips fvm autodetection).
#   NFPM_BIN      Explicit nfpm binary.

set -euo pipefail

NFPM_VERSION="v2.47.0"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

EXTRA_ARGS=()
if [[ "${1:-}" == "--" ]]; then
  shift
  EXTRA_ARGS=("$@")
fi

flutter_cmd() {
  if [[ -n "${FLUTTER_BIN:-}" ]]; then
    "${FLUTTER_BIN}" "$@"
  elif command -v fvm >/dev/null 2>&1 && [[ -f .fvmrc ]]; then
    fvm flutter "$@"
  elif command -v flutter >/dev/null 2>&1; then
    flutter "$@"
  else
    echo "✗ Couldn't locate Flutter. Install fvm or add flutter to PATH." >&2
    exit 1
  fi
}

nfpm_cmd() {
  if [[ -n "${NFPM_BIN:-}" ]]; then
    "${NFPM_BIN}" "$@"
  elif command -v nfpm >/dev/null 2>&1; then
    nfpm "$@"
  elif command -v go >/dev/null 2>&1; then
    go run "github.com/goreleaser/nfpm/v2/cmd/nfpm@${NFPM_VERSION}" "$@"
  else
    echo "✗ Neither nfpm nor Go found. Install one of them." >&2
    exit 1
  fi
}

case "$(uname -m)" in
  x86_64) FLUTTER_ARCH=x64; export ARCH=amd64 ;;
  aarch64 | arm64) FLUTTER_ARCH=arm64; export ARCH=arm64 ;;
  *) echo "✗ Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

# pubspec `version: 0.7.8+90` → VERSION=0.7.8, RELEASE=90.
PUBSPEC_VERSION="$(sed -n 's/^version: *//p' pubspec.yaml)"
export VERSION="${PUBSPEC_VERSION%%+*}"
export RELEASE="${PUBSPEC_VERSION#*+}"
[[ "${RELEASE}" == "${PUBSPEC_VERSION}" ]] && RELEASE=1

echo "▶ IntelliPilot ${VERSION}+${RELEASE} for ${ARCH}"

flutter_cmd config --enable-linux-desktop >/dev/null
flutter_cmd pub get
flutter_cmd gen-l10n
flutter_cmd build linux --release \
  --dart-define=INTELLIPILOT_VERSION="${VERSION}" \
  --dart-define=INTELLIPILOT_BUILD="${RELEASE}" \
  --dart-define=INTELLIPILOT_FLAVOR=prod \
  ${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}

# Stage the bundle where nfpm.yaml expects it, whatever the architecture.
STAGE=build/linux-package
rm -rf "${STAGE}"
mkdir -p "${STAGE}"
cp -a "build/linux/${FLUTTER_ARCH}/release/bundle" "${STAGE}/bundle"
if [[ -e "${STAGE}/bundle/lib/libdartjni.so" ]]; then
  echo "✗ libdartjni.so is still in the bundle; it would make the package depend on Java." >&2
  exit 1
fi

mkdir -p dist
nfpm_cmd package --config linux/packaging/nfpm.yaml --packager deb --target dist/
nfpm_cmd package --config linux/packaging/nfpm.yaml --packager rpm --target dist/

echo "✓ Packages:"
ls -1 dist/*"${VERSION}"*.deb dist/*"${VERSION}"*.rpm
