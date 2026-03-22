#!/bin/bash
# Usage: ./scripts/set-role-claim.sh <USER_UID> <TENANT_ID> <ROLE>
# Example: ./scripts/set-role-claim.sh abc123 test-tenant-1 admin
# Roles: admin, user

set -euo pipefail

UID_ARG="${1:?Usage: $0 <USER_UID> <TENANT_ID> <ROLE>}"
TENANT_ID="${2:?Usage: $0 <USER_UID> <TENANT_ID> <ROLE>}"
ROLE="${3:?Usage: $0 <USER_UID> <TENANT_ID> <ROLE>}"
PROJECT="carenote-dev-279"
ACCOUNT="system@279279.net"

if [[ "$ROLE" != "admin" && "$ROLE" != "user" ]]; then
  echo "❌ Invalid role: $ROLE (must be 'admin' or 'user')"
  exit 1
fi

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

echo "✅ Set tenantId='$TENANT_ID', role='$ROLE' on user $UID_ARG"
