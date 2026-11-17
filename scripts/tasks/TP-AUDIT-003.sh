#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-AUDIT-003] Deploying Gargamelle.Audit.ApiGraph & Gargamelle.Audit.Pedagogy ==="

if [ ! -f cabal.project.local ] && [ -f /home/nyc/src/gargamelle/cabal.project.local ]; then
  cp -f /home/nyc/src/gargamelle/cabal.project.local ./cabal.project.local
fi

mkdir -p packages/gargamelle-audit/src/Gargamelle/Audit

# Mount verbatim seeds
cp -f /home/nyc/src/plans/seeds/TP-AUDIT-003-ApiGraph.hs packages/gargamelle-audit/src/Gargamelle/Audit/ApiGraph.hs
cp -f /home/nyc/src/plans/seeds/TP-AUDIT-003-Pedagogy.hs packages/gargamelle-audit/src/Gargamelle/Audit/Pedagogy.hs
cp -f /home/nyc/src/plans/seeds/TP-AUDIT-003.cabal packages/gargamelle-audit/gargamelle-audit.cabal
cp -f /home/nyc/src/plans/seeds/TP-AUDIT-003-test-Main.hs packages/gargamelle-audit/test/Main.hs

chmod +x packages/gargamelle-audit/src/Gargamelle/Audit/*.hs || true
echo "=== [TP-AUDIT-003] Files mounted successfully ==="
