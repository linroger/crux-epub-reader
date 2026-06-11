#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Crux init: ensuring Xcode project is generated."
if command -v xcodegen >/dev/null 2>&1; then
  (cd "$ROOT_DIR" && xcodegen generate)
else
  echo "xcodegen not installed. Install with: brew install xcodegen"
fi
