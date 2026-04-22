#!/usr/bin/env bash
# Lint: Schema drift risk guard for SwiftData @Model types (Issue #165)
#
# SwiftData SIGTRAPs when the same `@Model` type is registered in multiple
# `ModelContainer`s within one process (Issue #141). To prevent regression of
# the shared-container fix introduced in PR #163, this lint enforces that
# `ModelContainer(for:` appears only in the approved test helper.
#
# When a new `@Model` type is added, update:
#   - CareNoteTests/TestHelpers/SwiftDataTestHelper.swift  (init + cleanup)
#   - CareNote/Services/LocalDataCleaner.swift             (purgeAll operations)
#   - Every `Schema([...])` site in CareNote/               (production previews + app)
#
# Usage:
#   bash scripts/lint-model-container.sh
#
# Exit codes:
#   0  clean
#   1  drift detected

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ALLOWED_TEST_FILE="CareNoteTests/TestHelpers/SwiftDataTestHelper.swift"

# Test-side: ModelContainer(for:) must appear only in the approved helper.
violations=$(
  grep -rlE 'ModelContainer\(\s*for:' CareNoteTests 2>/dev/null \
    | grep -v "^${ALLOWED_TEST_FILE}\$" \
    || true
)

if [ -n "$violations" ]; then
  echo "::error::ModelContainer(for:) found outside the approved test helper."
  echo ""
  echo "Per Issue #141 / #165, per-suite ModelContainer allocation is banned"
  echo "to prevent SwiftData SIGTRAPs from duplicate @Model type registration."
  echo "Allowed file: ${ALLOWED_TEST_FILE}"
  echo ""
  echo "Offending files:"
  echo "$violations" | sed 's/^/  - /'
  echo ""
  echo "Fix: route tests through SharedTestModelContainer.shared instead."
  exit 1
fi

echo "lint-model-container: OK (only ${ALLOWED_TEST_FILE} registers @Model types for tests)"
