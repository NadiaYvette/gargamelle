{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}

module Gargamelle.Sheaf.Cohomology
  ( -- * Coboundary Operator
    coboundary
  , isHarmonicCochain
    -- * Cohomological Invariants
  , CohomologyResult(..)
  , computeCohomology
  , GlobalSection(..)
  , globalSection
    -- * Homological Fault Localization
  , InterfaceObstruction(..)
  , locateObstructions
    -- * Model Amalgamation Bridge
  , verifyModelAmalgamation
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Proarrow.Core (type (~>))
import Gargamelle.Core.Institution (Sig, Mod)
import Gargamelle.Core.Weaving (PushoutWeaving(..))
import Gargamelle.Sheaf.Complex (CellComplex(..))
import Gargamelle.Sheaf.Diffusion (CellularSheaf(..), Cochain0(..), Cochain1(..))

-- | Sheaf Coboundary Operator \delta^0 : C^0(G; F) -> C^1(G; F).
-- Computes the boundary discrepancy pair (\rho_{u \trianglelefteq e}(x_u), \rho_{v \trianglelefteq e}(x_v))
-- for every 1-cell e = (u, v) in the complex.
-- Returns the 1-cochain of discrepancies and a boolean indicating whether the cochain is harmonic (no discrepancies).
coboundary
  :: forall vId eId stalk edgeStalk.
     (Ord vId, Eq edgeStalk)
  => CellComplex vId eId
  -> CellularSheaf vId eId stalk edgeStalk
  -> Cochain0 vId stalk
  -> (Cochain1 eId (edgeStalk, edgeStalk), Bool)
coboundary complex sheaf (Cochain0 vMap) =
  let edgeDiffs = Map.mapWithKey computeEdge (edges complex)
      harmonic = all (uncurry (==)) edgeDiffs
  in (Cochain1 edgeDiffs, harmonic)
  where
    computeEdge eId (u, v) =
      let stU = Map.findWithDefault (error "coboundary: source vertex missing") u vMap
          stV = Map.findWithDefault (error "coboundary: target vertex missing") v vMap
      in (restrictSrc sheaf eId stU, restrictTgt sheaf eId stV)

-- | Predicate checking if a 0-cochain satisfies the sheaf gluing condition (zero coboundary).
isHarmonicCochain
  :: (Ord vId, Eq edgeStalk)
  => CellComplex vId eId
  -> CellularSheaf vId eId stalk edgeStalk
  -> Cochain0 vId stalk
  -> Bool
isHarmonicCochain complex sheaf = snd . coboundary complex sheaf

-- | Result of cohomology computation at dimension 0 and 1.
data CohomologyResult eId edgeStalk
  = HarmonicSection
  | ObstructionMap (Map eId (edgeStalk, edgeStalk))
  deriving (Eq, Show)

-- | Compute cohomology: returns 'HarmonicSection' if all boundary restrictions agree,
-- or 'ObstructionMap' detailing the non-vanishing cocycles.
computeCohomology
  :: (Ord vId, Eq edgeStalk)
  => CellComplex vId eId
  -> CellularSheaf vId eId stalk edgeStalk
  -> Cochain0 vId stalk
  -> CohomologyResult eId edgeStalk
computeCohomology complex sheaf c0 =
  let (Cochain1 diffs, harmonic) = coboundary complex sheaf c0
  in if harmonic
       then HarmonicSection
       else ObstructionMap (Map.filter (uncurry (/=)) diffs)

-- | A verified global section H^0(G; F) = ker \delta^0.
-- Represents a family of local models or specifications that seamlessly glue across all cell boundaries.
newtype GlobalSection vId stalk = GlobalSection
  { unGlobalSection :: Cochain0 vId stalk
  } deriving (Eq, Show)

-- | Validate and wrap a 0-cochain as a global section.
-- Fails if any boundary discrepancy exists.
globalSection
  :: (Ord vId, Eq edgeStalk)
  => CellComplex vId eId
  -> CellularSheaf vId eId stalk edgeStalk
  -> Cochain0 vId stalk
  -> Maybe (GlobalSection vId stalk)
globalSection complex sheaf c0 =
  if isHarmonicCochain complex sheaf c0
    then Just (GlobalSection c0)
    else Nothing

-- | Detailed diagnostic report for an interface obstruction along an edge.
data InterfaceObstruction eId edgeStalk = InterfaceObstruction
  { obstructedEdge    :: eId
  , sourceRestriction :: edgeStalk
  , targetRestriction :: edgeStalk
  } deriving (Eq, Show)

-- | Locate all failing interface boundaries where H^1 cohomological obstructions prevent composition.
-- Directly informs the CEGIS counterexample-guided repair loop.
locateObstructions
  :: (Ord vId, Eq edgeStalk)
  => CellComplex vId eId
  -> CellularSheaf vId eId stalk edgeStalk
  -> Cochain0 vId stalk
  -> [InterfaceObstruction eId edgeStalk]
locateObstructions complex sheaf c0 =
  let (Cochain1 diffs, _) = coboundary complex sheaf c0
  in [ InterfaceObstruction
         { obstructedEdge    = e
         , sourceRestriction = s
         , targetRestriction = t
         }
     | (e, (s, t)) <- Map.toList diffs
     , s /= t
     ]

-- | Theorem: Model Amalgamation via Sheaves.
-- H^0(G; Mod) \cong Mod(colim D).
-- When base model mB and aspect model mW restrict to identical interface models on c,
-- the sheaf coboundary vanishes and 'amalgamateModels' produces a verified amalgamated model.
verifyModelAmalgamation
  :: forall inst (c :: Sig inst) (b :: Sig inst) (w :: Sig inst) (p :: Sig inst).
     (PushoutWeaving inst, Eq (Mod inst c))
  => (c ~> b) -> (c ~> w) -> (b ~> p) -> (w ~> p)
  -> Mod inst b
  -> Mod inst w
  -> (Mod inst b -> Mod inst c)
  -> (Mod inst w -> Mod inst c)
  -> Maybe (Mod inst p)
verifyModelAmalgamation f g inB inW mb mw reductB reductW =
  let restrB = reductB mb
      restrW = reductW mw
  in if restrB == restrW
       then amalgamate @inst f g inB inW mb mw
       else Nothing
