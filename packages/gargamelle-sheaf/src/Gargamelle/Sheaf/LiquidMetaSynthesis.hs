{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gargamelle.Sheaf.LiquidMetaSynthesis
  ( -- * 1. Galois Collision & Dynamic Theory Extension
    GaloisCollision (..)
  , detectGaloisCollision
  , repairGaloisCompleteness
    -- * 2. Cohomological H1 Obstruction Killing via Polytropos Rows
  , SheafEdgeObstruction (..)
  , killH1ObstructionViaRowExtension
  ) where

import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import Data.Text (Text)
import GHC.Generics (Generic)

import Gargamelle.Core.Institution.Liquid
import Gargamelle.Core.Institution.Liquid.Polytropos
import Gargamelle.FOL.LiquidHyperdoctrine

--------------------------------------------------------------------------------
-- 1. Galois Completeness Repair (Dynamic Measure & Qualifier Synthesis)
--------------------------------------------------------------------------------

-- | Witness that the current qualifier basis Q(Gamma) is too coarse:
-- A positive witness model M+ and a negative counterexample M- produce the
-- exact same truth valuation across every qualifier in Q(Gamma).
data GaloisCollision = GaloisCollision
  { colContext   :: Context
  , colPosModel  :: LiquidModel  -- ^ Witness where target property holds
  , colNegModel  :: LiquidModel  -- ^ Counterexample where target property fails
  , colSharedSig :: Set LiquidPred -- ^ Qualifiers true in BOTH M+ and M-
  } deriving stock (Eq, Show, Generic)

-- | Checks whether two models collide under the current qualifier basis.
detectGaloisCollision
  :: Context
  -> QualifierBasis
  -> (LiquidModel -> LiquidPred -> Bool) -- ^ Model evaluator
  -> LiquidModel                          -- ^ Positive model M+
  -> LiquidModel                          -- ^ Negative counterexample M-
  -> Maybe GaloisCollision
detectGaloisCollision ctx basis evalM posM negM =
  let atomicPreds = Set.map qualBody (qbQualifiers basis)
      posVal      = Set.filter (evalM posM) atomicPreds
      negVal      = Set.filter (evalM negM) atomicPreds
  in if posVal == negVal
       then Just $ GaloisCollision ctx posM negM posVal
       else Nothing

-- | When a GaloisCollision occurs, synthesizes a separating measure/qualifier
-- (e.g., via DPO difference or depth-1 catamorphism over M+ vs M-) and returns
-- an Institution Signature Morphism extending LiquidSig in-place!
repairGaloisCompleteness
  :: LiquidSig
  -> GaloisCollision
  -> (GaloisCollision -> IO (Maybe MeasureDecl, Qualifier)) -- ^ Equational separator
  -> IO LiquidSigMorphism
repairGaloisCompleteness sourceSig collision synthesizeSeparator = do
  (mNewMeasure, newQual) <- synthesizeSeparator collision
  let updatedMeasures = case mNewMeasure of
        Nothing -> sigMeasures sourceSig
        Just md -> Map.insert (measureName md) md (sigMeasures sourceSig)
      targetSig = sourceSig
        { sigMeasures   = updatedMeasures
        , sigQualifiers = Set.insert newQual (sigQualifiers sourceSig)
        }
  pure LiquidSigMorphism
    { morphSource  = sourceSig
    , morphTarget  = targetSig
    , morphSortMap = Map.empty
    , morphVarMap  = Map.fromSet id (Map.keysSet (sigEnv sourceSig))
    , morphMeasMap = Map.fromSet id (Map.keysSet (sigMeasures sourceSig))
    }

--------------------------------------------------------------------------------
-- 2. Killing H1 Sheaf Obstructions via Automatic Polytropos Row Extension
--------------------------------------------------------------------------------

-- | Represents a 1-cocycle obstruction on a directed sheaf edge e = (u -> v):
-- Target vertex `v` requires `obstructingQual` (pulled back to edge `e`),
-- which holds internally in source vertex `u` via `sourceWitnessTerm`,
-- but cannot cross edge `e` because `edgeOpenRow` lacks a slot for it.
data SheafEdgeObstruction = SheafEdgeObstruction
  { edgeId             :: SymName
  , sourceStalkSig     :: LiquidSig
  , edgeStalkSig       :: LiquidSig
  , targetStalkSig     :: LiquidSig
  , edgeFunctorSpec    :: FunctorSpec
  , edgeRowVar         :: SymName
    -- ^ Open Polytropos row variable `rho` on edge `e`
  , missingSlotSort    :: LiquidSort
    -- ^ Sort of the witness needed across the boundary
  , sourceWitnessTerm  :: LiquidPred
    -- ^ Term in `u` that computes the witness
  , targetRequiredPred :: SymName -> LiquidPred
    -- ^ Parameterized refinement over the newly projected field `sel_<newLabel>(r)`
  } deriving stock (Generic)

-- | Kills the H1 cocycle obstruction deterministically by instantiating the open
-- Polytropos row variable `rho` on the edge interface with a fresh synthesized
-- field `l_cohom_<edgeId>`, returning the repaired edge signature morphism.
killH1ObstructionViaRowExtension
  :: SheafEdgeObstruction
  -> Either Text (SymName, LiquidSigMorphism)
killH1ObstructionViaRowExtension SheafEdgeObstruction{..} = do
  let auxLabel = "l_cohom_" <> edgeId
      extRow   = OpenRow
        { rowFields = Map.singleton auxLabel missingSlotSort
        , rowTail   = Just (edgeRowVar <> "_tail")
        , rowLacks  = Set.singleton auxLabel
        }
      -- 1. Instantiate the open Polytropos row on the edge stalk via our
      -- Institution Signature Morphism from Gargamelle.Core.Institution.Liquid.Polytropos
      -- instantiateRowTailMorphism :: SymName -> OpenRow -> LiquidSig -> LiquidSig -> LiquidSigMorphism
      targetRowSig = registerRecordRowMeasures
        "Rep"
        extRow
        Nothing
        edgeStalkSig
      baseMorphism = instantiateRowTailMorphism
        edgeRowVar
        extRow
        edgeStalkSig
        targetRowSig
      -- 2. Strengthening the edge stalk with the bridged cocycle invariant:
      -- sel_<auxLabel>(r_edge) == sourceWitnessTerm && targetRequiredPred(sel_<auxLabel>(r_edge))
      bridgedInvariant = PAnd
        [ PRel Eq (PMeasureApp ("sel_" <> auxLabel) (PVar "r_edge")) sourceWitnessTerm
        , targetRequiredPred ("sel_" <> auxLabel)
        ]
      repairedTargetSig = (morphTarget baseMorphism)
        { sigPathCond = bridgedInvariant : sigPathCond (morphTarget baseMorphism)
        }
  Right (auxLabel, baseMorphism { morphTarget = repairedTargetSig })
