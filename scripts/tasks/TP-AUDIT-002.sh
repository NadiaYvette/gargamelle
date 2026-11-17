#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-AUDIT-002] Deploying Gargamelle.Audit.Scent & Gargamelle.Audit.DocTier ==="

# 0. Ensure cabal.project.local exists
if [ ! -f cabal.project.local ] && [ -f /home/nyc/src/gargamelle/cabal.project.local ]; then
  cp -f /home/nyc/src/gargamelle/cabal.project.local ./cabal.project.local
fi

mkdir -p packages/gargamelle-audit/src/Gargamelle/Audit

# 1. Mount verbatim seeds
cp -f /home/nyc/src/plans/seeds/TP-AUDIT-002-Scent.hs packages/gargamelle-audit/src/Gargamelle/Audit/Scent.hs
cp -f /home/nyc/src/plans/seeds/TP-AUDIT-002-DocTier.hs packages/gargamelle-audit/src/Gargamelle/Audit/DocTier.hs

# 2. Expose modules in gargamelle-audit.cabal
python3 -c '
with open("packages/gargamelle-audit/gargamelle-audit.cabal", "r") as f:
    content = f.read()

if "Gargamelle.Audit.Scent" not in content:
    content = content.replace(
        "    Gargamelle.Audit.WorkingMemory\n",
        "    Gargamelle.Audit.WorkingMemory\n    Gargamelle.Audit.Scent\n    Gargamelle.Audit.DocTier\n"
    )

with open("packages/gargamelle-audit/gargamelle-audit.cabal", "w") as f:
    f.write(content)
'

# 3. Add DocTier test group to test/Main.hs
python3 -c '
with open("packages/gargamelle-audit/test/Main.hs", "r") as f:
    content = f.read()

if "Gargamelle.Audit.DocTier" not in content:
    content = content.replace(
        "import Gargamelle.Audit.Baseline\n",
        "import Gargamelle.Audit.Baseline\nimport Gargamelle.Audit.DocTier\n  ( verifyModuleDocs\n  )\nimport Gargamelle.Audit.Scent\n  ( computeNovelStemRatio\n  )\n"
    )

if "KnowledgeSlot (..)" not in content:
    content = content.replace(
        "  , BaselineFingerprints (..)\n",
        "  , BaselineFingerprints (..)\n  , KnowledgeSlot (..)\n"
    )

if "testDocTierVerifier" not in content:
    content = content.replace(
        "  , testBaselinePersistence\n  ]",
        "  , testBaselinePersistence\n  , testDocTierVerifier\n  ]"
    )

    doc_tier_test = """
--------------------------------------------------------------------------------
-- 5. DocTier Verifier Test Group
--------------------------------------------------------------------------------

testDocTierVerifier :: TestTree
testDocTierVerifier = testGroup "DocTier"
  [ testCase "Tautology Rejection for rcast docstring ratio < 0.5 vs. >= 1.5" $ do
      let badDoc = "-- | Casts a record from t to s."
          badRatio = computeNovelStemRatio "rcast" "SubRow s t => Record f t -> Record f s" badDoc
      assertBool ("badRatio should be < 0.5, got: " ++ show badRatio) (badRatio < 0.5)

      let goodDoc = "-- | Projects a narrower target row in O(1) via SmallArray index slicing; preserves field invariants."
          goodRatio = computeNovelStemRatio "rcast" "SubRow s t => Record f t -> Record f s" goodDoc
      assertBool ("goodRatio should be >= 1.5, got: " ++ show goodRatio) (goodRatio >= 1.5)

  , testCase "Substrate Safety Slot" $ do
      let src = T.unlines
            [ "{-# ANN module \\"audit:substrate\\" #-}"
            , "module SubModule where"
            , ""
            , "{-|"
            , "@purpose Core low-level memory block"
            , "@behavior Direct memory allocations"
            , "@theory Linear address spaces"
            , "@contracts Total"
            , "@pattern Allocate and free"
            , "@example alloc 1024"
            , "-}"
            ]
          violations = verifyModuleDocs defaultAuditThresholds SubstrateMode "src/SubModule.hs" src
          missingSlots = [ s | AuditViolation{ avCategory = MissingKnowledgeSlots ms } <- violations, s <- ms ]
      assertEqual "Substrate module missing @safety_invariant must trigger MissingKnowledgeSlots [SlotSafetyInvariant]"
        [SlotSafetyInvariant] missingSlots

  , testCase "Exported ADT Check with MissingKnowledgeSlots [SlotTheory, SlotExample]" $ do
      let src = T.unlines
            [ "module MyTypes where"
            , ""
            , "{-|"
            , "@purpose High level domain entity"
            , "@behavior Wraps values"
            , "@contracts Pure"
            , "@pattern Value object"
            , "-}"
            , "data Entity = Entity Int"
            ]
          violations = verifyModuleDocs defaultAuditThresholds StandardModule "src/MyTypes.hs" src
          typeViolations = [ v | v <- violations, avSymbol v == "Entity" ]
      case typeViolations of
        [AuditViolation{ avCategory = MissingKnowledgeSlots ms }] ->
          assertEqual "Expected [SlotTheory, SlotExample]" [SlotTheory, SlotExample] ms
        _ -> assertFailure ("Expected MissingKnowledgeSlots for Entity, got: " ++ show typeViolations)
  ]
"""
    content = content + doc_tier_test

with open("packages/gargamelle-audit/test/Main.hs", "w") as f:
    f.write(content)
'

chmod +x packages/gargamelle-audit/src/Gargamelle/Audit/*.hs || true
echo "=== [TP-AUDIT-002] Files mounted successfully ==="
