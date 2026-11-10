#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
if pgrep -x ClickPlus >/dev/null; then osascript -e 'tell application id "br.com.ratoesperto.app" to quit' || true; fi
xcodebuild -project ClickPlus.xcodeproj -scheme ClickPlus -configuration Debug -derivedDataPath build build > /tmp/clickplus-build.log 2>&1 || { tail -80 /tmp/clickplus-build.log; exit 1; }
APP="$ROOT_DIR/build/Build/Products/Debug/Click +.app"
# Prefer this exact bundle when macOS resolves its identifier for TCC prompts.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
case "$MODE" in
  --build) echo "$APP" ;;
  --debug) lldb "$APP/Contents/MacOS/ClickPlus" ;;
  --logs|--telemetry) open "$APP"; /usr/bin/log stream --level info --predicate 'process == "ClickPlus"' ;;
  --verify) open "$APP"; sleep 2; pgrep -x ClickPlus ;;
  run) open "$APP" ;;
  *) echo 'Use: run | --build | --debug | --logs | --telemetry | --verify'; exit 2 ;;
esac
