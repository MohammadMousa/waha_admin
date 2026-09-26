#!/usr/bin/env bash
# Bumps pubspec.yaml's version (patch +1, build number = today, see
# tool/bump_version.py) THEN builds the release web app, as two separate steps
# (Flutter reads pubspec.yaml's version before the build starts). Flutter
# writes the bumped version into build/web/version.json.
#
# Usage: scripts/build_web.sh <API_BASE_URL> [extra flutter build web flags]
# Example: scripts/build_web.sh http://18.211.74.179
set -euo pipefail
cd "$(dirname "$0")/.."

if [ $# -lt 1 ] || [[ "$1" == -* ]]; then
  echo "Usage: $0 <API_BASE_URL> [extra flutter build web flags]" >&2
  exit 1
fi
api="$1"
shift

python3 tool/bump_version.py
flutter build web --release --no-wasm-dry-run \
  --dart-define=API_BASE_URL="$api" \
  --dart-define=BUILD_TIME="$(date '+%Y-%m-%d %H:%M %Z')" "$@"
