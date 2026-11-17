#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-007F-verify] Verifying gargamelle-sheaf ==="
cabal v2-test gargamelle-sheaf:test:tests
echo "=== [TP-007F-verify] Verification complete ==="
