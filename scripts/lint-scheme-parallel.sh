#!/usr/bin/env bash
# Lint: CareNote test scheme parallelization guard (Issue #170 H1 / #164)
#
# Cross-suite race in process-wide SharedTestModelContainer caused #164.
# Root cause: Swift Testing's `@Suite(.serialized)` only serializes WITHIN
# a suite, not BETWEEN suites. With a shared SwiftData container, another
# suite's `cleanup()` could fire mid-test-body of the active suite,
# corrupting fetch results (e.g., uploadCalls.count == 0).
#
# Fix: force every test scheme to disable parallelization at the scheme
# level (defense in depth alongside CI's `-parallel-testing-enabled NO`).
# This lint catches regressions where someone re-enables parallelization
# in project.yml, edits the scheme by hand, or adds a new scheme.
#
# Detection: walk every committed *.xcscheme and assert that EVERY
# <TestableReference> entry explicitly carries `parallelizable="NO"`.
# The pattern is anchored to the tag opening so a `parallelizable="NO"`
# on an unrelated future element (e.g., <TestPlanReference>) cannot
# satisfy the assertion. `perl -0777` slurp tolerates Xcode's
# cross-line attribute formatting (matches scripts/lint-model-container.sh).
#
# Usage:
#   bash scripts/lint-scheme-parallel.sh
#
# Exit codes:
#   0  every scheme correctly disables test parallelization
#   1  parallelization re-enabled, scheme missing/empty, or count mismatch

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEMES_DIR="CareNote.xcodeproj/xcshareddata/xcschemes"

# Pre-flight: schemes directory must exist. Schemes are committed
# alongside project.pbxproj (xcodegen output is treated as source-of-truth).
if [ ! -d "$SCHEMES_DIR" ]; then
  echo "::error::Schemes directory missing: $SCHEMES_DIR"
  echo "Run 'xcodegen generate' to materialize schemes from project.yml."
  exit 1
fi

# Collect every committed scheme. Sort for deterministic CI output.
mapfile -t SCHEMES < <(find "$SCHEMES_DIR" -name '*.xcscheme' | sort)
if [ "${#SCHEMES[@]}" -eq 0 ]; then
  echo "::error::No *.xcscheme files in $SCHEMES_DIR — cannot enforce parallelization guard."
  exit 1
fi

failed=0
checked_with_tests=0
for SCHEME in "${SCHEMES[@]}"; do
  # Empty-file guard. `perl -0777 -ne 'exit (/.../ ? 0 : 1)'` runs the
  # END block 0 times for an empty file and so exits 0 — silently
  # turning every regex assertion into a green pass. Refuse to lint
  # an empty scheme.
  if [ ! -s "$SCHEME" ]; then
    echo "::error::Scheme is empty: $SCHEME"
    failed=1
    continue
  fi

  # Count <TestableReference …> openings. Schemes with no TestAction
  # (build-only schemes) have zero, and are outside this guard's scope.
  testable_count=$(perl -0777 -ne 'my @m = /<TestableReference\b/g; print scalar(@m)' "$SCHEME")
  if [ "$testable_count" -eq 0 ]; then
    continue
  fi

  # Negative assertion: no <TestableReference …> may carry
  # parallelizable="YES". Anchored to the tag opening so the match
  # cannot leak across element boundaries; [^>]*? tolerates any
  # attribute order. /s flag lets [^>]*? span newlines.
  yes_count=$(perl -0777 -ne 'my @m = /<TestableReference\b[^>]*?parallelizable\s*=\s*"YES"/gs; print scalar(@m)' "$SCHEME")
  if [ "$yes_count" -gt 0 ]; then
    echo "::error::$SCHEME has $yes_count <TestableReference> with parallelizable=\"YES\"."
    echo ""
    echo "Cross-suite parallelization re-enables the race that caused Issue #164:"
    echo "SharedTestModelContainer cleanup() in suite A interleaves with the test"
    echo "body of suite B, returning empty fetch results."
    echo ""
    echo "Fix: set parallelizable: false in project.yml schemes.<name>.test.targets[]"
    echo "and re-run 'xcodegen generate'."
    failed=1
    continue
  fi

  # Positive ALL assertion: every <TestableReference …> must carry
  # parallelizable="NO" explicitly. A missing attribute defaults to
  # parallel on some Xcode scheme versions, so absence is also a
  # regression — counting NO matches and comparing to the total
  # <TestableReference> count catches both "missing" and "different
  # value" forms.
  no_count=$(perl -0777 -ne 'my @m = /<TestableReference\b[^>]*?parallelizable\s*=\s*"NO"/gs; print scalar(@m)' "$SCHEME")
  if [ "$no_count" -ne "$testable_count" ]; then
    missing=$((testable_count - no_count))
    echo "::error::$SCHEME has $missing of $testable_count <TestableReference> without explicit parallelizable=\"NO\"."
    echo ""
    echo "Implicit parallelizable defaults to parallel on some Xcode scheme versions."
    echo "Fix: set parallelizable: false in project.yml schemes.<name>.test.targets[]"
    echo "and re-run 'xcodegen generate'."
    failed=1
    continue
  fi

  checked_with_tests=$((checked_with_tests + 1))
done

if [ "$failed" -ne 0 ]; then
  exit 1
fi

echo "lint-scheme-parallel: OK (${#SCHEMES[@]} scheme(s) scanned, $checked_with_tests with TestAction, all <TestableReference> have parallelizable=\"NO\")"
