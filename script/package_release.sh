#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

xcodebuild -project ClickPlus.xcodeproj -scheme ClickPlus \
  -configuration Release -derivedDataPath build/release \
  'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build \
  > /tmp/clickplus-release-build.log 2>&1 || {
    tail -80 /tmp/clickplus-release-build.log
    exit 1
  }

APP="$ROOT_DIR/build/release/Build/Products/Release/Click +.app"
codesign --verify --deep --strict --verbose=2 "$APP"
RELEASE_ARCHS=$(lipo -archs "$APP/Contents/MacOS/ClickPlus")
for RELEASE_ARCH in arm64 x86_64; do
  case " $RELEASE_ARCHS " in
    *" $RELEASE_ARCH "*) ;;
    *) printf 'Arquitetura ausente: %s\n' "$RELEASE_ARCH" >&2; exit 1 ;;
  esac
done
RELEASE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
mkdir -p dist
RELEASE_ZIP="ClickPlus-${RELEASE_VERSION}-macOS-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/$RELEASE_ZIP"
(cd dist && shasum -a 256 "$RELEASE_ZIP" > SHA256SUMS.txt)
printf 'Pacote: %s/dist/%s\n' "$ROOT_DIR" "$RELEASE_ZIP"
