{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedRecordDot #-}

module Main (main) where

import Test.Hspec
import Data.Proxy (Proxy(..))
import Data.Tree (Tree(..))
import qualified Data.HashMap.Strict as HM
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.ByteString as BS
import Data.TreeDiff.Tree (treeDiff)
import Evidence
import Darcs.Patch.Witnesses
  ( FL(..)
  , (:>)(..)
  , (:\/:)(..)
  , (:/\:)(..)
  , Sealed2(..)
  , Invert(..)
  , Commute(..)
  )
import Gargamelle.Core.Institution.Liquid
import Gargamelle.Evidence.GitBundle
import Gargamelle.Evidence.Patch.Prim
import Gargamelle.Evidence.Patch.Bundle
import Gargamelle.FOL.LiquidHyperdoctrine (Z3Hyperdoctrine(..), Context(..), QualifierBasis(..), FOLFormula(..))
import Gargamelle.Sheaf.LatticeCohomology (SheafVertexSpec(..))

-- Dummy signature for testing EvidenceContext
data DummySig

main :: IO ()
main = hspec $ do
  describe "Evidence (EvidenceStore & Exact Match)" $ do
    it "treats emptyEvidenceStore as identity" $ do
      let store = emptyEvidenceStore :: EvidenceStore DummySig
      unEvidenceStore (store <> mempty) `shouldBe` HM.empty

    it "records failure and detects known failing proposal" $ do
      let rep1 = StructuralRep "RootA" (Node "RootA" [Node "Child1" []])
      let rep2 = StructuralRep "RootB" (Node "RootB" [Node "Child2" []])
      let ev1 = Evidence rep1 (TypeError "type mismatch: expected Int, got Bool") Proxy
      let store1 = addEvidence ev1 (emptyEvidenceStore :: EvidenceStore DummySig)

      proposesKnownFailure rep1 store1 `shouldBe` True
      proposesKnownFailure rep2 store1 `shouldBe` False

      case checkProposal rep1 store1 of
        Just ev -> evidenceReason ev `shouldBe` TypeError "type mismatch: expected Int, got Bool"
        Nothing -> expectationFailure "Expected known failure, got Nothing"

      checkProposal rep2 store1 `shouldBe` Nothing

  describe "Evidence (Structural Tree-Diff Edit Distance)" $ do
    it "computes structural tree edit distance" $ do
      let treeA = Node "Func" [Node "ParamA" []]
      let treeB = Node "Func" [Node "ParamB" []]
      let diff = treeDiff treeA treeB
      editDistance diff `shouldBe` 2

    it "identifies identical trees with 0 edit distance" $ do
      let tree = Node "App" [Node "f" [], Node "x" []]
      let diff = treeDiff tree tree
      editDistance diff `shouldBe` 0

  describe "Gargamelle.Evidence.GitBundle" $ do
    it "computes canonical blob, tree, and commit OIDs" $ do
      let blobOid = computeBlobOid "hello world\n"
      unOidHex (unBlobOid blobOid) `shouldBe` "3b18e512dba79e4c8300dd08aeb37f8e728b8dad"

    it "emits valid fast-import stream" $ do
      let stream = emitGitFastImportStream
            [ ("refs/heads/main", "Initial commit", [("README.md", "# Test\n")]) ]
      BS.isPrefixOf "commit refs/heads/main\n" stream `shouldBe` True

    it "stores and extracts custom institutional metadata in git bundles" $ do
      let baseBundle = GitBundleV2 [] [] []
          packetId = "TP-013A"
          metadata = "{\"status\": \"witnessed\", \"cohomology_H1\": 0}"
          bundleWithMeta = storeGpatchMetadata packetId metadata baseBundle
          extracted = extractGpatchMetadata packetId bundleWithMeta
      extracted `shouldBe` Just metadata

  describe "Gargamelle.Evidence.Patch.Prim" $ do
    it "inverts AST DPO edits involutively" $ do
      let dpo = PrimAstDPO "src/Foo.hs" (SymbolKey "bar") (DPOSpan "bar = 1" "bar = 2") :: PrimPatch () ()
      invert (invert dpo) `shouldBe` dpo

    it "commutes distinct declaration-keyed AST DPO edits" $ do
      let d1 = PrimAstDPO "src/Foo.hs" (SymbolKey "funcA") (DPOSpan "funcA = 1" "funcA = 2") :: PrimPatch () ()
          d2 = PrimAstDPO "src/Foo.hs" (SymbolKey "funcB") (DPOSpan "funcB = True" "funcB = False") :: PrimPatch () ()
      case commute (d1 :> d2) of
        Just (PrimAstDPO f2 sym2 _ :> PrimAstDPO f1 sym1 _) -> do
          f2 `shouldBe` "src/Foo.hs"
          sym2 `shouldBe` SymbolKey "funcB"
          f1 `shouldBe` "src/Foo.hs"
          sym1 `shouldBe` SymbolKey "funcA"
        _ -> expectationFailure "Expected commute to succeed"

  describe "Gargamelle.Evidence.Patch.Bundle" $ do
    let vspec idName = SheafVertexSpec
          { svVertexId = idName
          , svSig = emptySig
          , svContext = Context Map.empty
          , svBasis = QualifierBasis Set.empty
          , svLocalGuarantee = FTrue
          , svLocalRequirement = FTrue
          }
        p1 = GPatch
          { gpPatchId = PatchId "P1"
          , gpContextDeps = Set.empty
          , gpBaseTreeOid = TreeOid (OidHex "1111111111111111111111111111111111111111")
          , gpResultTreeOid = TreeOid (OidHex "2222222222222222222222222222222222222222")
          , gpPrims = PrimCabalSet "foo.cabal" "exposed-modules" SetInsert "ModA" :>: NilFL
          , gpSigMorphism = emptyMorphism
          , gpVertexSpec = vspec "v1"
          }
        p2 = GPatch
          { gpPatchId = PatchId "P2"
          , gpContextDeps = Set.empty
          , gpBaseTreeOid = TreeOid (OidHex "2222222222222222222222222222222222222222")
          , gpResultTreeOid = TreeOid (OidHex "3333333333333333333333333333333333333333")
          , gpPrims = PrimCabalSet "foo.cabal" "exposed-modules" SetInsert "ModB" :>: NilFL
          , gpSigMorphism = emptyMorphism
          , gpVertexSpec = vspec "v2"
          }

    it "commutes two sheaf-gated GPatch bundles under Z3Hyperdoctrine" $ do
      mRes <- commuteGPatch Z3Hyperdoctrine (p1 :> p2)
      case mRes of
        Just (p2' :> p1') -> do
          gpPatchId p2' `shouldBe` PatchId "P2"
          gpPatchId p1' `shouldBe` PatchId "P1"
        Nothing -> expectationFailure "Expected commuteGPatch to succeed"

    it "clean-merges two parallel GPatch bundles under Z3Hyperdoctrine" $ do
      mRes <- mergeGPatchParallel Z3Hyperdoctrine (p1 :\/: p2)
      case mRes of
        Just (p2' :/\: p1') -> do
          gpPatchId p2' `shouldBe` PatchId "P2"
          gpPatchId p1' `shouldBe` PatchId "P1"
          Set.member (PatchId "P1") (gpContextDeps p2') `shouldBe` True
          Set.member (PatchId "P2") (gpContextDeps p1') `shouldBe` True
        Nothing -> expectationFailure "Expected mergeGPatchParallel to succeed"

    it "serializes and round-trips a .gpatch bundle file" $ do
      let tmpPath = "/tmp/test-gpatch-bundle.gpatch"
      writeGPatchBundle tmpPath p1
      sealed <- readGPatchBundle tmpPath
      -- sealed restores GPatch
      case sealed of
        Sealed2 pRestored -> do
          gpPatchId pRestored `shouldBe` PatchId "P1"
