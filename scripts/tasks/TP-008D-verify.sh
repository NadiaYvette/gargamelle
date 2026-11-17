#!/usr/bin/env bash
set -euo pipefail

if [ ! -f cabal.project.local ] && [ -f /home/nyc/src/gargamelle/cabal.project.local ]; then
  cp -f /home/nyc/src/gargamelle/cabal.project.local ./cabal.project.local
fi

echo "=== [TP-008D-verify] Verifying gargamelle-core ==="
cabal v2-test gargamelle-core:test:tests
echo "=== [TP-008D-verify] Verification complete ==="
