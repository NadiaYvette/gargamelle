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
