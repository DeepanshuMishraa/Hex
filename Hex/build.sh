#!/bin/bash
# build.sh — Build, sign, and install Tick
#
# This script:
#   1. Builds the app (ad-hoc, since "Mac Development" cert isn't available)
#   2. Re-signs with the Apple Development identity (stable across builds)
#   3. Copies to ~/Applications
#
# Run with: ./build.sh

set -e

DD="$HOME/Library/Developer/Xcode/DerivedData/Hex-forrlwmvllucwyccbfrbnmdnwwxd/Build/Products/Debug"
SRC="$DD/tick Debug.app"
DEST="$HOME/Applications/tick Debug.app"
IDENTITY="Apple Development: teamindulus@gmail.com (TD57DQ83Z6)"

echo "Building..."
xcodebuild -project Hex.xcodeproj -scheme Hex -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  build 2>&1 | tail -1

echo "Re-signing with $IDENTITY..."
codesign --force --deep --sign "$IDENTITY" --options runtime "$SRC"

echo "Killing any running instances..."
killall "tick Debug" 2>/dev/null || true
sleep 0.5

echo "Installing to $DEST..."
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "Verifying signature..."
codesign -dvv "$DEST" 2>&1 | grep -E "Authority=|Identifier="

echo ""
echo "✓ Done. Launch with:"
echo "  open \"$DEST\""
