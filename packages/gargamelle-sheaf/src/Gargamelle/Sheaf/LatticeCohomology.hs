{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

{-# OPTIONS_GHC -Wno-redundant-constraints #-}

module Gargamelle.Sheaf.LatticeCohomology
  ( -- * Sheaf Identifiers and Structure
    VertexId
  , EdgeId
  , SheafEdgeSpec (..)
  , SheafVertexSpec (..)
  , LiquidCellularSheaf (..)
    -- * Cohomological Conflict Classification and Results
  , H1ConflictClassification (..)
  , H1QualifierConflict (..)
  , CohomologyResult (..)
    -- * Sheaf Cohomology Solver
  , solveSheafCohomology
    -- * Morphism translation helper
  , translatePredMorphism
  ) where

import Control.Monad (filterM)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import GHC.Generics (Generic)

import Gargamelle.Core.Institution.Liquid
import Gargamelle.FOL.LiquidHyperdoctrine
import Gargamelle.Sheaf.LiquidMetaSynthesis
  ( SheafEdgeObstruction (..)
  , killH1ObstructionViaRowExtension
  )

-- | Vertex identifier in the liquid cellular sheaf complex.
type VertexId = SymName

-- | Edge identifier in the liquid cellular sheaf complex.
type EdgeId = SymName

-- | Specification of a 1-cell (directed edge) in the sheaf complex.
data SheafEdgeSpec = SheafEdgeSpec
  { seEdgeId      :: EdgeId
  , seSourceVert  :: VertexId
  , seTargetVert  :: VertexId
  , seEdgeSig     :: LiquidSig
  , seEdgeBasis   :: QualifierBasis
  , seRestrictSrc :: LiquidSigMorphism
  , seRestrictTgt :: LiquidSigMorphism
  } deriving stock (Eq, Show, Generic)

-- | Specification of a 0-cell (vertex stalk) in the sheaf complex.
data SheafVertexSpec = SheafVertexSpec
  { svVertexId          :: VertexId
  , svSig               :: LiquidSig
  , svContext           :: Context
  , svBasis             :: QualifierBasis
  , svLocalGuarantee    :: FOLFormula
  , svLocalRequirement  :: FOLFormula
  } deriving stock (Eq, Show, Generic)

-- | Cellular sheaf over a 1D graph complex fibered over liquid institutions.
data LiquidCellularSheaf = LiquidCellularSheaf
  { sheafVertices :: Map VertexId SheafVertexSpec
  , sheafEdges    :: Map EdgeId SheafEdgeSpec
  } deriving stock (Eq, Show, Generic)

-- | Classification of an H^1 obstruction on an interface edge:
-- Either autonomously repairable via open Polytropos row tail extension,
-- or an architectural contradiction requiring high-level planner escalation.
data H1ConflictClassification
  = AutoRowRepairable SymName LiquidSigMorphism
  | ArchitecturalContradiction [LiquidPred]
  deriving stock (Eq, Show, Generic)

-- | Detailed diagnostic record of an H^1 qualifier conflict along an edge.
data H1QualifierConflict = H1QualifierConflict
  { conflictEdgeId       :: EdgeId
  , conflictSource       :: VertexId
  , conflictTarget       :: VertexId
  , conflictGuaranteed   :: QualifierConj
  , conflictRequired     :: QualifierConj
  , conflictMissingQuals :: Set LiquidPred
  , conflictResolution   :: H1ConflictClassification
  } deriving stock (Eq, Show, Generic)

-- | Cohomological verification outcome:
-- Either a globally consistent section H^0 (vanishing coboundary),
-- or a list of localized 1-cocycle obstructions H^1.
data CohomologyResult
  = GlobalSectionH0 (Map EdgeId QualifierConj)
  | ObstructionH1 [H1QualifierConflict]
  deriving stock (Eq, Show, Generic)

-- | Translate a LiquidPred under a LiquidSigMorphism (variable, measure, and sort renaming).
translatePredMorphism :: LiquidSigMorphism -> LiquidPred -> LiquidPred
translatePredMorphism sigma = go
  where
    renameV v = Map.findWithDefault v v (morphVarMap sigma)
    renameM m = Map.findWithDefault m m (morphMeasMap sigma)
    go = \case
      PTrue             -> PTrue
      PFalse            -> PFalse
      PVar v            -> PVar (renameV v)
      PIntLit i         -> PIntLit i
      PEmptySet s       -> PEmptySet s
      PMeasureApp m e   -> PMeasureApp (renameM m) (go e)
      PFieldProj l e    -> PFieldProj l (go e)
      PVariantTag t e   -> PVariantTag t (go e)
      PBinOp op l r     -> PBinOp op (go l) (go r)
      PRel op l r       -> PRel op (go l) (go r)
      PNot e            -> PNot (go e)
      PAnd es           -> PAnd (map go es)
      POr es            -> POr (map go es)
      PImplies l r      -> PImplies (go l) (go r)
      PIff l r          -> PIff (go l) (go r)
      PLiquidHole h vs  -> PLiquidHole h (map renameV vs)

-- | Compute cellular sheaf cohomology for a liquid cellular sheaf.
--
-- For each edge e = (u -> v):
-- 1. Evaluates source vertex guarantee via strong Galois consequence (left adjoint)
--    and restricts / pushes forward to edge stalk via seRestrictSrc.
-- 2. Evaluates target vertex requirement via weak Galois implicant (right adjoint)
--    and restricts / pulls back to edge stalk via seRestrictTgt.
-- 3. Entailment check on edge stalk: does the guaranteed edge contract entail the required contract?
--    If missing qualifiers exist:
--      Check if the user-supplied classifier identifies a SheafEdgeObstruction
--      that can be killed via Polytropos row tail extension (AutoRowRepairable).
--      Otherwise, classify as ArchitecturalContradiction.
-- 4. If all edges succeed, returns GlobalSectionH0 with the glued edge contracts.
--    Otherwise, returns ObstructionH1 detailing all failing edge conflicts.
solveSheafCohomology
  :: forall h. (Hyperdoctrine h, LiquidSubHyperdoctrine h)
  => h
  -> LiquidCellularSheaf
  -> (EdgeId -> LiquidPred -> Maybe SheafEdgeObstruction)
  -> IO CohomologyResult
solveSheafCohomology _ LiquidCellularSheaf{..} classifyObstruction = do
  edgeResults <- mapM checkEdge (Map.toList sheafEdges)
  let conflicts = [ c | Left c <- edgeResults ]
  if null conflicts
    then
      let globalSec = Map.fromList [ (eId, qc) | Right (eId, qc) <- edgeResults ]
      in pure (GlobalSectionH0 globalSec)
    else pure (ObstructionH1 conflicts)
  where
    checkEdge :: (EdgeId, SheafEdgeSpec) -> IO (Either H1QualifierConflict (EdgeId, QualifierConj))
    checkEdge (eId, SheafEdgeSpec{..}) = do
      case (Map.lookup seSourceVert sheafVertices, Map.lookup seTargetVert sheafVertices) of
        (Nothing, _) ->
          pure $ Left H1QualifierConflict
            { conflictEdgeId       = eId
            , conflictSource       = seSourceVert
            , conflictTarget       = seTargetVert
            , conflictGuaranteed   = QualifierConj Set.empty
            , conflictRequired     = QualifierConj Set.empty
            , conflictMissingQuals = Set.empty
            , conflictResolution   = ArchitecturalContradiction []
            }
        (_, Nothing) ->
          pure $ Left H1QualifierConflict
            { conflictEdgeId       = eId
            , conflictSource       = seSourceVert
            , conflictTarget       = seTargetVert
            , conflictGuaranteed   = QualifierConj Set.empty
            , conflictRequired     = QualifierConj Set.empty
            , conflictMissingQuals = Set.empty
            , conflictResolution   = ArchitecturalContradiction []
            }
        (Just srcSpec, Just tgtSpec) -> do
          -- 1. Compute strong Galois consequence of source guarantee in src context
          srcStrong <- strongGaloisConsequence @h
            (svContext srcSpec)
            (svBasis srcSpec)
            (svLocalGuarantee srcSpec)

          -- Push forward / restrict source qualifiers to the edge interface
          let srcEdgePreds = Set.map (translatePredMorphism seRestrictSrc) (qcConjuncts srcStrong)
              srcEdgeConj  = QualifierConj srcEdgePreds

          -- 2. Compute weak Galois implicant or requirement of target in tgt context
          mTgtWeak <- weakGaloisImplicant @h
            (svContext tgtSpec)
            (svBasis tgtSpec)
            (svLocalRequirement tgtSpec)

          tgtWeak <- case mTgtWeak of
            Just q  -> pure q
            Nothing -> strongGaloisConsequence @h
              (svContext tgtSpec)
              (svBasis tgtSpec)
              (svLocalRequirement tgtSpec)

          -- Pull back / restrict target requirement qualifiers to the edge interface
          let tgtEdgePreds = Set.map (translatePredMorphism seRestrictTgt) (qcConjuncts tgtWeak)
              tgtEdgeConj  = QualifierConj tgtEdgePreds

          -- 3. Check which target required predicates are NOT entailed by the source guarantee
          -- Context on edge interface: variables occurring in edge environment / context
          let edgeVarCtx = Map.map (\case RBScalar (RBase _ s _) -> s; _ -> SortInt) (sigEnv seEdgeSig)
              -- In addition, include any free variables appearing in guarantee / requirement
              collectVars = \case
                PVar v -> Set.singleton v
                PMeasureApp _ e -> collectVars e
                PFieldProj _ e -> collectVars e
                PVariantTag _ e -> collectVars e
                PBinOp _ l r -> collectVars l `Set.union` collectVars r
                PRel _ l r -> collectVars l `Set.union` collectVars r
                PNot e -> collectVars e
                PAnd es -> Set.unions (map collectVars es)
                POr es -> Set.unions (map collectVars es)
                PImplies l r -> collectVars l `Set.union` collectVars r
                PIff l r -> collectVars l `Set.union` collectVars r
                _ -> Set.empty
              allPredVars = Set.unions (map collectVars (Set.toList srcEdgePreds ++ Set.toList tgtEdgePreds))
              mergedCtx = Map.union edgeVarCtx (Map.fromSet (const SortInt) allPredVars)
              edgeCtx = Context mergedCtx
              guaranteeFOL = embedQualifier @h srcEdgeConj

          missingPredsList <- filterM
            (\p -> not <$> entails @h edgeCtx guaranteeFOL (FAtom p))
            (Set.toList tgtEdgePreds)

          let missingSet = Set.fromList missingPredsList

          if Set.null missingSet
            then pure $ Right (eId, srcEdgeConj)
            else do
              -- 4. Classify obstruction
              resolution <- classifyConflict eId missingPredsList
              pure $ Left H1QualifierConflict
                { conflictEdgeId       = eId
                , conflictSource       = seSourceVert
                , conflictTarget       = seTargetVert
                , conflictGuaranteed   = srcEdgeConj
                , conflictRequired     = tgtEdgeConj
                , conflictMissingQuals = missingSet
                , conflictResolution   = resolution
                }

    classifyConflict :: EdgeId -> [LiquidPred] -> IO H1ConflictClassification
    classifyConflict eId missingList = do
      -- Inspect missing predicates for potential row repair
      let tryRepair [] = pure (ArchitecturalContradiction missingList)
          tryRepair (p : rest) = case classifyObstruction eId p of
            Nothing -> tryRepair rest
            Just obsSpec -> case killH1ObstructionViaRowExtension obsSpec of
              Left _err -> tryRepair rest
              Right (auxLabel, morph) -> pure (AutoRowRepairable auxLabel morph)
      tryRepair missingList
