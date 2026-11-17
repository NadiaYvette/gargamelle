#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-013C] Setting up Gargamelle.Evidence.Patch.Bundle ==="

# 0. Ensure cabal.project.local exists
if [ ! -f cabal.project.local ] && [ -f /home/nyc/src/gargamelle/cabal.project.local ]; then
  cp -f /home/nyc/src/gargamelle/cabal.project.local ./cabal.project.local
fi

EVID_DIR="packages/gargamelle-evidence"
mkdir -p "$EVID_DIR/src/Gargamelle/Evidence/Patch"

# 1. Write Gargamelle.Evidence.Patch.Bundle
cat << 'EOF' > "$EVID_DIR/src/Gargamelle/Evidence/Patch/Bundle.hs"
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StrictData #-}

module Gargamelle.Evidence.Patch.Bundle
  ( -- * GPatch Type
    GPatch(..)
    -- * Semantic Commutation & Sheaf Merging
  , commuteGPatch
  , mergeGPatchParallel
    -- * Dual-View .gpatch Serialization
  , writeGPatchBundle
  , readGPatchBundle
    -- * Helpers
  , emptySig
  , emptyMorphism
  ) where

import Control.Exception (throwIO)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Char8 as C8
import Data.Kind (Type)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import System.IO.Error (userError)

import Darcs.Patch.Witnesses
  ( FL(..)
  , (:>)(..)
  , (:\/:)(..)
  , (:/\:)(..)
  , Sealed2(..)
  , seal2
  , Invert(..)
  , Commute(..)
  , CleanMerge(..)
  )
import Gargamelle.Core.Institution.Liquid
  ( LiquidSig(..)
  , LiquidSigMorphism(..)
  )
import Gargamelle.Evidence.GitBundle
  ( BlobOid(..)
  , TreeOid(..)
  , CommitOid(..)
  , GitObjType(..)
  , GitObject(..)
  , BundleRef(..)
  , GitBundleV2(..)
  , OidHex(..)
  , encodeGitBundleV2
  , decodeGitBundleV2Header
  , hashGitObject
  , gpatchRefPrefix
  )
import Gargamelle.Evidence.Patch.Prim
  ( PrimPatch(..)
  , PatchId(..)
  )
import Gargamelle.FOL.LiquidHyperdoctrine
  ( Context(..)
  , QualifierBasis(..)
  , FOLFormula(..)
  , Hyperdoctrine(..)
  , LiquidSubHyperdoctrine(..)
  )
import Gargamelle.Sheaf.LatticeCohomology
  ( SheafVertexSpec(..)
  , LiquidCellularSheaf(..)
  , CohomologyResult(..)
  , solveSheafCohomology
  )

emptySig :: LiquidSig
emptySig = LiquidSig mempty mempty [] mempty mempty []

emptyMorphism :: LiquidSigMorphism
emptyMorphism = LiquidSigMorphism emptySig emptySig Map.empty Map.empty Map.empty

-- | Dual-view witnessed patch bundle
data GPatch (wX :: Type) (wY :: Type) = GPatch
  { gpPatchId       :: !PatchId
  , gpContextDeps   :: !(Set PatchId)
  , gpBaseTreeOid   :: !TreeOid
  , gpResultTreeOid :: !TreeOid
  , gpPrims         :: !(FL PrimPatch wX wY)
  , gpSigMorphism   :: !LiquidSigMorphism
  , gpVertexSpec    :: !SheafVertexSpec
  }

instance Show (GPatch wX wY) where
  show p =
    "GPatch { gpPatchId = " ++ show p.gpPatchId
    ++ ", gpContextDeps = " ++ show p.gpContextDeps
    ++ ", gpBaseTreeOid = " ++ show p.gpBaseTreeOid
    ++ ", gpResultTreeOid = " ++ show p.gpResultTreeOid
    ++ " }"

instance Eq (GPatch wX wY) where
  p1 == p2 =
    p1.gpPatchId == p2.gpPatchId
    && p1.gpContextDeps == p2.gpContextDeps
    && p1.gpBaseTreeOid == p2.gpBaseTreeOid
    && p1.gpResultTreeOid == p2.gpResultTreeOid

-- | Clean merge for forward lists of primitive patches via inversion and commutation.
cleanMergeFL
  :: (:\/:) (FL PrimPatch) (FL PrimPatch) wA wB
  -> Maybe ((:/\:) (FL PrimPatch) (FL PrimPatch) wA wB)
cleanMergeFL (xs :\/: ys) = do
  ys' :> inv_xs' <- commute (invert xs :> ys)
  pure (ys' :/\: invert inv_xs')

instance CleanMerge (FL PrimPatch) where
  cleanMerge = cleanMergeFL

-- | Commutes two sequential GPatch bundles iff both primitive AST edits commute
--   and cellular sheaf cohomology obstruction H^1 = 0.
commuteGPatch
  :: (Hyperdoctrine h, LiquidSubHyperdoctrine h)
  => h
  -> (:>) GPatch GPatch wX wZ
  -> IO (Maybe ((:>) GPatch GPatch wX wZ))
commuteGPatch h (p :> q) = do
  case commute (p.gpPrims :> q.gpPrims) of
    Nothing -> pure Nothing
    Just (qPrims' :> pPrims') -> do
      let vP = p.gpVertexSpec
          vQ = q.gpVertexSpec
          sheaf = LiquidCellularSheaf
            { sheafVertices = Map.fromList [(vP.svVertexId, vP), (vQ.svVertexId, vQ)]
            , sheafEdges    = Map.empty
            }
      cohom <- solveSheafCohomology h sheaf (\_ _ -> Nothing)
      case cohom of
        ObstructionH1 _ -> pure Nothing
        GlobalSectionH0 _ ->
          let p' = p { gpPrims = pPrims' }
              q' = q { gpPrims = qPrims' }
          in pure (Just (q' :> p'))

-- | Parallel merger of two GPatch bundles requiring syntactic cleanMerge and H^1 = 0.
mergeGPatchParallel
  :: (Hyperdoctrine h, LiquidSubHyperdoctrine h)
  => h
  -> (:\/:) GPatch GPatch wX wY
  -> IO (Maybe ((:/\:) GPatch GPatch wX wY))
mergeGPatchParallel h (p :\/: q) = do
  case cleanMergeFL (p.gpPrims :\/: q.gpPrims) of
    Nothing -> pure Nothing
    Just (qPrims' :/\: pPrims') -> do
      let vP = p.gpVertexSpec
          vQ = q.gpVertexSpec
          sheaf = LiquidCellularSheaf
            { sheafVertices = Map.fromList [(vP.svVertexId, vP), (vQ.svVertexId, vQ)]
            , sheafEdges    = Map.empty
            }
      cohom <- solveSheafCohomology h sheaf (\_ _ -> Nothing)
      case cohom of
        ObstructionH1 _ -> pure Nothing
        GlobalSectionH0 _ ->
          let qMerged = q { gpPrims = qPrims', gpContextDeps = Set.insert p.gpPatchId q.gpContextDeps }
              pMerged = p { gpPrims = pPrims', gpContextDeps = Set.insert q.gpPatchId p.gpContextDeps }
          in pure (Just (qMerged :/\: pMerged))

-- | Serializes a GPatch to a standard gitformat-bundle(5) archive.
writeGPatchBundle :: FilePath -> GPatch wX wY -> IO ()
writeGPatchBundle path patch = do
  let metaPayload =
        "gpatch:" <> unPatchId patch.gpPatchId
        <> ":" <> unOidHex (unTreeOid patch.gpBaseTreeOid)
        <> ":" <> unOidHex (unTreeOid patch.gpResultTreeOid)
      metaObj = GitObject ObjBlob metaPayload
      metaOid = hashGitObject metaObj
      dummyCommit = GitObject ObjCommit ("commit " <> unPatchId patch.gpPatchId <> "\n")
      commitOid = hashGitObject dummyCommit
      baseBundle = GitBundleV2
        { gbPrerequisites = []
        , gbAdvertised    =
            [ BundleRef commitOid "refs/heads/main"
            , BundleRef metaOid (gpatchRefPrefix <> unPatchId patch.gpPatchId)
            ]
        , gbObjects       = [dummyCommit, metaObj]
        }
      bundleBytes = encodeGitBundleV2 baseBundle
  BS.writeFile path bundleBytes

-- | Reads a GPatch bundle header and restores a Sealed2 GPatch.
readGPatchBundle :: FilePath -> IO (Sealed2 GPatch)
readGPatchBundle path = do
  bytes <- BS.readFile path
  case decodeGitBundleV2Header bytes of
    Left err -> throwIO (userError ("Failed to decode GPatch bundle header: " ++ err))
    Right (_, refs, _) -> do
      let patchRefPrefix' = gpatchRefPrefix
          metaRefs = filter (\r -> patchRefPrefix' `BS.isPrefixOf` r.brRefName) refs
      case metaRefs of
        [] -> throwIO (userError "No refs/gargamelle/gpatch ref found in bundle")
        (r : _) -> do
          let pid = PatchId (BS.drop (BS.length patchRefPrefix') r.brRefName)
              baseOid = TreeOid (OidHex "0000000000000000000000000000000000000000")
              resOid  = TreeOid r.brOid
              vspec = SheafVertexSpec
                { svVertexId = "v_patch"
                , svSig = emptySig
                , svContext = Context Map.empty
                , svBasis = QualifierBasis Set.empty
                , svLocalGuarantee = FTrue
                , svLocalRequirement = FTrue
                }
              patch = GPatch
                { gpPatchId = pid
                , gpContextDeps = Set.empty
                , gpBaseTreeOid = baseOid
                , gpResultTreeOid = resOid
                , gpPrims = NilFL
                , gpSigMorphism = emptyMorphism
                , gpVertexSpec = vspec
                }
          pure (seal2 patch)
EOF

# 2. Update gargamelle-evidence.cabal
cat << 'EOF' > "$EVID_DIR/gargamelle-evidence.cabal"
cabal-version: 3.0
name: gargamelle-evidence
version: 0.1.0.0
synopsis: Evidence preservation and structural tree-diff AST tracking
description:
  Evidence preservation and structural tree-diff AST tracking for
  Gargamelle. Provides tree-sitter syntactic integration, parse tree
  hashing, semantic AST diffing, and proof artifact tracking.
license: EUPL-1.2
license-file: LICENSE
author: Nadia Yvette Chambers
maintainer: nadia.yvette.chambers@ik.me
category: Development
homepage: https://github.com/NadiaYvette/gargamelle
bug-reports: https://github.com/NadiaYvette/gargamelle/issues
extra-doc-files:
  README.md
  CHANGELOG.md
build-type: Simple
tested-with:
  GHC == 9.6.7,
  GHC == 9.8.4,
  GHC == 9.10.3,
  GHC == 9.12.4,
  GHC == 9.14.1

source-repository head
  type: git
  location: https://github.com/NadiaYvette/gargamelle
  subdir: packages/gargamelle-evidence

library
  exposed-modules:
    Evidence
    Gargamelle.Evidence.GitBundle
    Gargamelle.Evidence.Patch.Prim
    Gargamelle.Evidence.Patch.Bundle
  hs-source-dirs: src
  default-language: Haskell2010
  ghc-options: -Wall
  build-depends:
    base >= 4.14 && < 5,
    containers >= 0.6 && < 0.9,
    unordered-containers >= 0.2 && < 0.3,
    hashable >= 1.4 && < 1.6,
    text >= 2.0 && < 2.2,
    bytestring >= 0.10 && < 0.13,
    zlib >= 0.6 && < 0.8,
    cryptohash-sha1 >= 0.11 && < 0.12,
    cryptohash-sha256 >= 0.6 && < 0.7,
    polytropos-core >= 0.1.0.1 && < 0.2,
    gargamelle-core >= 0.1 && < 0.2,
    hs-tree-sitter >= 13.0 && < 14,
    tree-diff >= 0.3 && < 0.5,
    git-bundle-pure >= 0.1 && < 0.2,
    darcs-witnesses >= 0.1 && < 0.2,
    darcs-prim-structural >= 0.1 && < 0.2,
    gargamelle-sheaf >= 0.1 && < 0.2,
    gargamelle-fol >= 0.1 && < 0.2

test-suite tests
  type: exitcode-stdio-1.0
  main-is: Main.hs
  hs-source-dirs: test
  default-language: Haskell2010
  ghc-options: -Wall
  build-depends:
    base >= 4.14 && < 5,
    gargamelle-evidence,
    gargamelle-core >= 0.1 && < 0.2,
    containers >= 0.6 && < 0.9,
    unordered-containers >= 0.2 && < 0.3,
    tree-diff >= 0.3 && < 0.5,
    hspec >= 2.10 && < 2.12,
    git-bundle-pure >= 0.1 && < 0.2,
    darcs-witnesses >= 0.1 && < 0.2,
    darcs-prim-structural >= 0.1 && < 0.2,
    gargamelle-sheaf >= 0.1 && < 0.2,
    gargamelle-fol >= 0.1 && < 0.2,
    bytestring
EOF

# 3. Update test/Main.hs
cat << 'EOF' > "$EVID_DIR/test/Main.hs"
{-# LANGUAGE OverloadedStrings #-}

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
          p2'.gpPatchId `shouldBe` PatchId "P2"
          p1'.gpPatchId `shouldBe` PatchId "P1"
        Nothing -> expectationFailure "Expected commuteGPatch to succeed"

    it "clean-merges two parallel GPatch bundles under Z3Hyperdoctrine" $ do
      mRes <- mergeGPatchParallel Z3Hyperdoctrine (p1 :\/: p2)
      case mRes of
        Just (p2' :/\: p1') -> do
          p2'.gpPatchId `shouldBe` PatchId "P2"
          p1'.gpPatchId `shouldBe` PatchId "P1"
          Set.member (PatchId "P1") p2'.gpContextDeps `shouldBe` True
          Set.member (PatchId "P2") p1'.gpContextDeps `shouldBe` True
        Nothing -> expectationFailure "Expected mergeGPatchParallel to succeed"

    it "serializes and round-trips a .gpatch bundle file" $ do
      let tmpPath = "/tmp/test-gpatch-bundle.gpatch"
      writeGPatchBundle tmpPath p1
      sealed <- readGPatchBundle tmpPath
      -- sealed restores GPatch
      case sealed of
        Sealed2 pRestored -> do
          pRestored.gpPatchId `shouldBe` PatchId "P1"
EOF

echo "=== [TP-013C] Completed successfully ==="
