#!/bin/bash
# Usage: ./scripts/set-tenant-claim.sh <USER_UID> <TENANT_ID>
# Example: ./scripts/set-tenant-claim.sh abc123 test-tenant-1

set -euo pipefail

UID_ARG="${1:?Usage: $0 <USER_UID> <TENANT_ID>}"
TENANT_ID="${2:?Usage: $0 <USER_UID> <TENANT_ID>}"
PROJECT="carenote-dev-279"
ACCOUNT="system@279279.net"

TOKEN=$(gcloud auth print-access-token --account="$ACCOUNT")

curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: $PROJECT" \
  "https://identitytoolkit.googleapis.com/v1/projects/$PROJECT/accounts:update" \
  -d "{
    \"localId\": \"$UID_ARG\",
    \"customAttributes\": \"{\\\"tenantId\\\": \\\"$TENANT_ID\\\"}\"
  }" | python3 -m json.tool

echo "✅ Set tenantId='$TENANT_ID' on user $UID_ARG"
