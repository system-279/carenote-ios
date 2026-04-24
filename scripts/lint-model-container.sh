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
# every entry MUST be preceded by an `# Issue #NNN:` justification comment
# (enforced by Pre-flight 3 below) that points to the tracking Issue — when
# someone hits a cross-suite regression like Issue #164 and is tempted to
# whitelist a new file, the comment requirement forces them to first record
# the investigation in a new Issue instead of silently expanding the allow-
# list and losing the drift-guard coverage.
ALLOWED_TEST_FILES=(
  # Issue #141: Canonical shared container (PR #163 root-cause fix).
  "CareNoteTests/TestHelpers/SwiftDataTestHelper.swift"
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

# Pre-flight 3: each allowed entry must be preceded by an `# Issue #NNN:`
# comment. Without this, a future engineer hitting a cross-suite regression
# (Issue #164 style) can silently expand the allow-list with a vague `# TODO`
# comment, erasing the drift-guard coverage without leaving an investigation
# trail. The check scans this very script so the policy is self-enforcing.
# Pattern: find the ALLOWED_TEST_FILES=( block, then assert every quoted
# entry's preceding non-blank line starts with `# Issue #`.
missing_issue_refs=$(
  perl -0777 -ne '
    my @lines = split /\n/;
    my $in_list = 0;
    my $prev_comment = "";
    for my $line (@lines) {
      if ($line =~ /^ALLOWED_TEST_FILES=\(/) { $in_list = 1; next; }
      if ($in_list && $line =~ /^\)/) { last; }
      if ($in_list) {
        # Quoted entry line (whitelisted file path)
        if ($line =~ /^\s*"([^"]+)"/) {
          my $entry = $1;
          if ($prev_comment !~ /^\s*#\s*Issue\s*#\d+:/i) {
            print "$entry\n";
          }
        }
        # Track the last non-blank comment line for the next entry
        if ($line =~ /^\s*#/) { $prev_comment = $line; }
        elsif ($line =~ /^\s*$/) { } # blank: keep prev_comment
        else { $prev_comment = ""; }
      }
    }
  ' "$0"
)
if [ -n "$missing_issue_refs" ]; then
  echo "::error::ALLOWED_TEST_FILES entries must be preceded by an '# Issue #NNN:' comment."
  echo ""
  echo "Entries without an Issue reference (add '# Issue #NNN: <justification>' above each):"
  printf '%s\n' "$missing_issue_refs" | sed 's/^/  - /'
  echo ""
  echo "If you are whitelisting a new file because of a cross-suite regression"
  echo "(Issue #164-style failure), FIRST open a new Issue with the investigation,"
  echo "then reference that Issue number here. Silent expansion of the allow-list"
  echo "erases the drift-guard coverage with no audit trail."
  exit 1
fi

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
  echo ""
  echo "If the offending file genuinely CANNOT use the shared container due to"
  echo "a cross-suite regression (Issue #164-style failure where the shared"
  echo "container's cleanup interacts badly with a specific test's timing):"
  echo "  1. Open a new Issue documenting the regression investigation"
  echo "     (repro steps, shared-container hypotheses tried, root cause)."
  echo "  2. Add the file to ALLOWED_TEST_FILES in this script with a"
  echo "     preceding '# Issue #NNN: <one-line justification>' comment."
  echo "  3. Do NOT add a file to the whitelist without an Issue reference —"
  echo "     Pre-flight 3 will reject it."
  exit 1
fi

echo "lint-model-container: OK (${#ALLOWED_TEST_FILES[@]} approved file(s) register @Model types)"
