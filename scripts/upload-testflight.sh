#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# 設定（Step 1 で取得した値に置換）
AUTH_KEY_ID="${ASC_KEY_ID:?Set ASC_KEY_ID}"
AUTH_KEY_ISSUER="${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
AUTH_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${AUTH_KEY_ID}.p8"
BUILD_NUMBER="${1:-$(date +%Y%m%d%H%M)}"

cd "$(dirname "$0")/.."

echo "== XcodeGen =="
xcodegen generate

echo "== Archive (build: $BUILD_NUMBER) =="
xcodebuild archive \
  -project CareNote.xcodeproj \
  -scheme CareNote \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath build/CareNote.xcarchive \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$AUTH_KEY_PATH" \
  -authenticationKeyID "$AUTH_KEY_ID" \
  -authenticationKeyIssuerID "$AUTH_KEY_ISSUER" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

echo "== Export + Upload =="
xcodebuild -exportArchive \
  -archivePath build/CareNote.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$AUTH_KEY_PATH" \
  -authenticationKeyID "$AUTH_KEY_ID" \
  -authenticationKeyIssuerID "$AUTH_KEY_ISSUER"

echo "== Done. App Store Connect でビルド処理を確認してください =="
