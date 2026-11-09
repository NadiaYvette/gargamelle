#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-AUDIT-003 Verification Gate] ==="
echo "  [1/2] Building gargamelle-audit..."
cabal v2-build gargamelle-audit -j20 --semaphore

echo "  [2/2] Running Pedagogy tests..."
cabal v2-test gargamelle-audit-test -j20 --semaphore --test-option='-p' --test-option='Pedagogy'
echo "  [+] All TP-AUDIT-003 checks passed!"
