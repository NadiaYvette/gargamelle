{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Gargamelle.Sheaf.Diffusion
  ( -- * Cellular Sheaf
    CellularSheaf(..)
  , symmetricSheaf
  , directionalSheaf
  , liftEdge
    -- * Cochains
  , Cochain0(..)
  , Cochain1(..)
  , lookupCochain0
  , lookupCochain1
  , fromListCochain0
  , fromListCochain1
    -- * Store Comonad Cellular Diffusion
  , cochainToStore
  , diffuseLocalRule
  , stepDiffusion
  , diffuseUntilHarmonic
  , diffuseTrace
  , meet
  , join
  ) where

import Algebra.Lattice (Lattice(..), BoundedMeetSemiLattice(..))
import Control.Comonad (extend, extract)
import Control.Comonad.Store (Store, store, pos, peek)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Gargamelle.Sheaf.Complex (CellComplex(..), incidentEdges, Orientation(..))

-- | Infix meet operator synonym.
meet :: Lattice a => a -> a -> a
meet = (/\)

-- | Infix join operator synonym.
join :: Lattice a => a -> a -> a
join = (\/)

{- Note [Cellular Sheaf Restriction Maps and Stalk Functors]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-cellular-sheaf-stalks]
In applied algebraic topology and distributed systems verification, a software
architecture is formalized as a 1-dimensional cell complex (graph complex) G = (V, E):
  - 0-cells (vertices v ∈ V) represent local component scopes, module stalks, or actor states.
  - 1-cells (edges e ∈ E) represent shared communication interfaces, network channels, or contracts.

A Cellular Sheaf F over G consists of:
  1. Stalk Assignments:
     - For each vertex v, a stalk F(v) containing local contract or model data.
     - For each edge e = (u, v), an edge stalk F(e) representing the shared interface contract.
  2. Restriction Maps:
     Along face inclusions u ⊴ e and v ⊴ e, directional restriction morphisms:
       ρ_{u ⊴ e} : F(u) -> F(e)
       ρ_{v ⊴ e} : F(v) -> F(e)
     project vertex-level internal invariants into the shared interface language.
  3. Adjoint Lifting Maps:
     Adjoint or Galois dual maps lift edge-level interface contracts back into vertex stalks:
       liftSrc : F(e) -> F(u)
       liftTgt : F(e) -> F(v)

Operational Role:
  - Symmetric Sheaves ('symmetricSheaf'): Useful when communication channels are non-directional
    and contracts are symmetric across client and server.
  - Directional Sheaves ('directionalSheaf'): Essential when interfaces distinguish caller
    assumptions from callee guarantees.
-}

-- | A cellular sheaf F over a cell complex G = (V, E).
-- Assigns stalks to 0-cells and 1-cells, restriction maps along cell face inclusions,
-- and comonadic diffusion lifting maps back to the vertex stalks.
--
-- See Note [Cellular Sheaf Restriction Maps and Stalk Functors] [ref:note-cellular-sheaf-stalks].
data CellularSheaf vId eId stalk edgeStalk = CellularSheaf
  { restrictSrc :: eId -> stalk -> edgeStalk  -- ^ \rho_{u \trianglelefteq e} (source restriction)
  , restrictTgt :: eId -> stalk -> edgeStalk  -- ^ \rho_{v \trianglelefteq e} (target restriction)
  , liftSrc     :: eId -> edgeStalk -> stalk  -- ^ Lift edge stalk back to source vertex
  , liftTgt     :: eId -> edgeStalk -> stalk  -- ^ Lift edge stalk back to target vertex
  }

-- | Backward-compatible alias for lifting an edge stalk to a vertex stalk.
liftEdge :: CellularSheaf vId eId stalk edgeStalk -> eId -> edgeStalk -> stalk
liftEdge = liftSrc

-- | Construct a cellular sheaf where source and target restrictions/lifts are symmetric.
symmetricSheaf
  :: (eId -> stalk -> edgeStalk)
  -> (eId -> edgeStalk -> stalk)
  -> CellularSheaf vId eId stalk edgeStalk
symmetricSheaf restr lift_ = CellularSheaf
  { restrictSrc = restr
  , restrictTgt = restr
  , liftSrc     = lift_
  , liftTgt     = lift_
  }

-- | Construct a cellular sheaf with explicit directional restriction and lifting maps.
directionalSheaf
  :: (eId -> stalk -> edgeStalk)
  -> (eId -> stalk -> edgeStalk)
  -> (eId -> edgeStalk -> stalk)
  -> (eId -> edgeStalk -> stalk)
  -> CellularSheaf vId eId stalk edgeStalk
directionalSheaf = CellularSheaf

-- | 0-Cochain: an assignment of stalk elements across 0-cells (vertices).
newtype Cochain0 vId stalk = Cochain0
  { unCochain0 :: Map vId stalk
  } deriving (Eq, Show, Functor)

-- | 1-Cochain: an assignment of edge stalk elements across 1-cells (edges).
newtype Cochain1 eId edgeStalk = Cochain1
  { unCochain1 :: Map eId edgeStalk
  } deriving (Eq, Show, Functor)

instance (Ord vId, Lattice stalk) => Lattice (Cochain0 vId stalk) where
  (/\) (Cochain0 m1) (Cochain0 m2) = Cochain0 (Map.unionWith (/\) m1 m2)
  (\/) (Cochain0 m1) (Cochain0 m2) = Cochain0 (Map.unionWith (\/) m1 m2)

-- | Safe lookup in a 0-cochain.
lookupCochain0 :: (Ord vId) => vId -> Cochain0 vId stalk -> Maybe stalk
lookupCochain0 v (Cochain0 m) = Map.lookup v m

-- | Safe lookup in a 1-cochain.
lookupCochain1 :: (Ord eId) => eId -> Cochain1 eId edgeStalk -> Maybe edgeStalk
lookupCochain1 e (Cochain1 m) = Map.lookup e m

-- | Create a 0-cochain from an association list.
fromListCochain0 :: (Ord vId) => [(vId, stalk)] -> Cochain0 vId stalk
fromListCochain0 = Cochain0 . Map.fromList

-- | Create a 1-cochain from an association list.
fromListCochain1 :: (Ord eId) => [(eId, edgeStalk)] -> Cochain1 eId edgeStalk
fromListCochain1 = Cochain1 . Map.fromList

-- | Represent a 0-cochain as a Store comonad focused at an initial vertex position.
-- Lookups outside the cochain return the provided fallback default.
cochainToStore :: (Ord vId) => stalk -> Cochain0 vId stalk -> vId -> Store vId stalk
cochainToStore defaultStalk (Cochain0 m) =
  store (\v -> Map.findWithDefault defaultStalk v m)

{- Note [Store Comonad Cellular Diffusion and Harmonic Consensus]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-store-comonad-diffusion]
Traditional graph algorithms process networks via imperative mutation or iterative loops.
Gargamelle models cellular space comonadically using 'Control.Comonad.Store':
  data Store s a = Store (s -> a) s

In cellular diffusion:
  - Focus 's = vId': The focused vertex currently under evaluation ('pos w').
  - Local Value: The current stalk contract at that vertex ('extract w').
  - Neighborhood Access: Neighboring contract stalks across incident cell boundaries
    are queried via 'peek other w'.

Parallel Global Diffusion via Comonadic 'extend':
  The local rule 'diffuseLocalRule' inspects the focused vertex and takes the meet (/\)
  of its current contract with all incoming restricted and lifted neighbor contracts.
  By invoking:
    diffusedStore = extend (diffuseLocalRule complex sheaf) baseStore
  the comonad simultaneously computes updated stalks across all vertices in the cell
  complex in a single pure, parallel evaluation step.

Knaster-Tarski Fixed-Point Convergence:
  Because the meet operation (/\) in a meet-semi-lattice is monotonic and contracting:
    c_{t+1} ⩽ c_t
  the sequence of 0-cochains produced by 'diffuseUntilHarmonic':
    c_0 ⩾ c_1 ⩾ c_2 ⩾ ...
  is guaranteed by the Knaster-Tarski fixed-point theorem to converge to the greatest
  lower bound (the most permissive common contract refinement that satisfies all interface
  boundary constraints simultaneously).
-}

-- | Local cellular diffusion step evaluated comonadically at the current focused vertex.
-- Uses 'pos' to determine the active vertex, 'extract' for its current stalk value,
-- and 'peek' to inspect neighboring stalks across incident cell boundaries.
--
-- See Note [Store Comonad Cellular Diffusion and Harmonic Consensus] [ref:note-store-comonad-diffusion].
diffuseLocalRule
  :: forall vId eId stalk edgeStalk.
     (Ord vId, BoundedMeetSemiLattice stalk)
  => CellComplex vId eId
  -> CellularSheaf vId eId stalk edgeStalk
  -> Store vId stalk
  -> stalk
diffuseLocalRule complex sheaf w =
  let v = pos w
      curr = extract w
      incident = incidentEdges complex v
      incomingStalks =
        [ case orient of
            Forward  ->
              -- v is source of e; neighbor 'other' is target.
              -- Restrict other's stalk via restrictTgt, then lift to v via liftSrc.
              liftSrc sheaf e (restrictTgt sheaf e (peek other w))
            Backward ->
              -- v is target of e; neighbor 'other' is source.
              -- Restrict other's stalk via restrictSrc, then lift to v via liftTgt.
              liftTgt sheaf e (restrictSrc sheaf e (peek other w))
        | (e, orient, other) <- incident
        ]
  in foldr meet curr incomingStalks

-- | Advance diffusion by one discrete comonadic step across all vertices in the complex.
-- Uses 'extend' on the Store comonad to simultaneously compute new values everywhere.
stepDiffusion
  :: forall vId eId stalk edgeStalk.
     (Ord vId, BoundedMeetSemiLattice stalk)
  => CellComplex vId eId
  -> CellularSheaf vId eId stalk edgeStalk
  -> Cochain0 vId stalk
  -> Cochain0 vId stalk
stepDiffusion complex sheaf c0@(Cochain0 m) = case vertices complex of
  [] -> c0
  (v0:_) ->
    let baseStore = cochainToStore top c0 v0
        diffusedStore = extend (diffuseLocalRule complex sheaf) baseStore
        newM = Map.fromList [ (v, peek v diffusedStore) | v <- vertices complex ]
    in Cochain0 (Map.union newM m)

-- | Knaster-Tarski fixed-point iteration via Store comonad diffusion.
-- Iterates until a fixed point is reached (new state == current state)
-- or the step limit is reached.
--
-- See Note [Store Comonad Cellular Diffusion and Harmonic Consensus] [ref:note-store-comonad-diffusion].
diffuseUntilHarmonic
  :: (Ord vId, BoundedMeetSemiLattice stalk, Eq stalk)
  => Int  -- ^ Maximum iterations
  -> CellComplex vId eId
  -> CellularSheaf vId eId stalk edgeStalk
  -> Cochain0 vId stalk
  -> Cochain0 vId stalk
diffuseUntilHarmonic maxSteps complex sheaf = go 0
  where
    go step c0
      | step >= maxSteps = c0
      | otherwise =
          let cNext = stepDiffusion complex sheaf c0
          in if cNext == c0
               then c0
               else go (step + 1) cNext

-- | Trace diffusion steps until a fixed point is reached or the limit is reached.
-- Produces the sequence of intermediate 0-cochains.
diffuseTrace
  :: (Ord vId, BoundedMeetSemiLattice stalk, Eq stalk)
  => Int
  -> CellComplex vId eId
  -> CellularSheaf vId eId stalk edgeStalk
  -> Cochain0 vId stalk
  -> [Cochain0 vId stalk]
diffuseTrace maxSteps complex sheaf = go 0
  where
    go step c0
      | step >= maxSteps = [c0]
      | otherwise =
          let cNext = stepDiffusion complex sheaf c0
          in if cNext == c0
               then [c0]
               else c0 : go (step + 1) cNext
