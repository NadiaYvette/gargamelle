#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-AUDIT-002] Deploying Gargamelle.Audit.Scent & Gargamelle.Audit.DocTier ==="

if [ ! -f cabal.project.local ] && [ -f /home/nyc/src/gargamelle/cabal.project.local ]; then
  cp -f /home/nyc/src/gargamelle/cabal.project.local ./cabal.project.local
fi

mkdir -p packages/gargamelle-audit/src/Gargamelle/Audit

# Mount verbatim seeds
cp -f /home/nyc/src/plans/seeds/TP-AUDIT-002-Scent.hs packages/gargamelle-audit/src/Gargamelle/Audit/Scent.hs
cp -f /home/nyc/src/plans/seeds/TP-AUDIT-002-DocTier.hs packages/gargamelle-audit/src/Gargamelle/Audit/DocTier.hs
cp -f /home/nyc/src/plans/seeds/TP-AUDIT-002.cabal packages/gargamelle-audit/gargamelle-audit.cabal
cp -f /home/nyc/src/plans/seeds/TP-AUDIT-002-test-Main.hs packages/gargamelle-audit/test/Main.hs

chmod +x packages/gargamelle-audit/src/Gargamelle/Audit/*.hs || true
echo "=== [TP-AUDIT-002] Files mounted successfully ==="
