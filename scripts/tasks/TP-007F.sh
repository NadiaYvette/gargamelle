#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-007F] Deploying Gargamelle.Sheaf.FFI ==="

mkdir -p packages/gargamelle-sheaf/src/Gargamelle/Sheaf

# 1. Mount seed
cp -f /home/nyc/src/plans/seeds/TP-007F-SheafFFI.hs packages/gargamelle-sheaf/src/Gargamelle/Sheaf/FFI.hs

# 2. Update gargamelle-sheaf.cabal
python3 -c '
with open("packages/gargamelle-sheaf/gargamelle-sheaf.cabal", "r") as f:
    content = f.read()

if "Gargamelle.Sheaf.FFI" not in content:
    content = content.replace("    Gargamelle.Sheaf.LatticeCohomology\n", "    Gargamelle.Sheaf.LatticeCohomology\n    Gargamelle.Sheaf.FFI\n")

if "penelope-core" not in content:
    content = content.replace("    proarrow >= 0.2 && < 0.3\n", "    proarrow >= 0.2 && < 0.3,\n    penelope-core >= 0.1 && < 0.2\n")

with open("packages/gargamelle-sheaf/gargamelle-sheaf.cabal", "w") as f:
    f.write(content)
'

# 3. Add FFI tests to packages/gargamelle-sheaf/test/Main.hs
python3 -c '
with open("packages/gargamelle-sheaf/test/Main.hs", "r") as f:
    content = f.read()

if "Gargamelle.Sheaf.FFI" not in content:
    content = content.replace("import Gargamelle.Sheaf.LatticeCohomology\n", "import Gargamelle.Sheaf.LatticeCohomology\nimport Gargamelle.Sheaf.FFI\nimport Penelope.Perceus (RTSProfile(..))\n")

ffi_test = """
  describe "Gargamelle.Sheaf.FFI (H1 Cohomological Obstructions & Synthesized Adapters)" do
    it "verifies identity zero-copy for compatible stalks" do
      let baseStalk name lang prof = ModuleStalkSpec
            { mssModuleName       = name
            , mssLanguage         = lang
            , mssRTSProfile       = prof
            , mssHasMultiShot     = False
            , mssMutatesInPlace   = False
            , mssSpawnsThreads    = False
            , mssProducesLazyList = False
            }
          caller = baseStalk "A" "C99" RTSFreestandingLinear
          callee = baseStalk "B" "C99" RTSFreestandingLinear
      verifyFFISheafEdge caller callee `shouldBe` Right ()
      synthesizeFFIBoundaryAdapter caller callee `shouldBe` AdapterIdentityZeroCopy

    it "detects NonDet crossing linear mutation and synthesizes CloneOnBacktrack" do
      let baseStalk name lang prof = ModuleStalkSpec
            { mssModuleName       = name
            , mssLanguage         = lang
            , mssRTSProfile       = prof
            , mssHasMultiShot     = False
            , mssMutatesInPlace   = False
            , mssSpawnsThreads    = False
            , mssProducesLazyList = False
            }
          caller = (baseStalk "M" "Mercury" RTSLean4ThreadLocal) { mssHasMultiShot = True }
          callee = (baseStalk "R" "Rust" RTSFreestandingLinear) { mssMutatesInPlace = True }
      verifyFFISheafEdge caller callee `shouldBe` Left [ObstructionNonDetCrossesLinear "M" "R"]
      synthesizeFFIBoundaryAdapter caller callee `shouldBe` AdapterCloneOnBacktrack "__organ_ffi_clone_on_backtrack_M_to_R"
"""

if "Gargamelle.Sheaf.FFI (H1 Cohomological Obstructions" not in content:
    content = content.rstrip() + "\n" + ffi_test

with open("packages/gargamelle-sheaf/test/Main.hs", "w") as f:
    f.write(content)
'

echo "=== [TP-007F] Building and testing ==="
cabal v2-build gargamelle-sheaf -j20 --semaphore
cabal v2-test gargamelle-sheaf:test:tests

echo "=== [TP-007F] Script execution complete ==="
