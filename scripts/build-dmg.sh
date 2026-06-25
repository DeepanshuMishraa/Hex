#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting production release build of macOS App...${NC}"

# Navigate to the project root directory (one level up from scripts/)
cd "$(dirname "$0")/.."

# Clean up previous builds
echo -e "${BLUE}Cleaning previous build artifacts...${NC}"
rm -rf ./build
rm -f ./*.dmg

# Build the scheme in Release configuration with ad-hoc signing
echo -e "${BLUE}Compiling Xcode project in Release mode...${NC}"
xcodebuild -project Hex.xcodeproj \
           -scheme Hex \
           -configuration Release \
           -derivedDataPath ./build/DerivedData \
           CODE_SIGN_IDENTITY="-" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=YES

echo -e "${GREEN}Compilation finished successfully.${NC}"

# Find the built .app package (use maxdepth 1 to avoid sparkle framework updater)
echo -e "${BLUE}Locating built app package...${NC}"
APP_PATH=$(find ./build/DerivedData/Build/Products/Release -maxdepth 1 -name "*.app" | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo -e "${RED}Error: Could not locate built .app bundle!${NC}"
    exit 1
fi

APP_NAME=$(basename "$APP_PATH" .app)
echo -e "${GREEN}Found app: $APP_NAME.app at $APP_PATH${NC}"

# Set up staging area for DMG
echo -e "${BLUE}Preparing DMG staging area...${NC}"
STAGING_DIR="./build/dmg_root"
mkdir -p "$STAGING_DIR"

# Copy the app to the staging directory
# Note: Keep the original .app name (tick.app) as compiled by Xcode to ensure code signature integrity
cp -R "$APP_PATH" "$STAGING_DIR/"

# Create link to Applications folder
echo -e "${BLUE}Creating symlink to /Applications...${NC}"
ln -s /Applications "$STAGING_DIR/Applications"

# Create the DMG file (Name the volume and DMG file based on APP_NAME)
echo -e "${BLUE}Packaging into DMG...${NC}"
DMG_FILE="./${APP_NAME}.dmg"
hdiutil create -volname "$APP_NAME" \
               -srcfolder "$STAGING_DIR" \
               -ov \
               -format UDZO \
               "$DMG_FILE"

# Clean up staging directory
rm -rf "$STAGING_DIR"

echo -e "${GREEN}Successfully generated production DMG: $DMG_FILE${NC}"
echo -e "${GREEN}You can open this DMG and drag the app to your /Applications folder to run the production release build.${NC}"
