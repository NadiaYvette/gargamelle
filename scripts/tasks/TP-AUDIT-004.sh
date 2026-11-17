#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-AUDIT-004] Deploying Gargamelle.Audit.Repair, Runner & gargamelle-audit CLI ==="

if [ ! -f cabal.project.local ] && [ -f /home/nyc/src/gargamelle/cabal.project.local ]; then
  cp -f /home/nyc/src/gargamelle/cabal.project.local ./cabal.project.local
fi

mkdir -p packages/gargamelle-audit/src/Gargamelle/Audit
mkdir -p packages/gargamelle-audit/app
mkdir -p bin

# 1. Mount verbatim seeds
cp -f /home/nyc/src/plans/seeds/TP-AUDIT-004-Repair.hs packages/gargamelle-audit/src/Gargamelle/Audit/Repair.hs
cp -f /home/nyc/src/plans/seeds/TP-AUDIT-004-Runner.hs packages/gargamelle-audit/src/Gargamelle/Audit/Runner.hs
cp -f /home/nyc/src/plans/seeds/TP-AUDIT-004-Main.hs packages/gargamelle-audit/app/Main.hs
cp -f /home/nyc/src/plans/seeds/TP-AUDIT-004.cabal packages/gargamelle-audit/gargamelle-audit.cabal

# 2. Create bin/gargamelle-audit wrapper
cat << 'EOF' > bin/gargamelle-audit
#!/usr/bin/env bash
exec cabal run gargamelle-audit -- "$@"
EOF
chmod +x bin/gargamelle-audit

# 3. Update or create bin/gargamelle-verify
cat << 'EOF' > bin/gargamelle-verify
#!/usr/bin/env bash
set -euo pipefail

echo "=== [gargamelle-verify] Running all repository verification gates ==="
cabal v2-build gargamelle-audit -j20 --semaphore
cabal v2-test gargamelle-audit-test -j20 --semaphore
cabal run gargamelle-audit -- check --self-test
echo "=== [gargamelle-verify] All gates passed successfully! ==="
EOF
chmod +x bin/gargamelle-verify

chmod +x packages/gargamelle-audit/src/Gargamelle/Audit/*.hs || true
chmod +x packages/gargamelle-audit/app/*.hs || true
echo "=== [TP-AUDIT-004] Files mounted successfully ==="
