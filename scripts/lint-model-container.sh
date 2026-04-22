#!/usr/bin/env bash
# Lint: Schema drift risk guard for SwiftData @Model types (Issue #165)
#
# SwiftData SIGTRAPs when the same `@Model` type is registered in multiple
# `ModelContainer`s within one process (Issue #141). To prevent regression of
# the shared-container fix introduced in PR #163, this lint enforces that
# `ModelContainer(...)` construction appears only in approved test files.
#
# When a new `@Model` type is added, update:
#   - CareNoteTests/TestHelpers/SwiftDataTestHelper.swift  (init + cleanup)
#   - CareNote/Services/LocalDataCleaner.swift             (purgeAll operations)
#   - Every `Schema([...])` site in CareNote/               (production previews + app)
# See `CareNote/Models/SwiftDataModels.swift` top-of-file comment for the
# authoritative production site list.
#
# Detection strategy: use `perl -0777` (slurp mode) so the pattern matches
# across newlines — the approved helper itself uses a multi-line constructor
# (`ModelContainer(\n  for: ...`), and any line-oriented grep would silently
# miss violations written in the same idiomatic style.
#
# Usage:
#   bash scripts/lint-model-container.sh
#
# Exit codes:
#   0  clean
#   1  drift detected, pre-flight failed, or tool error

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Files allowed to construct `ModelContainer(for:)`. Keep this list minimal;
# every entry must be justified in a comment that points to the tracking Issue.
ALLOWED_TEST_FILES=(
  # Canonical shared container (PR #163 root-cause fix for Issue #141).
  "CareNoteTests/TestHelpers/SwiftDataTestHelper.swift"
  # NOTE (Issue #164 investigation, 2026-04-22): OutboxSyncServiceTests.swift は
  # shared container に差し戻し済み。真因調査の観測点追加中につき暫定許可は不要。
  # 真因特定 or workaround 適用後、必要があれば許可を復活させる。
)

# Matches `ModelContainer[<Generic>](<newline/spaces>for:` — tolerates
# multi-line constructors, generic parameters, and arbitrary whitespace.
PATTERN='ModelContainer\s*(?:<[^>]*>)?\s*\(\s*for\s*:'

# Pre-flight 1: target directory must exist. If renamed/moved, a pure
# "no violations found" result would be a false green.
if [ ! -d CareNoteTests ]; then
  echo "::error::CareNoteTests directory missing — lint cannot verify drift guard."
  echo "If the test directory was reorganized, update ALLOWED_TEST_FILES in this script."
  exit 1
fi

# Pre-flight 2: each allowed file must exist and still contain the banned
# pattern. If absent, either the file was deleted (whitelist is stale) or
# the regex is broken (all violations silently pass). Either case is a
# drift-guard failure, not a clean state.
for allowed in "${ALLOWED_TEST_FILES[@]}"; do
  if [ ! -f "$allowed" ]; then
    echo "::error::Allowed test file missing: $allowed"
    echo "If the file was renamed/removed, update ALLOWED_TEST_FILES in this script."
    exit 1
  fi
  if ! perl -0777 -ne "exit (/$PATTERN/ ? 0 : 1)" "$allowed"; then
    echo "::error::$allowed no longer contains ModelContainer(for:) — either the file"
    echo "stopped registering @Model types (remove from ALLOWED_TEST_FILES), or the"
    echo "lint regex is broken. Either way the drift guard is invalid; fix before merging."
    exit 1
  fi
done

# Scan for violations: any *.swift under CareNoteTests/ (except allowed
# ones) that contains the banned pattern. `perl -0777` slurps each file
# so the pattern matches across newlines.
raw=$(
  find CareNoteTests -type f -name '*.swift' -print0 \
    | xargs -0 perl -0777 -ne 'print "$ARGV\n" if /'"$PATTERN"'/' \
    | sort -u
)

violations="$raw"
for allowed in "${ALLOWED_TEST_FILES[@]}"; do
  violations=$(printf '%s\n' "$violations" | grep -v "^${allowed}$" || true)
done

if [ -n "$violations" ]; then
  echo "::error::ModelContainer(for:) found outside the approved test files."
  echo ""
  echo "Per Issue #141 / #165, per-suite ModelContainer allocation is banned"
  echo "to prevent SwiftData SIGTRAPs from duplicate @Model type registration."
  echo "Allowed files:"
  for allowed in "${ALLOWED_TEST_FILES[@]}"; do
    echo "  - ${allowed}"
  done
  echo ""
  echo "Offending files:"
  printf '%s\n' "$violations" | sed 's/^/  - /'
  echo ""
  echo "Fix: route tests through SharedTestModelContainer.shared instead."
  exit 1
fi

echo "lint-model-container: OK (${#ALLOWED_TEST_FILES[@]} approved file(s) register @Model types)"
