#!/usr/bin/env bash
# Bumps pubspec.yaml's version (patch +1, build number = today, see
# tool/bump_version.py) THEN builds the release web app, as two separate steps
# (Flutter reads pubspec.yaml's version before the build starts). Flutter
# writes the bumped version into build/web/version.json.
#
# Usage: scripts/build_web.sh <API_BASE_URL> [extra flutter build web flags]
# Example1: scripts/build_web.sh http://17.201.74.159
# Example2: scripts/build_web.sh https://waha1.duckdns.org
set -euo pipefail
cd "$(dirname "$0")/.."

api="${1:-}"
if [ $# -ge 1 ]; then
  shift
fi

python3 tool/bump_version.py

flutter build web --release --no-wasm-dry-run \
  --dart-define=BUILD_TIME="$(date '+%Y-%m-%d %H:%M %Z')" "$@"

# Automatically write config.json to the production build output
echo "{\"apiBaseUrl\": \"$api\"}" > build/web/config.json

echo "Build complete! API base URL set to: ${api:-'(relative path /api)'}"
