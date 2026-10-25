#!/bin/zsh
# Builds Photo21.app without xcodebuild (works even before the Xcode license is accepted).
# Usage: Scripts/build.sh [output-dir]   (default: build/manual)
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/manual}"
APP="$OUT/Photo21.app"
PLUGINS=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins
VERSION=$(sed -nE 's/.*MARKETING_VERSION = ([0-9.]+);.*/\1/p' Photo21.xcodeproj/project.pbxproj | head -1)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling…"
swiftc -O -parse-as-library -swift-version 6 -strict-concurrency=complete \
  -target arm64-apple-macosx15.0 -plugin-path "$PLUGINS" -module-name Photo21 \
  $(find Photo21 -name '*.swift') -o "$APP/Contents/MacOS/Photo21"

# Info.plist: the document types from Photo21/Info.plist plus the keys Xcode would generate.
cp Photo21/Info.plist "$APP/Contents/Info.plist"
P=/usr/libexec/PlistBuddy
$P -c "Add :CFBundleExecutable string Photo21" "$APP/Contents/Info.plist"
$P -c "Add :CFBundleIdentifier string com.21loopings.Photo21" "$APP/Contents/Info.plist"
$P -c "Add :CFBundleName string Photo21" "$APP/Contents/Info.plist"
$P -c "Add :CFBundleDisplayName string Photo21" "$APP/Contents/Info.plist"
$P -c "Add :CFBundlePackageType string APPL" "$APP/Contents/Info.plist"
$P -c "Add :CFBundleShortVersionString string ${VERSION:-1.0}" "$APP/Contents/Info.plist"
$P -c "Add :CFBundleVersion string 1" "$APP/Contents/Info.plist"
$P -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$APP/Contents/Info.plist"
$P -c "Add :LSMinimumSystemVersion string 15.0" "$APP/Contents/Info.plist"
$P -c "Add :LSApplicationCategoryType string public.app-category.photography" "$APP/Contents/Info.plist"
$P -c "Add :NSHighResolutionCapable bool true" "$APP/Contents/Info.plist"

# Icon: build an .icns from the asset catalog PNGs with iconutil (ships with macOS).
ICONSET="$OUT/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for f in Photo21/Assets.xcassets/AppIcon.appiconset/icon_*.png; do cp "$f" "$ICONSET/"; done
if ls "$ICONSET"/*.png >/dev/null 2>&1; then
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  $P -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi
rm -rf "$ICONSET"

echo "APPL????" > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP"
echo "Built $APP"
