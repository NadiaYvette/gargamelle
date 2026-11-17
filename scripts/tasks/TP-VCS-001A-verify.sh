#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-VCS-001A-verify] Building darcs-witnesses ==="
cabal v2-build darcs-witnesses -j20 --semaphore

echo "=== [TP-VCS-001A-verify] Testing darcs-witnesses ==="
cabal v2-test darcs-witnesses
