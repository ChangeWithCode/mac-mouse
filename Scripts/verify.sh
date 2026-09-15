#!/usr/bin/env bash
#
# Runs every check that does not require a Mac.
#
# The physics harness in Tools/physics-lab mirrors the Swift core and asserts
# its invariants. It needs only Node, so the maths stays verifiable on any
# machine — including CI without a macOS runner.

set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Physics core"
node Tools/physics-lab/spec.js

echo
echo "==> Scroll engine"
node Tools/physics-lab/engine.spec.js

echo
echo "==> Chord recogniser"
node Tools/physics-lab/chord.spec.js

echo
echo "==> Preset guard rails"
node Tools/physics-lab/presets.js

if command -v swift >/dev/null 2>&1; then
  echo
  echo "==> Swift tests"
  swift test
else
  echo
  echo "==> Swift tests skipped (no toolchain on this machine)"
fi
