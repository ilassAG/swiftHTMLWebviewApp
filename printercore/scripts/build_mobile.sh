#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CORE_DIR="$ROOT_DIR/printercore"

export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$(go env GOPATH)/bin:$PATH"

if ! command -v gomobile >/dev/null 2>&1; then
  echo "gomobile is not installed. Run:" >&2
  echo "  go install golang.org/x/mobile/cmd/gomobile@latest" >&2
  echo "  go install golang.org/x/mobile/cmd/gobind@latest" >&2
  echo "  go get -tool golang.org/x/mobile/cmd/gobind" >&2
  echo "  gomobile init" >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/android/app/libs"
mkdir -p "$ROOT_DIR/ios/Frameworks"

(
  cd "$CORE_DIR"
  go test ./...
  gomobile bind -target=android -androidapi 23 -javapkg com.ilass -o "$ROOT_DIR/android/app/libs/printercore.aar" .
  gomobile bind -target=ios,iossimulator -prefix PM -o "$ROOT_DIR/ios/Frameworks/Printercore.xcframework" .
)
