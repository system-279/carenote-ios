#!/bin/bash
# Usage: ./scripts/set-tenant-claim.sh <USER_UID> <TENANT_ID> [ROLE] [PROJECT]
# Example: ./scripts/set-tenant-claim.sh abc123 test-tenant-1 admin
# Example: ./scripts/set-tenant-claim.sh abc123 279 admin carenote-prod-279

set -euo pipefail

UID_ARG="${1:?Usage: $0 <USER_UID> <TENANT_ID> [ROLE] [PROJECT]}"
TENANT_ID="${2:?Usage: $0 <USER_UID> <TENANT_ID> [ROLE] [PROJECT]}"
ROLE="${3:-user}"
PROJECT="${4:-carenote-dev-279}"
ACCOUNT="system@279279.net"

TOKEN=$(gcloud auth print-access-token --account="$ACCOUNT")

curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: $PROJECT" \
  "https://identitytoolkit.googleapis.com/v1/projects/$PROJECT/accounts:update" \
  -d "{
    \"localId\": \"$UID_ARG\",
    \"customAttributes\": \"{\\\"tenantId\\\": \\\"$TENANT_ID\\\", \\\"role\\\": \\\"$ROLE\\\"}\"
  }" | python3 -m json.tool

echo "✅ Set tenantId='$TENANT_ID', role='$ROLE' on user $UID_ARG (project: $PROJECT)"
