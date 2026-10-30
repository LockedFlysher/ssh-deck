#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP_NAME="SSH Deck.app"
APP_PATH="$ROOT/dist/$APP_NAME"
UNIVERSAL="${UNIVERSAL:-1}"

cd "$ROOT"

if [[ "$UNIVERSAL" == "1" ]]; then
    ARM_TRIPLE="arm64-apple-macosx14.0"
    INTEL_TRIPLE="x86_64-apple-macosx14.0"
    swift build -c "$CONFIG" --triple "$ARM_TRIPLE"
    ARM_BIN="$(swift build -c "$CONFIG" --triple "$ARM_TRIPLE" --show-bin-path)/SSHDeck"
    ARM_COPY="$ROOT/.build/SSHDeck-arm64"
    cp "$ARM_BIN" "$ARM_COPY"
    swift build -c "$CONFIG" --triple "$INTEL_TRIPLE"
    INTEL_BIN="$(swift build -c "$CONFIG" --triple "$INTEL_TRIPLE" --show-bin-path)/SSHDeck"
    ARM_BIN="$ARM_COPY"
else
    swift build -c "$CONFIG"
    ARM_BIN="$(swift build -c "$CONFIG" --show-bin-path)/SSHDeck"
    INTEL_BIN=""
fi

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

if [[ -n "$INTEL_BIN" ]]; then
    lipo -create "$ARM_BIN" "$INTEL_BIN" -output "$APP_PATH/Contents/MacOS/SSHDeck"
else
    cp "$ARM_BIN" "$APP_PATH/Contents/MacOS/SSHDeck"
fi
cp "$ROOT/Support/Info.plist" "$APP_PATH/Contents/Info.plist"

ICON_WORK="$ROOT/.build/sshdeck-icon"
ICONSET="$ICON_WORK/AppIcon.iconset"
MASTER="$ICON_WORK/AppIcon-1024.png"
rm -rf "$ICON_WORK"
mkdir -p "$ICONSET"

swift "$ROOT/scripts/make-icon.swift" "$MASTER"

for size in 16 32 64 128 256 512 1024; do
    if [[ "$size" == "16" ]]; then
        name="icon_16x16.png"
    elif [[ "$size" == "32" ]]; then
        name="icon_16x16@2x.png"
        sips -z 32 32 "$MASTER" --out "$ICONSET/icon_32x32.png" >/dev/null
    elif [[ "$size" == "64" ]]; then
        name="icon_32x32@2x.png"
    elif [[ "$size" == "128" ]]; then
        name="icon_128x128.png"
    elif [[ "$size" == "256" ]]; then
        name="icon_128x128@2x.png"
        sips -z 256 256 "$MASTER" --out "$ICONSET/icon_256x256.png" >/dev/null
    elif [[ "$size" == "512" ]]; then
        name="icon_256x256@2x.png"
        sips -z 512 512 "$MASTER" --out "$ICONSET/icon_512x512.png" >/dev/null
    else
        name="icon_512x512@2x.png"
    fi
    sips -z "$size" "$size" "$MASTER" --out "$ICONSET/$name" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_PATH"

ARTIFACT_DIR="$ROOT/artifacts"
ARTIFACT_PATH="$ARTIFACT_DIR/SSHDeck-macos-universal.zip"
mkdir -p "$ARTIFACT_DIR"
rm -f "$ARTIFACT_PATH" "$ARTIFACT_DIR/SHA256SUMS.txt"
ditto -c -k --norsrc --keepParent "$APP_PATH" "$ARTIFACT_PATH"
(cd "$ARTIFACT_DIR" && shasum -a 256 "$(basename "$ARTIFACT_PATH")" > SHA256SUMS.txt)

printf '%s\n' "$APP_PATH"
