#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-SMIRK-007A Verification Gate] ==="

echo "  [1/2] Running gargamelle-core test suite..."
cabal test gargamelle-core

echo "  [2/2] Running gargamelle-fol test suite..."
cabal test gargamelle-fol

echo "=== [TP-SMIRK-007A Verification Gate PASSED] ==="
