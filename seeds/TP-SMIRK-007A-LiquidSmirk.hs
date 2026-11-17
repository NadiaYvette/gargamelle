{-# LANGUAGE OverloadedStrings #-}

{- |
Module      : Gargamelle.Core.Institution.Liquid.Smirk
Description : LiquidHaskell refinement measures & qualifiers for Smirk and dunning-t-digest
Copyright   : (c) Nadia Yvette Chambers, 2026
License     : Apache-2.0

Registers refinement measures and qualifier templates in the Liquid Institution
for step-budgeted execution, evacuable regular expression matching, and
dunning-t-digest centroids.

-- Note [Smirk Liquid Measures and Qualifiers]
1. Fuel & ResourceBudget conservation:
   - stepsConsumed >= 0
   - fuelRemaining >= 0
   - stepsConsumed + fuelRemaining <= grantedFuel
   - effectiveFuel <= min(reqFuel, defaultFuel)

2. Evacuable non-empty matching:
   - not (isNullableAST(r)) => matchLength(res) >= 1
   - not (isNullableAST(r)) => remainingInputLen < prevInputLen

3. dunning-t-digest invariants:
   - centroidCount(d) <= maxCentroids(delta)
   - centroidMean(i) <= centroidMean(i + 1)
   - centroidWeight(i) > 0
-}
module Gargamelle.Core.Institution.Liquid.Smirk
  ( -- * Measure Registration
    registerFuelBudgetMeasures
  , registerEvacuableMeasures
  , registerTDigestMeasures
  , registerAllSmirkMeasures

    -- * Qualifiers
  , fuelBudgetQualifiers
  , evacuableQualifiers
  , tDigestQualifiers
  , allSmirkQualifiers
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Data.Set (Set)

import Gargamelle.Core.Institution.Liquid

{-@
measure stepsConsumed :: a -> Int
measure fuelRemaining :: a -> Int
measure grantedFuel :: a -> Int
measure effectiveFuel :: a -> Int
measure reqFuel :: a -> Int
measure defaultFuel :: a -> Int

measure isNullableAST :: a -> Bool
measure matchLength :: a -> Int
measure remainingInputLen :: a -> Int
measure prevInputLen :: a -> Int

measure centroidCount :: a -> Int
measure maxCentroids :: a -> Int
measure centroidMean :: Int -> Int
measure centroidWeight :: Int -> Int

invariant {v: a | stepsConsumed v >= 0 && fuelRemaining v >= 0 && stepsConsumed v + fuelRemaining v <= grantedFuel v}
invariant {v: a | centroidCount v <= maxCentroids v}
@-}

-- -----------------------------------------------------------------------------
-- 1. Fuel & ResourceBudget Conservation Measures & Qualifiers
-- -----------------------------------------------------------------------------

-- | Qualifiers enforcing Fuel and ResourceBudget conservation laws.
fuelBudgetQualifiers :: Set Qualifier
fuelBudgetQualifiers = Set.fromList
  [ Qualifier "fuel_steps_nonneg" [("f", SortADT "Fuel" [])]
      (PRel Ge (PMeasureApp "stepsConsumed" (PVar "f")) (PIntLit 0))

  , Qualifier "fuel_remaining_nonneg" [("f", SortADT "Fuel" [])]
      (PRel Ge (PMeasureApp "fuelRemaining" (PVar "f")) (PIntLit 0))

  , Qualifier "fuel_conservation" [("f", SortADT "Fuel" [])]
      (PRel Le
        (PBinOp Add (PMeasureApp "stepsConsumed" (PVar "f")) (PMeasureApp "fuelRemaining" (PVar "f")))
        (PMeasureApp "grantedFuel" (PVar "f")))

  , Qualifier "fuel_effective_clamped_req" [("f", SortADT "Fuel" [])]
      (PRel Le
        (PMeasureApp "effectiveFuel" (PVar "f"))
        (PMeasureApp "reqFuel" (PVar "f")))

  , Qualifier "fuel_effective_clamped_default" [("f", SortADT "Fuel" [])]
      (PRel Le
        (PMeasureApp "effectiveFuel" (PVar "f"))
        (PMeasureApp "defaultFuel" (PVar "f")))
  ]

-- | Register Fuel and ResourceBudget measures into a LiquidSig.
registerFuelBudgetMeasures :: LiquidSig -> LiquidSig
registerFuelBudgetMeasures sig =
  let sortFuel = SortADT "Fuel" []
      measures = Map.fromList
        [ ("stepsConsumed", MeasureDecl "stepsConsumed" sortFuel SortInt False)
        , ("fuelRemaining", MeasureDecl "fuelRemaining" sortFuel SortInt True)
        , ("grantedFuel",   MeasureDecl "grantedFuel"   sortFuel SortInt False)
        , ("effectiveFuel", MeasureDecl "effectiveFuel" sortFuel SortInt False)
        , ("reqFuel",       MeasureDecl "reqFuel"       sortFuel SortInt False)
        , ("defaultFuel",   MeasureDecl "defaultFuel"   sortFuel SortInt False)
        ]
  in sig
      { sigSorts      = Set.insert "Fuel" (sigSorts sig)
      , sigMeasures   = Map.union measures (sigMeasures sig)
      , sigQualifiers = Set.union fuelBudgetQualifiers (sigQualifiers sig)
      }

-- -----------------------------------------------------------------------------
-- 2. Evacuable Non-Empty Match Measures & Qualifiers
-- -----------------------------------------------------------------------------

-- | Qualifiers ensuring progress and well-founded termination for non-nullable regexes.
evacuableQualifiers :: Set Qualifier
evacuableQualifiers = Set.fromList
  [ Qualifier "evac_nonnull_progress" [("r", SortADT "AST" []), ("res", SortADT "MatchResult" [])]
      (PImplies
        (PRel Eq (PMeasureApp "isNullableAST" (PVar "r")) PFalse)
        (PRel Ge (PMeasureApp "matchLength" (PVar "res")) (PIntLit 1)))

  , Qualifier "evac_nonnull_termination" [("r", SortADT "AST" []), ("st", SortADT "ParseState" [])]
      (PImplies
        (PRel Eq (PMeasureApp "isNullableAST" (PVar "r")) PFalse)
        (PRel Lt (PMeasureApp "remainingInputLen" (PVar "st")) (PMeasureApp "prevInputLen" (PVar "st"))))
  ]

-- | Register Evacuable matching measures into a LiquidSig.
registerEvacuableMeasures :: LiquidSig -> LiquidSig
registerEvacuableMeasures sig =
  let sortAST    = SortADT "AST" []
      sortResult = SortADT "MatchResult" []
      sortState  = SortADT "ParseState" []
      measures = Map.fromList
        [ ("isNullableAST",     MeasureDecl "isNullableAST"     sortAST    SortBool False)
        , ("matchLength",       MeasureDecl "matchLength"       sortResult SortInt  False)
        , ("remainingInputLen", MeasureDecl "remainingInputLen" sortState  SortInt  True)
        , ("prevInputLen",      MeasureDecl "prevInputLen"      sortState  SortInt  False)
        ]
  in sig
      { sigSorts      = Set.union (Set.fromList ["AST", "MatchResult", "ParseState"]) (sigSorts sig)
      , sigMeasures   = Map.union measures (sigMeasures sig)
      , sigQualifiers = Set.union evacuableQualifiers (sigQualifiers sig)
      }

-- -----------------------------------------------------------------------------
-- 3. Dunning t-Digest Invariants
-- -----------------------------------------------------------------------------

-- | Qualifiers enforcing t-digest centroid capacity, monotonicity, and positive weights.
tDigestQualifiers :: Set Qualifier
tDigestQualifiers = Set.fromList
  [ Qualifier "tdigest_centroid_count_bounded" [("d", SortADT "TDigest" [])]
      (PRel Le
        (PMeasureApp "centroidCount" (PVar "d"))
        (PMeasureApp "maxCentroids" (PVar "d")))

  , Qualifier "tdigest_monotonic_means" [("i", SortInt)]
      (PRel Le
        (PMeasureApp "centroidMean" (PVar "i"))
        (PMeasureApp "centroidMean" (PBinOp Add (PVar "i") (PIntLit 1))))

  , Qualifier "tdigest_positive_weight" [("i", SortInt)]
      (PRel Gt
        (PMeasureApp "centroidWeight" (PVar "i"))
        (PIntLit 0))
  ]

-- | Register Dunning t-digest measures into a LiquidSig.
registerTDigestMeasures :: LiquidSig -> LiquidSig
registerTDigestMeasures sig =
  let sortDigest = SortADT "TDigest" []
      measures = Map.fromList
        [ ("centroidCount",  MeasureDecl "centroidCount"  sortDigest SortInt False)
        , ("maxCentroids",   MeasureDecl "maxCentroids"   sortDigest SortInt False)
        , ("centroidMean",   MeasureDecl "centroidMean"   SortInt    SortInt False)
        , ("centroidWeight", MeasureDecl "centroidWeight" SortInt    SortInt False)
        ]
  in sig
      { sigSorts      = Set.insert "TDigest" (sigSorts sig)
      , sigMeasures   = Map.union measures (sigMeasures sig)
      , sigQualifiers = Set.union tDigestQualifiers (sigQualifiers sig)
      }

-- -----------------------------------------------------------------------------
-- 4. Combined Registration
-- -----------------------------------------------------------------------------

-- | Combined set of all Smirk and t-digest qualifiers.
allSmirkQualifiers :: Set Qualifier
allSmirkQualifiers = Set.unions [fuelBudgetQualifiers, evacuableQualifiers, tDigestQualifiers]

-- | Register all Fuel, Evacuable, and t-Digest measures into a signature.
registerAllSmirkMeasures :: LiquidSig -> LiquidSig
registerAllSmirkMeasures =
  registerTDigestMeasures . registerEvacuableMeasures . registerFuelBudgetMeasures
