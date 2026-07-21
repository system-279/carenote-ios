#!/bin/bash
# Usage: ./scripts/set-vertex-ai-config.sh <MODEL_ID> <THINKING_LEVEL> [PROJECT]
# Example: ./scripts/set-vertex-ai-config.sh gemini-3.5-flash minimal carenote-dev-279
# Example: ./scripts/set-vertex-ai-config.sh gemini-3.5-flash minimal carenote-prod-279
#
# Sets platformConfig/vertexAi, the Firestore document that lets an operator
# switch the Vertex AI transcription model/thinkingLevel without an App Store
# release. See ADR-012 for background. MODEL_ID/THINKING_LEVEL must still pass
# the iOS-side allowlist (CareNote/Models/VertexAIConfig.swift) or the app
# soft-fails back to its hardcoded default.

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <MODEL_ID> <THINKING_LEVEL> [PROJECT]" >&2
  exit 1
fi

MODEL_ID="$1"
THINKING_LEVEL="$2"
PROJECT="${3:-carenote-dev-279}"
ACCOUNT="system@279279.net"

# CLAUDE.md Dev/Prod 分離: prod への書込みは明示引数に加えて対話確認を必須にする
if [ "$PROJECT" = "carenote-prod-279" ]; then
  read -r -p "⚠️  carenote-prod-279 に platformConfig/vertexAi を書き込みます。よろしいですか？ (yes と入力): " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted." >&2
    exit 1
  fi
fi

TOKEN=$(gcloud auth print-access-token --account="$ACCOUNT")

echo "Setting platformConfig/vertexAi on project: $PROJECT (modelId=$MODEL_ID, thinkingLevel=$THINKING_LEVEL)"

BODY=$(jq -n --arg model "$MODEL_ID" --arg level "$THINKING_LEVEL" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
  fields: {
    modelId: { stringValue: $model },
    thinkingLevel: { stringValue: $level },
    updatedAt: { timestampValue: $ts }
  }
}')

HTTP_STATUS=$(curl -s -o /tmp/set-vertex-ai-config-response.json -w '%{http_code}' -X PATCH \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "x-goog-user-project: $PROJECT" \
  "https://firestore.googleapis.com/v1/projects/$PROJECT/databases/(default)/documents/platformConfig/vertexAi" \
  -d "$BODY")

python3 -m json.tool < /tmp/set-vertex-ai-config-response.json
rm -f /tmp/set-vertex-ai-config-response.json

if [ "$HTTP_STATUS" -ge 400 ]; then
  echo "❌ Firestore returned HTTP $HTTP_STATUS — platformConfig/vertexAi was NOT updated" >&2
  exit 1
fi

echo "✅ Set platformConfig/vertexAi on $PROJECT"
