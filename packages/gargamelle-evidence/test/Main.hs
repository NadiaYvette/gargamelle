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
