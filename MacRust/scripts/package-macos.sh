#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(dirname -- "$SCRIPT_DIR")
SUITE_DIR=$(dirname -- "$PROJECT_DIR")
BUILDS_DIR="$SUITE_DIR/Builds"
SOURCE_ICON="$SUITE_DIR/Shared/Brand/mac-rust-icon.png"
SPREADSHEET_PRACTICE="$SUITE_DIR/Samples/SPREADSHEET_PRACTICE.md"
PLIST_TEMPLATE="$PROJECT_DIR/packaging/Info.plist"
QUICK_START_SOURCE="$PROJECT_DIR/packaging/LedgerForge Quick Start.md"
ICNS_BUILDER="$PROJECT_DIR/scripts/make-icns.swift"
APP_BUNDLE="$BUILDS_DIR/LedgerForge.app"
ZIP_PATH="$BUILDS_DIR/LedgerForge-macOS.zip"
PRACTICE_DIR="$BUILDS_DIR/LedgerForge Practice Packs"
QUICK_START_DEST="$BUILDS_DIR/LedgerForge Quick Start.md"
RELEASE_BINARY="$PROJECT_DIR/target/release/accounting-question-studio"
PACKAGE_VERSION=$(awk -F '"' '/^version = "/ { print $2; exit }' "$PROJECT_DIR/Cargo.toml")
CLEAN_AFTER=0

if [ "${1-}" = "--clean" ]; then
    CLEAN_AFTER=1
elif [ "$#" -ne 0 ]; then
    echo "usage: $0 [--clean]" >&2
    exit 64
fi

for REQUIRED_FILE in "$SOURCE_ICON" "$SPREADSHEET_PRACTICE" "$PLIST_TEMPLATE" "$QUICK_START_SOURCE" "$ICNS_BUILDER"; do
    if [ ! -f "$REQUIRED_FILE" ]; then
        echo "required packaging input is missing: $REQUIRED_FILE" >&2
        exit 1
    fi
done

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ledgerforge-package.XXXXXX")
TEMP_APP="$WORK_DIR/LedgerForge.app"
ICONSET="$WORK_DIR/LedgerForge.iconset"
STAGE_ROOT="$WORK_DIR/LedgerForge-macOS"

cleanup() {
    rm -rf -- "$WORK_DIR"
}
trap cleanup EXIT HUP INT TERM

cd "$PROJECT_DIR"

cargo fmt --check
cargo test --locked --all-targets
cargo clippy --locked --all-targets -- -D warnings
MACOSX_DEPLOYMENT_TARGET=11.0 cargo build --release --locked

mkdir -p "$TEMP_APP/Contents/MacOS" "$TEMP_APP/Contents/Resources/Practice Packs" "$ICONSET"
ditto "$RELEASE_BINARY" "$TEMP_APP/Contents/MacOS/LedgerForge"
chmod 755 "$TEMP_APP/Contents/MacOS/LedgerForge"
ditto "$PLIST_TEMPLATE" "$TEMP_APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$PACKAGE_VERSION" "$TEMP_APP/Contents/Info.plist"
ditto "$QUICK_START_SOURCE" "$TEMP_APP/Contents/Resources/LedgerForge Quick Start.md"
ditto "$SPREADSHEET_PRACTICE" "$TEMP_APP/Contents/Resources/Practice Packs/SPREADSHEET_PRACTICE.md"
ditto "$SOURCE_ICON" "$TEMP_APP/Contents/Resources/LedgerForgeIcon-1024.png"

sips -z 16 16 "$SOURCE_ICON" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$SOURCE_ICON" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$SOURCE_ICON" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET/icon_512x512.png" >/dev/null
ditto "$SOURCE_ICON" "$ICONSET/icon_512x512@2x.png"
mkdir -p "$WORK_DIR/swift-module-cache"
CLANG_MODULE_CACHE_PATH="$WORK_DIR/swift-module-cache" \
SWIFT_MODULECACHE_PATH="$WORK_DIR/swift-module-cache" \
swift "$ICNS_BUILDER" "$ICONSET" "$TEMP_APP/Contents/Resources/LedgerForge.icns"

plutil -lint "$TEMP_APP/Contents/Info.plist"
test "$(plutil -extract CFBundleIdentifier raw "$TEMP_APP/Contents/Info.plist")" = "com.lyspresso.ledgerforge"
test "$(plutil -extract CFBundleExecutable raw "$TEMP_APP/Contents/Info.plist")" = "LedgerForge"
test "$(plutil -extract LSMinimumSystemVersion raw "$TEMP_APP/Contents/Info.plist")" = "11.0"
test "$(lipo -archs "$TEMP_APP/Contents/MacOS/LedgerForge")" = "arm64"
vtool -show-build "$TEMP_APP/Contents/MacOS/LedgerForge" | grep -q 'minos 11.0'
iconutil -c iconset "$TEMP_APP/Contents/Resources/LedgerForge.icns" -o "$WORK_DIR/Verified.iconset"

codesign --force --sign - --timestamp=none "$TEMP_APP"
codesign --verify --deep --strict --verbose=2 "$TEMP_APP"

mkdir -p "$BUILDS_DIR"
rm -rf -- "$APP_BUNDLE"
ditto "$TEMP_APP" "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

rm -rf -- "$PRACTICE_DIR"
mkdir -p "$PRACTICE_DIR"
ditto "$SPREADSHEET_PRACTICE" "$PRACTICE_DIR/SPREADSHEET_PRACTICE.md"
ditto "$QUICK_START_SOURCE" "$QUICK_START_DEST"

mkdir -p "$STAGE_ROOT/LedgerForge Practice Packs"
ditto "$APP_BUNDLE" "$STAGE_ROOT/LedgerForge.app"
ditto "$QUICK_START_DEST" "$STAGE_ROOT/LedgerForge Quick Start.md"
ditto "$PRACTICE_DIR/SPREADSHEET_PRACTICE.md" "$STAGE_ROOT/LedgerForge Practice Packs/SPREADSHEET_PRACTICE.md"

rm -f -- "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$STAGE_ROOT" "$ZIP_PATH"
unzip -tq "$ZIP_PATH"

if [ "$CLEAN_AFTER" -eq 1 ]; then
    cargo clean
fi

echo "Created $APP_BUNDLE"
echo "Created $ZIP_PATH"
