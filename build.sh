#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
SWIFTC="${AM_SWIFTC:-/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc}"
SDK="${AM_SDK:-/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk}"
if [[ ! -f Resources/am-infinity.png || ! -f Resources/am-infinity-black.png ]]; then
    echo 'Missing mouse artwork. Run bash scripts/fetch-artwork.sh; see THIRD_PARTY_NOTICES.md.' >&2
    exit 1
fi
mkdir -p build/cache "build/AM Native.app/Contents/MacOS"
FLAGS=(-swift-version 5 -target arm64-apple-macosx14.0 -sdk "$SDK" -module-cache-path "$PWD/build/cache")
"$SWIFTC" "${FLAGS[@]}" Sources/MouseCore.swift Sources/BluetoothTransport.swift Tests/CoreTests.swift -o build/core-tests
build/core-tests
"$SWIFTC" "${FLAGS[@]}" Sources/MouseCore.swift Sources/BluetoothTransport.swift Sources/Lighting.swift Sources/MouseService.swift Sources/KeyMapping.swift Sources/OfficialUpdates.swift Tests/FeatureTests.swift -o build/feature-tests
"$SWIFTC" "${FLAGS[@]}" Sources/MouseCore.swift Sources/BluetoothTransport.swift Sources/MouseService.swift Sources/KeyMapping.swift Sources/Lighting.swift Tests/LightingTests.swift -o build/lighting-tests
build/lighting-tests
build/feature-tests
"$SWIFTC" "${FLAGS[@]}" Sources/MacNavigationButton.swift Tests/NavigationTests.swift -o build/navigation-tests
build/navigation-tests
"$SWIFTC" "${FLAGS[@]}" Sources/MouseCore.swift Sources/BluetoothTransport.swift Sources/Probe.swift -o build/am-probe
"$SWIFTC" "${FLAGS[@]}" Sources/MouseCore.swift Sources/BluetoothTransport.swift Sources/Lighting.swift Sources/MouseService.swift Sources/KeyMapping.swift Sources/OfficialUpdates.swift Sources/LightingPanel.swift Sources/UpdatePanel.swift Sources/MappingPanel.swift Sources/InteractiveMouse.swift Sources/MacNavigationButton.swift Sources/NativeStyle.swift Sources/DeviceWorkspace.swift Sources/PointerView.swift Sources/AMNativeApp.swift -o "build/AM Native.app/Contents/MacOS/AMNative"
mkdir -p "build/AM Native.app/Contents/Resources"
cp Resources/am-infinity.png Resources/am-infinity-black.png "build/AM Native.app/Contents/Resources/"
# Use the release artwork when present; a fresh source clone has a generated fallback.
ICON_SOURCE="Resources/AppIcon-v1.png"
if [[ ! -f "$ICON_SOURCE" ]]; then
    "$SWIFTC" "${FLAGS[@]}" scripts/MakeFallbackIcon.swift -o build/make-fallback-icon
    build/make-fallback-icon build/AppIcon-fallback.png
    ICON_SOURCE="build/AppIcon-fallback.png"
fi
mkdir -p build/AppIcon.iconset
for point_size in 16 32 128 256 512; do
    /usr/bin/sips -z "$point_size" "$point_size" "$ICON_SOURCE" --out "build/AppIcon.iconset/icon_${point_size}x${point_size}.png" >/dev/null
    pixel_size=$((point_size * 2))
    /usr/bin/sips -z "$pixel_size" "$pixel_size" "$ICON_SOURCE" --out "build/AppIcon.iconset/icon_${point_size}x${point_size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns build/AppIcon.iconset -o "build/AM Native.app/Contents/Resources/AppIcon.icns"
cp Info.plist "build/AM Native.app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "build/AM Native.app"
printf 'Built: %s/build/AM Native.app\n' "$PWD"
