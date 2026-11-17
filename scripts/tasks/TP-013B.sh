#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-013B] Setting up Gargamelle.Evidence.Patch.Prim ==="

# 0. Ensure cabal.project.local exists
if [ ! -f cabal.project.local ] && [ -f /home/nyc/src/gargamelle/cabal.project.local ]; then
  cp -f /home/nyc/src/gargamelle/cabal.project.local ./cabal.project.local
fi

EVID_DIR="packages/gargamelle-evidence"
mkdir -p "$EVID_DIR/src/Gargamelle/Evidence/Patch"

# 1. Write Gargamelle.Evidence.Patch.Prim
cat << 'EOF' > "$EVID_DIR/src/Gargamelle/Evidence/Patch/Prim.hs"
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE StrictData #-}

module Gargamelle.Evidence.Patch.Prim
  ( -- * Primitives & Types
    SetOp(..)
  , CabalSection
  , HeaderSection
  , SymbolKey(..)
  , DPOSpan(..)
  , HoleId(..)
  , PrimPatch(..)
  , PatchId(..)
  , NamedPatch(..)
    -- * Category & Witnesses
  , FL(..)
  , RL(..)
  , (:>)(..)
  , (:\/:)(..)
  , (:/\:)(..)
  , Invert(..)
  , Commute(..)
  , CleanMerge(..)
    -- * Functions
  , invertPrim
  , commutePrim
  , cleanMergePrim
  ) where

import Data.ByteString (ByteString)
import Data.Kind (Type)
import Data.Set (Set)
import Data.Text (Text)
import GHC.Generics (Generic)
import Darcs.Patch.Witnesses
  ( FL(..)
  , RL(..)
  , (:>)(..)
  , (:\/:)(..)
  , (:/\:)(..)
  , Invert(..)
  , Commute(..)
  , CleanMerge(..)
  )
import Darcs.Patch.Prim.Structural (SetOp(..), invertSetOp)

type CabalSection = Text
type HeaderSection = Text

newtype SymbolKey = SymbolKey { unSymbolKey :: Text }
  deriving stock (Eq, Ord, Show, Generic)

data DPOSpan = DPOSpan
  { dpoBeforeAST :: !Text
  , dpoAfterAST  :: !Text
  } deriving stock (Eq, Ord, Show, Generic)

newtype HoleId = HoleId { unHoleId :: Text }
  deriving stock (Eq, Ord, Show, Generic)

newtype PatchId = PatchId { unPatchId :: ByteString }
  deriving stock (Eq, Ord, Show, Generic)

data NamedPatch p (wX :: Type) (wY :: Type) = NamedPatch
  { npId      :: !PatchId
  , npDeps    :: !(Set PatchId)
  , npPayload :: !(p wX wY)
  } deriving stock (Eq, Show, Generic)

-- | 5 Beyond-Darcs Structural Patch Primitives
data PrimPatch (wX :: Type) (wY :: Type) where
  -- 1. Cabal section set insertions / deletions
  PrimCabalSet
    :: !FilePath
    -> !CabalSection
    -> !SetOp
    -> !Text
    -> PrimPatch wX wY

  -- 2. Haskell header set insertions / deletions
  PrimHsHeaderSet
    :: !FilePath
    -> !HeaderSection
    -> !SetOp
    -> !Text
    -> PrimPatch wX wY

  -- 3. Declaration-keyed AST Double-Pushout rewrite
  PrimAstDPO
    :: !FilePath
    -> !SymbolKey
    -> !DPOSpan
    -> PrimPatch wX wY

  -- 4. Typed synthesis hole inside AST declaration
  PrimSynquidHole
    :: !FilePath
    -> !SymbolKey
    -> !HoleId
    -> !Text      -- ^ RSchema
    -> !Text      -- ^ QualifierBasis
    -> PrimPatch wX wY

  -- 5. Standard line hunk fallback
  PrimLineHunk
    :: !FilePath
    -> !Int       -- ^ 1-based line offset
    -> ![ByteString]
    -> ![ByteString]
    -> PrimPatch wX wY

deriving stock instance Eq (PrimPatch wX wY)
deriving stock instance Show (PrimPatch wX wY)

invertPrim :: PrimPatch wX wY -> PrimPatch wY wX
invertPrim = \case
  PrimCabalSet fp sec op item ->
    PrimCabalSet fp sec (invertSetOp op) item
  PrimHsHeaderSet fp sec op item ->
    PrimHsHeaderSet fp sec (invertSetOp op) item
  PrimAstDPO fp sym (DPOSpan beforeAST afterAST) ->
    PrimAstDPO fp sym (DPOSpan afterAST beforeAST)
  PrimSynquidHole fp sym hid schema basis ->
    PrimSynquidHole fp sym hid schema basis
  PrimLineHunk fp off oldLines newLines ->
    PrimLineHunk fp off newLines oldLines

instance Invert PrimPatch where
  invert = invertPrim

commutePrim
  :: (:>) PrimPatch PrimPatch wX wZ
  -> Maybe ((:>) PrimPatch PrimPatch wX wZ)
commutePrim (p :> q) = case (p, q) of
  -- 1. Cabal set operations
  (PrimCabalSet fp1 s1 op1 it1, PrimCabalSet fp2 s2 op2 it2)
    | (fp1, s1, it1) /= (fp2, s2, it2) ->
        Just (PrimCabalSet fp2 s2 op2 it2 :> PrimCabalSet fp1 s1 op1 it1)
    | otherwise -> Nothing

  -- 2. Haskell header set operations
  (PrimHsHeaderSet fp1 s1 op1 it1, PrimHsHeaderSet fp2 s2 op2 it2)
    | (fp1, s1, it1) /= (fp2, s2, it2) ->
        Just (PrimHsHeaderSet fp2 s2 op2 it2 :> PrimHsHeaderSet fp1 s1 op1 it1)
    | otherwise -> Nothing

  -- 3. AST DPO edits commute whenever they target different files or different declarations!
  (PrimAstDPO fp1 sym1 sp1, PrimAstDPO fp2 sym2 sp2)
    | (fp1, sym1) /= (fp2, sym2) ->
        Just (PrimAstDPO fp2 sym2 sp2 :> PrimAstDPO fp1 sym1 sp1)
    | otherwise -> Nothing

  -- 4. Holes and AST DPO edits on distinct symbols commute
  (PrimSynquidHole fp1 sym1 hid1 sch1 b1, PrimAstDPO fp2 sym2 sp2)
    | (fp1, sym1) /= (fp2, sym2) ->
        Just (PrimAstDPO fp2 sym2 sp2 :> PrimSynquidHole fp1 sym1 hid1 sch1 b1)
    | otherwise -> Nothing
  (PrimAstDPO fp1 sym1 sp1, PrimSynquidHole fp2 sym2 hid2 sch2 b2)
    | (fp1, sym1) /= (fp2, sym2) ->
        Just (PrimSynquidHole fp2 sym2 hid2 sch2 b2 :> PrimAstDPO fp1 sym1 sp1)
    | otherwise -> Nothing

  -- Distinct holes commute
  (PrimSynquidHole fp1 sym1 h1 sch1 b1, PrimSynquidHole fp2 sym2 h2 sch2 b2)
    | (fp1, sym1, h1) /= (fp2, sym2, h2) ->
        Just (PrimSynquidHole fp2 sym2 h2 sch2 b2 :> PrimSynquidHole fp1 sym1 h1 sch1 b1)
    | otherwise -> Nothing

  -- 5. Inter-domain structural commutations (Cabal, Header, AST DPO, Hole) ALWAYS commute!
  (PrimCabalSet fp1 s1 op1 it1, PrimHsHeaderSet fp2 s2 op2 it2) ->
    Just (PrimHsHeaderSet fp2 s2 op2 it2 :> PrimCabalSet fp1 s1 op1 it1)
  (PrimHsHeaderSet fp1 s1 op1 it1, PrimCabalSet fp2 s2 op2 it2) ->
    Just (PrimCabalSet fp2 s2 op2 it2 :> PrimHsHeaderSet fp1 s1 op1 it1)

  (PrimCabalSet fp1 s1 op1 it1, PrimAstDPO fp2 sym2 sp2) ->
    Just (PrimAstDPO fp2 sym2 sp2 :> PrimCabalSet fp1 s1 op1 it1)
  (PrimAstDPO fp1 sym1 sp1, PrimCabalSet fp2 s2 op2 it2) ->
    Just (PrimCabalSet fp2 s2 op2 it2 :> PrimAstDPO fp1 sym1 sp1)

  (PrimHsHeaderSet fp1 s1 op1 it1, PrimAstDPO fp2 sym2 sp2) ->
    Just (PrimAstDPO fp2 sym2 sp2 :> PrimHsHeaderSet fp1 s1 op1 it1)
  (PrimAstDPO fp1 sym1 sp1, PrimHsHeaderSet fp2 s2 op2 it2) ->
    Just (PrimHsHeaderSet fp2 s2 op2 it2 :> PrimAstDPO fp1 sym1 sp1)

  (PrimCabalSet fp1 s1 op1 it1, PrimSynquidHole fp2 sym2 h2 sch2 b2) ->
    Just (PrimSynquidHole fp2 sym2 h2 sch2 b2 :> PrimCabalSet fp1 s1 op1 it1)
  (PrimSynquidHole fp1 sym1 h1 sch1 b1, PrimCabalSet fp2 s2 op2 it2) ->
    Just (PrimCabalSet fp2 s2 op2 it2 :> PrimSynquidHole fp1 sym1 h1 sch1 b1)

  (PrimHsHeaderSet fp1 s1 op1 it1, PrimSynquidHole fp2 sym2 h2 sch2 b2) ->
    Just (PrimSynquidHole fp2 sym2 h2 sch2 b2 :> PrimHsHeaderSet fp1 s1 op1 it1)
  (PrimSynquidHole fp1 sym1 h1 sch1 b1, PrimHsHeaderSet fp2 s2 op2 it2) ->
    Just (PrimHsHeaderSet fp2 s2 op2 it2 :> PrimSynquidHole fp1 sym1 h1 sch1 b1)

  -- 6. Line hunks commute with each other when disjoint
  (PrimLineHunk fp1 off1 old1 new1, PrimLineHunk fp2 off2 old2 new2)
    | fp1 /= fp2 ->
        Just (PrimLineHunk fp2 off2 old2 new2 :> PrimLineHunk fp1 off1 old1 new1)
    | off1 + length new1 < off2 ->
        let delta = length new1 - length old1
        in Just ( PrimLineHunk fp2 (off2 - delta) old2 new2
                :> PrimLineHunk fp1 off1 old1 new1
                )
    | off2 + length old2 < off1 ->
        let delta = length new2 - length old2
        in Just ( PrimLineHunk fp2 off2 old2 new2
                :> PrimLineHunk fp1 (off1 + delta) old1 new1
                )
    | otherwise -> Nothing

  -- 7. Line hunks and structural edits commute across different files
  (PrimLineHunk fp1 off1 o1 n1, PrimCabalSet fp2 s2 op2 it2)
    | fp1 /= fp2 -> Just (PrimCabalSet fp2 s2 op2 it2 :> PrimLineHunk fp1 off1 o1 n1)
  (PrimCabalSet fp1 s1 op1 it1, PrimLineHunk fp2 off2 o2 n2)
    | fp1 /= fp2 -> Just (PrimLineHunk fp2 off2 o2 n2 :> PrimCabalSet fp1 s1 op1 it1)

  (PrimLineHunk fp1 off1 o1 n1, PrimHsHeaderSet fp2 s2 op2 it2)
    | fp1 /= fp2 -> Just (PrimHsHeaderSet fp2 s2 op2 it2 :> PrimLineHunk fp1 off1 o1 n1)
  (PrimHsHeaderSet fp1 s1 op1 it1, PrimLineHunk fp2 off2 o2 n2)
    | fp1 /= fp2 -> Just (PrimLineHunk fp2 off2 o2 n2 :> PrimHsHeaderSet fp1 s1 op1 it1)

  (PrimLineHunk fp1 off1 o1 n1, PrimAstDPO fp2 sym2 sp2)
    | fp1 /= fp2 -> Just (PrimAstDPO fp2 sym2 sp2 :> PrimLineHunk fp1 off1 o1 n1)
  (PrimAstDPO fp1 sym1 sp1, PrimLineHunk fp2 off2 o2 n2)
    | fp1 /= fp2 -> Just (PrimLineHunk fp2 off2 o2 n2 :> PrimAstDPO fp1 sym1 sp1)

  (PrimLineHunk fp1 off1 o1 n1, PrimSynquidHole fp2 sym2 h2 sch2 b2)
    | fp1 /= fp2 -> Just (PrimSynquidHole fp2 sym2 h2 sch2 b2 :> PrimLineHunk fp1 off1 o1 n1)
  (PrimSynquidHole fp1 sym1 h1 sch1 b1, PrimLineHunk fp2 off2 o2 n2)
    | fp1 /= fp2 -> Just (PrimLineHunk fp2 off2 o2 n2 :> PrimSynquidHole fp1 sym1 h1 sch1 b1)

  _ -> Nothing

instance Commute PrimPatch where
  commute = commutePrim

cleanMergePrim
  :: (:\/:) PrimPatch PrimPatch wX wY
  -> Maybe ((:/\:) PrimPatch PrimPatch wX wY)
cleanMergePrim (p :\/: q) = do
  q' :> p_inv' <- commute (invert p :> q)
  pure (q' :/\: invert p_inv')

instance CleanMerge PrimPatch where
  cleanMerge = cleanMergePrim
EOF

# 2. Update gargamelle-evidence.cabal
python3 -c '
with open("packages/gargamelle-evidence/gargamelle-evidence.cabal", "r") as f:
    content = f.read()

if "Gargamelle.Evidence.Patch.Prim" not in content:
    content = content.replace("    Gargamelle.Evidence.GitBundle\n", "    Gargamelle.Evidence.GitBundle\n    Gargamelle.Evidence.Patch.Prim\n")

if "darcs-witnesses" not in content:
    content = content.replace("    git-bundle-pure >= 0.1 && < 0.2\n", "    git-bundle-pure >= 0.1 && < 0.2,\n    darcs-witnesses >= 0.1 && < 0.2,\n    darcs-prim-structural >= 0.1 && < 0.2\n")

with open("packages/gargamelle-evidence/gargamelle-evidence.cabal", "w") as f:
    f.write(content)
'

# 3. Update test/Main.hs
cat << 'EOF' > "$EVID_DIR/test/Main.hs"
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
EOF

echo "=== [TP-013B] Completed successfully ==="
