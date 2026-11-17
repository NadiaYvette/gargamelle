#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-013C-verify] Building gargamelle-evidence ==="
cabal v2-build gargamelle-evidence -j20 --semaphore

echo "=== [TP-013C-verify] Testing gargamelle-evidence ==="
cabal v2-test gargamelle-evidence
