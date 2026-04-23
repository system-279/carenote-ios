#!/usr/bin/env bash
# Lint: CareNote test scheme parallelization guard (Issue #170 H1 / #164)
#
# Cross-suite race in process-wide SharedTestModelContainer caused #164.
# Root cause: Swift Testing's `@Suite(.serialized)` only serializes WITHIN
# a suite, not BETWEEN suites. With shared SwiftData container, another
# suite's `cleanup()` could fire mid-test-body of the active suite,
# corrupting fetch results (e.g., uploadCalls.count == 0).
#
# Fix (PR for #170 H1): force the test scheme to be non-parallelizable
# at the scheme level (defense in depth alongside CI's
# `-parallel-testing-enabled NO`). This lint catches regressions where
# someone re-enables parallelization in project.yml or via Xcode UI.
#
# Detection: parse the generated scheme XML and assert that ALL
# <TestableReference> entries have `parallelizable="NO"` and that NO
# entry has `parallelizable="YES"`. The positive assertion guards
# against a missing attribute (which Xcode treats as parallelizable=YES
# on some scheme versions).
#
# Implementation: `perl -0777` slurp (matches the established pattern in
# scripts/lint-model-container.sh). xcodegen currently emits the
# attribute on the same line as the tag, but Xcode's own scheme editor
# may break long attribute lists across newlines on save — a
# line-oriented `grep` would silently false-green that case.
#
# Usage:
#   bash scripts/lint-scheme-parallel.sh
#
# Exit codes:
#   0  scheme correctly disables test parallelization
#   1  parallelization re-enabled, scheme missing, or assertion absent

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SCHEME="CareNote.xcodeproj/xcshareddata/xcschemes/CareNote.xcscheme"

# Tolerates whitespace + cross-line attributes (`parallelizable\n  = "YES"` etc.).
PARALLEL_YES_PATTERN='parallelizable\s*=\s*"YES"'
PARALLEL_NO_PATTERN='parallelizable\s*=\s*"NO"'

# Pre-flight: scheme must exist. xcodegen must have run before this lint
# (CI invokes `xcodegen generate` before any test step).
if [ ! -f "$SCHEME" ]; then
  echo "::error::Scheme not found: $SCHEME"
  echo "Run 'xcodegen generate' first. The scheme is now committed (was auto-generated"
  echo "before PR for #170 H1 added an explicit schemes: section to project.yml)."
  exit 1
fi

# Negative assertion: NO TestableReference may be parallelizable="YES".
# This is the regression guard.
if perl -0777 -ne "exit (/$PARALLEL_YES_PATTERN/ ? 0 : 1)" "$SCHEME"; then
  echo "::error::CareNote scheme has parallelizable=\"YES\" on a TestableReference."
  echo ""
  echo "Cross-suite parallelization re-enables the race that caused Issue #164:"
  echo "process-wide SharedTestModelContainer cleanup() in suite A interleaves"
  echo "with test body fetch in suite B, returning empty results."
  echo ""
  echo "Fix: ensure project.yml schemes.CareNote.test.targets[].parallelizable: false"
  echo "and re-run 'xcodegen generate'."
  exit 1
fi

# Positive assertion: at least one TestableReference must explicitly carry
# parallelizable="NO". A missing attribute would silently default to
# parallelizable behavior in some Xcode scheme versions, so we require
# the explicit declaration.
if ! perl -0777 -ne "exit (/$PARALLEL_NO_PATTERN/ ? 0 : 1)" "$SCHEME"; then
  echo "::error::CareNote scheme missing explicit parallelizable=\"NO\" declaration."
  echo ""
  echo "Without explicit NO, Xcode's default may parallelize tests. The fix"
  echo "must be load-bearing in the scheme XML, not implicit."
  echo ""
  echo "Fix: ensure project.yml schemes.CareNote.test.targets[].parallelizable: false"
  echo "and re-run 'xcodegen generate'."
  exit 1
fi

echo "lint-scheme-parallel: OK (CareNoteTests scheme has parallelizable=\"NO\")"
