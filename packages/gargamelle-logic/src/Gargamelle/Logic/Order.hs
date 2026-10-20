{-# LANGUAGE ConstraintKinds #-}

module Gargamelle.Logic.Order
  ( Lattice(..)
  , BoundedJoinSemiLattice(..)
  , BoundedMeetSemiLattice(..)
  , BoundedLattice
  , Heyting(..)
  , HeytingLattice
  , Op(..)
  ) where

import Algebra.Lattice
import Algebra.Lattice.Op (Op(..))
import Algebra.Heyting (Heyting(..))

-- | Bundled constraint alias for a complete Heyting refinement lattice.
type HeytingLattice l = (Eq l, BoundedLattice l, Heyting l)
