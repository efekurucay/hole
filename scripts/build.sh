#!/bin/bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

mode=${1:-native}
case "$mode" in
    native) architectures=("$(uname -m)") ;;
    release) architectures=(arm64 x86_64) ;;
    *) echo "Usage: $0 [native|release]" >&2; exit 2 ;;
esac

build_dir="$(pwd)/build"
app="$build_dir/Hole.app"
iconset="$build_dir/Hole.iconset"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$iconset"

for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" branding/hole.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    /usr/bin/sips -z "$double" "$double" branding/hole.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns -o "$app/Contents/Resources/Hole.icns" "$iconset"
cp scripts/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE"

binaries=()
for arch in "${architectures[@]}"; do
    binary="$build_dir/Hole-$arch"
    xcrun swiftc -swift-version 5 -O -parse-as-library -target "$arch-apple-macosx14.0" \
        Sources/Hole/*.swift -o "$binary"
    binaries+=("$binary")
done
xcrun lipo -create "${binaries[@]}" -output "$app/Contents/MacOS/Hole"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --deep --strict "$app"

if [[ "$mode" == release ]]; then
    staging="$build_dir/dmg"
    mkdir -p "$staging"
    /usr/bin/ditto "$app" "$staging/Hole.app"
    if [[ ! -L "$staging/Applications" ]]; then ln -s /Applications "$staging/Applications"; fi
    /usr/bin/hdiutil create -quiet -ov -format UDZO -volname "Hole" -srcfolder "$staging" "$build_dir/Hole.dmg"
fi
echo "$app"
