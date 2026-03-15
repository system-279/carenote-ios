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
xcodebuild -exportArchive \
  -archivePath build/CareNote.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates

echo "== Done! Build $BUILD_NUMBER uploaded to App Store Connect =="
echo "== project.yml updated: CURRENT_PROJECT_VERSION=$BUILD_NUMBER =="
