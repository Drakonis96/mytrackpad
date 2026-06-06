#!/bin/bash
# Builds the distributable artifacts into ./dist:
#   - MyTrackpad-Server.dmg  (macOS app, drag-to-install)
#   - MyTrackpad-Server.zip  (macOS app, for the curl one-liner installer)
#   - MyTrackpad.ipa         (iOS app, unsigned → sideload / AltStore)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJ="MyTrackpad.xcodeproj"
DD="build"
OUT="$ROOT/dist"
DMG="$OUT/MyTrackpad-Server.dmg"
ZIP="$OUT/MyTrackpad-Server.zip"
IPA="$OUT/MyTrackpad.ipa"

mkdir -p "$OUT"

echo "▶︎ Generating project…"
xcodegen generate >/dev/null
echo "▶︎ Regenerating icons…"
swift tools/makeicons.swift >/dev/null

# ---------- macOS → DMG + ZIP ----------
echo "▶︎ Building macOS app (Release)…"
xcodebuild -project "$PROJ" -scheme MyTrackpadMac -configuration Release \
  -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build \
  >/dev/null 2>&1 && echo "  ✓ build macOS"

MAC_APP="$DD/Build/Products/Release/MyTrackpadMac.app"
STAGE="$DD/dist-stage"
APP="$STAGE/MyTrackpad Server.app"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$MAC_APP" "$APP"

# Clean ad-hoc signature (no Developer ID available). Valid, but not notarized,
# so macOS will quarantine it when downloaded via a browser — use the curl
# installer (see README) which avoids quarantine entirely.
codesign --force --deep --sign - "$APP"
codesign --verify --strict "$APP" && echo "  ✓ ad-hoc signature valid"

# ZIP (preserves the signature; used by the curl one-liner).
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
echo "  ✓ $ZIP"

# DMG (drag-to-Applications).
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "MyTrackpad Server" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
xattr -dr com.apple.quarantine "$DMG" 2>/dev/null || true
echo "  ✓ $DMG"

# ---------- iOS → IPA (unsigned) ----------
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
ls -lh "$DMG" "$ZIP" "$IPA"
