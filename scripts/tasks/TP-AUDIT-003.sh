#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-AUDIT-003] Deploying Gargamelle.Audit.ApiGraph & Gargamelle.Audit.Pedagogy ==="

if [ ! -f cabal.project.local ] && [ -f /home/nyc/src/gargamelle/cabal.project.local ]; then
  cp -f /home/nyc/src/gargamelle/cabal.project.local ./cabal.project.local
fi

mkdir -p packages/gargamelle-audit/src/Gargamelle/Audit

# 1. Mount verbatim seeds
cp -f /home/nyc/src/plans/seeds/TP-AUDIT-003-ApiGraph.hs packages/gargamelle-audit/src/Gargamelle/Audit/ApiGraph.hs
cp -f /home/nyc/src/plans/seeds/TP-AUDIT-003-Pedagogy.hs packages/gargamelle-audit/src/Gargamelle/Audit/Pedagogy.hs

# 2. Expose modules in gargamelle-audit.cabal
python3 -c '
with open("packages/gargamelle-audit/gargamelle-audit.cabal", "r") as f:
    content = f.read()

if "Gargamelle.Audit.ApiGraph" not in content:
    content = content.replace(
        "    Gargamelle.Audit.DocTier\n",
        "    Gargamelle.Audit.DocTier\n    Gargamelle.Audit.ApiGraph\n    Gargamelle.Audit.Pedagogy\n"
    )

with open("packages/gargamelle-audit/gargamelle-audit.cabal", "w") as f:
    f.write(content)
'

# 3. Add Pedagogy test group to test/Main.hs
python3 -c '
with open("packages/gargamelle-audit/test/Main.hs", "r") as f:
    content = f.read()

if "Gargamelle.Audit.ApiGraph" not in content:
    content = content.replace(
        "import Gargamelle.Audit.DocTier\n",
        "import Gargamelle.Audit.ApiGraph\n  ( verifyApiExplorationGraph\n  )\nimport Gargamelle.Audit.Pedagogy\n  ( verifyDocumentationCorpus\n  )\nimport Gargamelle.Audit.DocTier\n"
    )

if "testPedagogyVerifier" not in content:
    content = content.replace(
        "  , testDocTierVerifier\n  ]",
        "  , testDocTierVerifier\n  , testPedagogyVerifier\n  ]"
    )

    pedagogy_test = """
--------------------------------------------------------------------------------
-- 6. Pedagogy & ApiGraph Verifier Test Group
--------------------------------------------------------------------------------

testPedagogyVerifier :: TestTree
testPedagogyVerifier = testGroup "Pedagogy"
  [ testCase "API Graph Diameter" $ do
      let src = T.unlines
            [ "module MyAPI where"
            , ""
            , "data PrimaryRope = PrimaryRope"
            , "data Adapter1 = Adapter1"
            , "data Adapter2 = Adapter2"
            , "data OrphanConfig = OrphanConfig"
            , ""
            , "hop1 :: PrimaryRope -> Adapter1"
            , "hop1 _ = Adapter1"
            , ""
            , "hop2 :: Adapter1 -> Adapter2"
            , "hop2 _ = Adapter2"
            , ""
            , "hop3 :: Adapter2 -> OrphanConfig"
            , "hop3 _ = OrphanConfig"
            ]
          violations = verifyApiExplorationGraph defaultAuditThresholds StandardModule "src/MyAPI.hs" src
          orphanViolations = [ v | v <- violations, avSymbol v == "OrphanConfig" ]
      case orphanViolations of
        [AuditViolation{ avCategory = ApiReachabilityExceeded _ (Just 3) 2 }] -> pure ()
        _ -> assertFailure ("Expected ApiReachabilityExceeded with measuredHops = Just 3, got: " ++ show orphanViolations)

  , testCase "Forward-Reference Detection and @spiral escape hatch" $ do
      let corpus =
            [ ( "docs/01-intro.md"
              , T.unlines
                  [ "<!-- @uses: TambaraModule -->"
                  , "# Introduction"
                  , "Here we introduce TambaraModule."
                  ]
              )
            , ( "docs/03-optics.md"
              , T.unlines
                  [ "<!-- @defines: TambaraModule -->"
                  , "# Optics"
                  , "Definition of TambaraModule."
                  ]
              )
            ]
          viols = verifyDocumentationCorpus defaultAuditThresholds "docs" corpus
          fwdViol = [ v | v <- viols, avSymbol v == "TambaraModule" ]
      assertEqual "Referencing TambaraModule in intro triggers PedagogicalForwardRef" 1 (length fwdViol)

      let corpusFixed =
            [ ( "docs/01-intro.md"
              , T.unlines
                  [ "<!-- @uses: TambaraModule -->"
                  , "<!-- @spiral: TambaraModule -->"
                  , "# Introduction"
                  , "Here we spiral-reference TambaraModule."
                  ]
              )
            , ( "docs/03-optics.md"
              , T.unlines
                  [ "<!-- @defines: TambaraModule -->"
                  , "# Optics"
                  , "Definition of TambaraModule."
                  ]
              )
            ]
          violsFixed = verifyDocumentationCorpus defaultAuditThresholds "docs" corpusFixed
          fwdViolFixed = [ v | v <- violsFixed, avSymbol v == "TambaraModule" ]
      assertEqual "Spiral escape hatch resolves PedagogicalForwardRef" 0 (length fwdViolFixed)

  , testCase "Paragraph Definition-Use Gap" $ do
      let docText = T.unlines
            [ "# Chapter"
            , ""
            , "Paragraph 1 with @use{tarskiCoboundary}."
            , ""
            , "Paragraph 2."
            , ""
            , "Paragraph 3."
            , ""
            , "Paragraph 4."
            , ""
            , "Paragraph 5."
            , ""
            , "Paragraph 6."
            , ""
            , "Paragraph 7 with @def{tarskiCoboundary}."
            ]
          viols = verifyDocumentationCorpus defaultAuditThresholds "docs" [("docs/chapter.md", docText)]
          gapViols = [ v | v <- viols, case avCategory v of ExcessiveDefUseGap {} -> True; _ -> False ]
      assertEqual "6 paragraphs gap triggers ExcessiveDefUseGap" 1 (length gapViols)
  ]
"""
    content = content + pedagogy_test

with open("packages/gargamelle-audit/test/Main.hs", "w") as f:
    f.write(content)
'

chmod +x packages/gargamelle-audit/src/Gargamelle/Audit/*.hs || true
echo "=== [TP-AUDIT-003] Files mounted successfully ==="
