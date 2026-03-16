#!/bin/bash
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

cd "$(dirname "$0")/.."

# ビルド番号: 引数 or project.yml から現在値+1
if [ -n "${1:-}" ]; then
  BUILD_NUMBER="$1"
else
  CURRENT=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/')
  BUILD_NUMBER=$((CURRENT + 1))
fi

# project.yml のビルド番号を更新
sed -i '' "s/CURRENT_PROJECT_VERSION: \"[0-9]*\"/CURRENT_PROJECT_VERSION: \"$BUILD_NUMBER\"/" project.yml

echo "== XcodeGen =="
xcodegen generate

echo "== Archive (v$(grep 'MARKETING_VERSION:' project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/'), build: $BUILD_NUMBER) =="
xcodebuild archive \
  -project CareNote.xcodeproj \
  -scheme CareNote \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath build/CareNote.xcarchive \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=C96A7EHVW8 \
  CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER"

echo "== Export + Upload =="
ASC_KEY_ID="PDP26W2YV4"
ASC_ISSUER_ID="60f20785-26ce-40bf-b274-1ad7560e3769"
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

xcodebuild -exportArchive \
  -archivePath build/CareNote.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "== Done! Build $BUILD_NUMBER uploaded to App Store Connect =="
echo "== project.yml updated: CURRENT_PROJECT_VERSION=$BUILD_NUMBER =="
