#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-VCS-001B-verify] Building git-bundle-pure ==="
cabal v2-build git-bundle-pure -j20 --semaphore

echo "=== [TP-VCS-001B-verify] Testing git-bundle-pure ==="
cabal v2-test git-bundle-pure
