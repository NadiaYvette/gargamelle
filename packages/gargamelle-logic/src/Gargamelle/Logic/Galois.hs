{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}

module Gargamelle.Logic.Galois
  ( Galois(..)
  , composeGalois
  , galoisObsMor
  ) where

import Data.Kind (Type)
import Control.Category (Category(..))
import Gargamelle.Logic.Defunctionalize (ObsMor(..))
import Prelude hiding (id, (.))

{- Note [Adjoint Restrict-CoRestrict Galois Connections]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-galois-connection-stalks]
In sheaf-theoretic program analysis and cell complex verification, individual components
or subsystems reside at vertices (v ∈ V), while shared interfaces, protocol buses, and
network channels reside at boundary edges (e ∈ E).

To transfer contracts and refinement obligations soundly between interior component stalks
and boundary edge stalks, we employ a Galois connection (an adjunction between posets):
  restrict ⊣ coRestrict   (i.e. α ⊣ γ)

Formally, for vertex state/contract v ∈ V and boundary state/contract e ∈ E:
  restrict(v) ≤_E e   ⟺   v ≤_V coRestrict(e)

Where:
  1. 'restrict' (lower adjoint α) projects an interior vertex contract onto the shared
     boundary edge. It represents the interface footprint exposed to the outside world.
  2. 'coRestrict' (upper adjoint γ) takes a boundary guarantee or requirement and lifts it
     back into the interior vertex state space.

Adjunction invariants:
  - Unit:     v ≤_V coRestrict (restrict v)   (round-trip through boundary is an over-approximation)
  - Counit:   restrict (coRestrict e) ≤_E e   (round-trip from boundary is contractive)

By parameterizing 'Galois' over the underlying arrow category 'arr :: k -> k -> Type',
we can instantiate it with 'ObsMor', ensuring that interface projection and lifting
remain completely inspectable by autonomous agents and SMT solvers without executing
opaque closures.
-}

-- | Galois connection (restrict ⊣ coRestrict) between a Vertex Stalk and an Edge Stalk,
-- parameterized over the arrow category 'arr'.
--
-- See Note [Adjoint Restrict-CoRestrict Galois Connections] [ref:note-galois-connection-stalks].
data Galois (arr :: k -> k -> Type) vStalk eStalk = Galois
  { restrict   :: arr vStalk eStalk   -- ^ Lower adjoint α (projects specification to boundary)
  , coRestrict :: arr eStalk vStalk   -- ^ Upper adjoint γ (lifts boundary specification to vertex)
  }

-- | Compose two Galois connections in series.
composeGalois :: Category arr => Galois arr b c -> Galois arr a b -> Galois arr a c
composeGalois g2 g1 = Galois
  (restrict g2 . restrict g1)
  (coRestrict g1 . coRestrict g2)

-- | Construct an observable Galois connection from named projection/lifting functions.
galoisObsMor :: String -> (v -> e) -> (e -> v) -> Galois ObsMor v e
galoisObsMor label proj lift' = Galois
  (SymbolicStep (label ++ "-restrict") proj)
  (SymbolicStep (label ++ "-coRestrict") lift')
