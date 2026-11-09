#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-AUDIT-004 Verification Gate] ==="
echo "  [1/2] Building gargamelle-audit..."
cabal v2-build gargamelle-audit -j20 --semaphore

echo "  [2/2] Running gargamelle-audit tests..."
cabal v2-test gargamelle-audit-test -j20 --semaphore

echo "  [3/3] Running self-test..."
cabal run gargamelle-audit -- check --self-test
echo "  [+] All TP-AUDIT-004 checks passed!"
