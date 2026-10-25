#!/bin/zsh
# Runs the test suite through SwiftPM (no xcodebuild needed). Sources are linked into a scratch package.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="${TMPDIR:-/tmp}/photo21-spm"
mkdir -p "$PKG/Sources" "$PKG/Tests"
ln -sfn "$ROOT/Photo21" "$PKG/Sources/Photo21"
ln -sfn "$ROOT/Photo21Tests" "$PKG/Tests/Photo21Tests"
cat > "$PKG/Package.swift" <<'PKG'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Photo21",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "Photo21", path: "Sources/Photo21", exclude: ["Photo21App.swift", "Info.plist", "Assets.xcassets"]),
        .testTarget(name: "Photo21Tests", dependencies: ["Photo21"], path: "Tests/Photo21Tests"),
    ]
)
PKG
XCODE_PLUGINS=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins
TESTING_PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
cd "$PKG" && swift test -Xswiftc -plugin-path -Xswiftc "$XCODE_PLUGINS" -Xswiftc -plugin-path -Xswiftc "$TESTING_PLUGINS" "$@"
