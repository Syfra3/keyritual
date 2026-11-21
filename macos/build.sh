#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then echo 'Build requires macOS' >&2; exit 1; fi
cargo build --release --bin keyritual-core
arch="$(uname -m)"
engine="target/release/keyritual-core"
if [[ "$arch" != arm64 && "$arch" != x86_64 ]]; then echo "Unsupported host architecture: $arch" >&2; exit 1; fi
file "$engine" | grep -q "$arch" || { echo 'Rust engine architecture does not match host' >&2; exit 1; }
app="macos/build/Keyritual.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -parse-as-library -O -framework SwiftUI -framework AppKit macos/KeyritualMac/main.swift -o "$app/Contents/MacOS/Keyritual"
cp "$engine" "$app/Contents/Resources/keyritual-core"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.syfra3.keyritual.mac</string>
<key>CFBundleName</key><string>Keyritual</string>
<key>CFBundleExecutable</key><string>Keyritual</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
printf 'Built %s (unsigned, local development only)\n' "$app"
