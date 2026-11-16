#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-VCS-001D-verify] Building darcs-patch-index-prim ==="
cabal v2-build darcs-patch-index-prim -j20 --semaphore

echo "=== [TP-VCS-001D-verify] Testing darcs-patch-index-prim ==="
cabal v2-test darcs-patch-index-prim
