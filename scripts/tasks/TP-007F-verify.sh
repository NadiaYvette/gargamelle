#!/usr/bin/env bash
set -euo pipefail

if [ ! -f cabal.project.local ] && [ -f /home/nyc/src/gargamelle/cabal.project.local ]; then
  cp -f /home/nyc/src/gargamelle/cabal.project.local ./cabal.project.local
fi

echo "=== [TP-007F-verify] Verifying gargamelle-sheaf ==="
cabal v2-test gargamelle-sheaf:test:tests
echo "=== [TP-007F-verify] Verification complete ==="
