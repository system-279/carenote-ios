#!/bin/bash
# Usage: ./scripts/seed-demo-guest-tenant.sh [PROJECT]
# Example: ./scripts/seed-demo-guest-tenant.sh carenote-dev-279
# Example: ./scripts/seed-demo-guest-tenant.sh carenote-prod-279
#
# Creates the demo-guest tenant document used by Apple Sign-In auto-provisioning.
# See ADR-007 for background.

set -euo pipefail

PROJECT="${1:-carenote-dev-279}"
ACCOUNT="system@279279.net"
TENANT_ID="demo-guest"

TOKEN=$(gcloud auth print-access-token --account="$ACCOUNT")

echo "Creating tenants/$TENANT_ID on project: $PROJECT"

curl -s -X PATCH \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: $PROJECT" \
  "https://firestore.googleapis.com/v1/projects/$PROJECT/databases/(default)/documents/tenants/$TENANT_ID" \
  -d '{
    "fields": {
      "name": { "stringValue": "Guest Tenant" },
      "allowedDomains": { "arrayValue": { "values": [] } },
      "createdAt": { "timestampValue": "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'" }
    }
  }' | python3 -m json.tool

echo "✅ Created tenants/$TENANT_ID on $PROJECT"
