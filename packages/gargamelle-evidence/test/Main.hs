{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Test.Hspec
import Data.Proxy (Proxy(..))
import Data.Tree (Tree(..))
import qualified Data.HashMap.Strict as HM
import qualified Data.ByteString as BS
import Data.TreeDiff.Tree (treeDiff)
import Evidence
import Gargamelle.Evidence.GitBundle
import Gargamelle.Evidence.Patch.Prim

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

    it "encodes and decodes git bundle with metadata" $ do
      let blob = GitObject ObjBlob "file content\n"
          baseBundle = GitBundleV2 [] [BundleRef (hashGitObject blob) "refs/heads/main"] [blob]
          bundle = storeGpatchMetadata "TP-013A" "meta-payload" baseBundle
          encoded = encodeGitBundleV2 bundle
      case decodeGitBundleV2Header encoded of
        Left err -> expectationFailure ("Bundle header decode failed: " ++ err)
        Right (_, refs, _) -> do
          length refs `shouldBe` 2

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

    it "clean-merges parallel independent structural edits" $ do
      let p = PrimCabalSet "foo.cabal" "exposed-modules" SetInsert "ModuleA" :: PrimPatch () ()
          q = PrimCabalSet "foo.cabal" "exposed-modules" SetInsert "ModuleB" :: PrimPatch () ()
      case cleanMerge (p :\/: q) of
        Just (q_after :/\: p_after) -> do
          case (q_after, p_after) of
            (PrimCabalSet _ _ _ itQ, PrimCabalSet _ _ _ itP) -> do
              itQ `shouldBe` "ModuleB"
              itP `shouldBe` "ModuleA"
            _ -> expectationFailure "Unexpected merged constructors"
        Nothing -> expectationFailure "Expected cleanMerge to succeed"
