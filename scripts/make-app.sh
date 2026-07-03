#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="V2rayN Sentinel"
EXECUTABLE="V2rayNSentinel"

echo "==> Building release binary..."
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/${EXECUTABLE}"

DEST="build/${APP_NAME}.app"
echo "==> Assembling ${DEST} ..."
rm -rf "${DEST}"
mkdir -p "${DEST}/Contents/MacOS" "${DEST}/Contents/Resources"
cp "${BIN_PATH}" "${DEST}/Contents/MacOS/${EXECUTABLE}"
cp Resources/Info.plist "${DEST}/Contents/Info.plist"

echo "==> Done: ${DEST}"
echo "    Run with: open \"${DEST}\""
