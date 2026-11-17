#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-008D] Deploying Gargamelle.HostVM.PgclPushout ==="

# 0. Ensure cabal.project.local exists
if [ ! -f cabal.project.local ] && [ -f /home/nyc/src/gargamelle/cabal.project.local ]; then
  cp -f /home/nyc/src/gargamelle/cabal.project.local ./cabal.project.local
fi

mkdir -p packages/gargamelle-core/src/Gargamelle/HostVM

# 1. Mount seed
cp -f /home/nyc/src/plans/seeds/TP-008D-PgclPushout.hs packages/gargamelle-core/src/Gargamelle/HostVM/PgclPushout.hs

# 2. Expose module and add dependencies in packages/gargamelle-core/gargamelle-core.cabal
python3 -c '
with open("packages/gargamelle-core/gargamelle-core.cabal", "r") as f:
    content = f.read()

if "Gargamelle.HostVM.PgclPushout" not in content:
    content = content.replace("    Gargamelle.CodeGen.OrganIR\n", "    Gargamelle.CodeGen.OrganIR\n    Gargamelle.HostVM.PgclPushout\n")

extra_deps = """    penelope-core >= 0.1 && < 0.2,
    penelope-stage >= 0.1 && < 0.2,
    penelope-backend-mlir >= 0.1 && < 0.2,
    penelope-backend-gimple >= 0.1 && < 0.2,
    frankenstein,
    primitive >= 0.9 && < 0.10,
"""

if "penelope-stage" not in content:
    content = content.replace("  build-depends:\n", "  build-depends:\n" + extra_deps)

with open("packages/gargamelle-core/gargamelle-core.cabal", "w") as f:
    f.write(content)
'

# 3. Add tests to packages/gargamelle-core/test/Main.hs
python3 -c '
with open("packages/gargamelle-core/test/Main.hs", "r") as f:
    content = f.read()

if "Gargamelle.HostVM.PgclPushout" not in content:
    content = content.replace("import Gargamelle.CodeGen.OrganIR\n", "import Gargamelle.CodeGen.OrganIR\nimport Gargamelle.HostVM.PgclPushout\n")

hostvm_test = """
    describe "Gargamelle.HostVM.PgclPushout (Multi-OS Shim Categorical Pushout)" $ do
      it "sweeps all 5 target kernels (Linux, FreeBSD, illumos, seL4, Zircon)" $ do
        case sweepAllTargetKernels of
          Left err -> expectationFailure ("Expected successful kernel sweep, got error: " ++ show err)
          Right shims -> do
            length shims `shouldBe` 5
            let kernels = map sksKernel shims
            kernels `shouldBe` [KernelLinux, KernelFreeBSD, KernelIllumos, KernelSeL4, KernelZircon]
            all (T.isInfixOf "struct PolytroposRep" . sksProfunctorFunnelH) shims `shouldBe` True
"""

if "Gargamelle.HostVM.PgclPushout (Multi-OS Shim" not in content:
    content = content.rstrip() + "\n" + hostvm_test

with open("packages/gargamelle-core/test/Main.hs", "w") as f:
    f.write(content)
'

echo "=== [TP-008D] Building and testing ==="
cabal v2-build gargamelle-core -j20 --semaphore
cabal v2-test gargamelle-core:test:tests

echo "=== [TP-008D] Script execution complete ==="
