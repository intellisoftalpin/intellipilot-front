#!/usr/bin/env bash
# Universal "run the IntelliPilot web app" launcher.
#
# Works on:
#   - macOS  (bash 3.2+ stock)
#   - Linux  (bash 4+)
#   - Windows under Git Bash, WSL, or MSYS2
#
# Usage:
#   ./scripts/run-web.sh                       # debug, hot-reload, port 8080
#   ./scripts/run-web.sh --port 5173           # pick another port
#   ./scripts/run-web.sh --host 0.0.0.0        # expose on the LAN
#   ./scripts/run-web.sh --mode release        # `flutter run` in release
#   ./scripts/run-web.sh --build               # build then serve build/web
#   ./scripts/run-web.sh --build --port 5000
#   ./scripts/run-web.sh -- --dart-define=FOO=bar  # extra args after `--`
#
# Run the offline demo (no backend, seeded in-memory data):
#   ./scripts/run-web.sh -- --dart-define=INTELLIPILOT_DEMO=true
#
# Environment overrides:
#   FLUTTER_BIN         Explicit Flutter binary (skips fvm autodetection).
#   INTELLIPILOT_PORT   Default port if --port isn't supplied.
#   INTELLIPILOT_HOST   Default host (default 127.0.0.1).

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

PORT="${INTELLIPILOT_PORT:-8080}"
HOST="${INTELLIPILOT_HOST:-127.0.0.1}"
MODE="debug"              # debug | profile | release
DEVICE="chrome"           # the only useful web device target on flutter run
DO_BUILD=0
EXTRA_ARGS=()

# ---------------------------------------------------------------------------
# Locate the project root (this script lives in <repo>/scripts/)
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

if [[ ! -f "pubspec.yaml" ]]; then
  echo "✗ pubspec.yaml not found at ${REPO_ROOT}; aborting." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# OS / shell detection — purely informational, lets us hint about quirks
# ---------------------------------------------------------------------------

case "$(uname -s 2>/dev/null || echo unknown)" in
  Darwin)             OS_LABEL="macOS" ;;
  Linux)              OS_LABEL="Linux" ;;
  MINGW*|MSYS*|CYGWIN*) OS_LABEL="Windows (Git Bash / MSYS / Cygwin)" ;;
  *)                  OS_LABEL="Unknown ($(uname -s 2>/dev/null || echo n/a))" ;;
esac

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port|-p)        PORT="${2:?--port needs a value}"; shift 2 ;;
    --port=*)         PORT="${1#*=}"; shift ;;
    --host|-h)        HOST="${2:?--host needs a value}"; shift 2 ;;
    --host=*)         HOST="${1#*=}"; shift ;;
    --mode|-m)        MODE="${2:?--mode needs a value}"; shift 2 ;;
    --mode=*)         MODE="${1#*=}"; shift ;;
    --build|-b)       DO_BUILD=1; shift ;;
    --help)           usage; exit 0 ;;
    --)               shift; EXTRA_ARGS+=("$@"); break ;;
    *)                EXTRA_ARGS+=("$1"); shift ;;
  esac
done

case "${MODE}" in
  debug|profile|release) ;;
  *)
    echo "✗ Unknown --mode '${MODE}'. Use debug | profile | release." >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# Resolve a Flutter binary. Preference order:
#   1) $FLUTTER_BIN if explicitly set
#   2) `fvm flutter` (matches this repo's .fvmrc pin)
#   3) `flutter` on PATH
# ---------------------------------------------------------------------------

flutter_cmd() {
  if [[ -n "${FLUTTER_BIN:-}" ]]; then
    "${FLUTTER_BIN}" "$@"
    return
  fi
  if command -v fvm >/dev/null 2>&1 && [[ -f "${REPO_ROOT}/.fvmrc" ]]; then
    fvm flutter "$@"
    return
  fi
  if command -v flutter >/dev/null 2>&1; then
    flutter "$@"
    return
  fi
  echo "✗ Couldn't locate Flutter. Install fvm (recommended) or add flutter to PATH." >&2
  echo "  See README / .fvmrc for the pinned version." >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Action
# ---------------------------------------------------------------------------

echo "→ IntelliPilot web launcher"
echo "  OS:    ${OS_LABEL}"
echo "  Mode:  ${MODE}"
echo "  Host:  ${HOST}"
echo "  Port:  ${PORT}"
echo "  Repo:  ${REPO_ROOT}"
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
  echo "  Extra: ${EXTRA_ARGS[*]}"
fi
echo

if [[ "${DO_BUILD}" -eq 1 ]]; then
  echo "→ Building release web bundle…"
  flutter_cmd build web --release "${EXTRA_ARGS[@]}"
  echo
  echo "→ Serving build/web on http://${HOST}:${PORT}"
  echo "  (Stop with Ctrl+C.)"
  # Try Python (ships on macOS + most Linux + Git Bash via the system Python).
  # Fall back to `dart` if Python isn't on PATH — `dart pub global activate dhttpd`
  # is the documented official option but we don't want to install anything here.
  if command -v python3 >/dev/null 2>&1; then
    cd build/web && exec python3 -m http.server "${PORT}" --bind "${HOST}"
  elif command -v python >/dev/null 2>&1; then
    cd build/web && exec python -m http.server "${PORT}" --bind "${HOST}"
  else
    echo "✗ No Python on PATH. Either install Python 3 or run:" >&2
    echo "    dart pub global activate dhttpd && dart pub global run dhttpd --port ${PORT} --path build/web" >&2
    exit 1
  fi
else
  echo "→ Starting flutter run (hot-reload, ${MODE})…"
  exec_args=(run -d "${DEVICE}" --web-port="${PORT}" --web-hostname="${HOST}")
  case "${MODE}" in
    profile) exec_args+=(--profile) ;;
    release) exec_args+=(--release) ;;
  esac
  exec_args+=("${EXTRA_ARGS[@]}")
  flutter_cmd "${exec_args[@]}"
fi
