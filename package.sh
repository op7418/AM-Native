#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="build/AM Native.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
NAME="AMNative-${VERSION}-arm64-preview"
ARCHIVE="$PWD/dist/${NAME}.zip"
[[ ! -e "$ARCHIVE" ]] || { echo "Archive already exists; preserve it and choose a new version." >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$APP"
mkdir -p dist
STAGING=$(mktemp -d "$PWD/build/distribution.XXXXXX")
mkdir "$STAGING/$NAME"
/usr/bin/ditto --norsrc --noextattr "$APP" "$STAGING/$NAME/AM Native.app"
cp docs/使用说明.txt "$STAGING/$NAME/使用说明.txt"
cp docs/Usage.en.txt "$STAGING/$NAME/Usage.en.txt"
cp LICENSE THIRD_PARTY_NOTICES.md "$STAGING/$NAME/"
printf 'AM Native %s\nArchitecture: arm64 (Apple Silicon only)\nSignature: ad-hoc; no Developer ID; not notarized\nMinimum declared macOS: 14.0; tested on macOS 27\n' "$VERSION" > "$STAGING/$NAME/版本与签名.txt"
/usr/bin/ditto -c -k --norsrc --noextattr --keepParent "$STAGING/$NAME" "$ARCHIVE"
(cd dist && /usr/bin/shasum -a 256 "${NAME}.zip" > "${NAME}.sha256")
printf 'Packaged: %s\n' "$ARCHIVE"
