#!/bin/bash
# Regenerates the DMG (macOS) and the unsigned IPA (iOS) on the Desktop.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJ="MyTrackpad.xcodeproj"
DD="build"
DESKTOP="$HOME/Desktop"
DMG="$DESKTOP/MyTrackpad-Server.dmg"
IPA="$DESKTOP/MyTrackpad.ipa"

echo "▶︎ Generating project…"
xcodegen generate >/dev/null
echo "▶︎ Regenerating icons…"
swift tools/makeicons.swift >/dev/null

# ---------- macOS → DMG ----------
echo "▶︎ Building macOS app (Release)…"
xcodebuild -project "$PROJ" -scheme MyTrackpadMac -configuration Release \
  -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build \
  >/dev/null 2>&1 && echo "  ✓ build macOS"

MAC_APP="$DD/Build/Products/Release/MyTrackpadMac.app"
STAGE="$DD/dmg-stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$MAC_APP" "$STAGE/MyTrackpad Server.app"
codesign --force --deep --sign - "$STAGE/MyTrackpad Server.app" 2>/dev/null
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "MyTrackpad Server" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
xattr -dr com.apple.quarantine "$DMG" 2>/dev/null || true
echo "  ✓ $DMG"

# ---------- iOS → IPA (sin firmar) ----------
echo "▶︎ Building iOS app (Release, device, unsigned)…"
xcodebuild -project "$PROJ" -scheme MyTrackpad -sdk iphoneos -configuration Release \
  -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build \
  >/dev/null 2>&1 && echo "  ✓ build iOS"

IOS_APP="$DD/Build/Products/Release-iphoneos/MyTrackpad.app"
WORK="$DD/ipa-work"
rm -rf "$WORK"; mkdir -p "$WORK/Payload"
cp -R "$IOS_APP" "$WORK/Payload/"
rm -f "$IPA"
( cd "$WORK" && zip -qr "$IPA" Payload )
echo "  ✓ $IPA"

echo ""
echo "✅ Done:"
ls -lh "$DMG" "$IPA"
