#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-VCS-001C-verify] Building darcs-prim-structural ==="
cabal v2-build darcs-prim-structural -j20 --semaphore

echo "=== [TP-VCS-001C-verify] Testing darcs-prim-structural ==="
cabal v2-test darcs-prim-structural
