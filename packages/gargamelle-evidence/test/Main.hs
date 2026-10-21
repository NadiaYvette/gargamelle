module Main (main) where

import Test.Hspec
import Data.Proxy (Proxy(..))
import Data.Tree (Tree(..))
import qualified Data.HashMap.Strict as HM
import Data.TreeDiff.Tree (treeDiff)
import Evidence

-- Dummy signature for testing EvidenceContext
data DummySig

main :: IO ()
main = hspec $ do
  describe "Evidence (EvidenceStore & Exact Match)" $ do
    -- See Note [Structural AST Change Tracking via Tree-Diff] [ref:note-structural-tree-diff]
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
    -- See Note [Structural AST Change Tracking via Tree-Diff] [ref:note-structural-tree-diff]
    it "computes structural tree edit distance" $ do
      let treeA = Node "Func" [Node "ParamA" []]
      let treeB = Node "Func" [Node "ParamB" []]
      let diff = treeDiff treeA treeB
      -- Swap 1 leaf node = edit distance 2
      editDistance diff `shouldBe` 2

    it "identifies identical trees with 0 edit distance" $ do
      let tree = Node "App" [Node "f" [], Node "x" []]
      let diff = treeDiff tree tree
      editDistance diff `shouldBe` 0
