{-# LANGUAGE FlexibleContexts #-}

module Gargamelle.Logic.Contract
  ( AGContract(..)
  , contract
  , getAssumption
  , getGuarantee
  , deriveAGGalois
  , verifyCircularAG
  ) where

import Algebra.Lattice (Lattice(..), BoundedJoinSemiLattice(..), BoundedMeetSemiLattice(..))
import Algebra.Lattice.Op (Op(..))
import Algebra.Heyting (Heyting(..))
import Gargamelle.Logic.Defunctionalize (ObsMor(..))
import Gargamelle.Logic.Galois (Galois(..))

-- | Assume-Guarantee contract using 'Algebra.Lattice.Op' from @lattices@.
-- Because refinement is meet (/\), wrapping assumptions in 'Op' ensures that
-- contract refinement automatically weakens assumptions (as joins \/ in the base lattice)
-- while strengthening guarantees (as meets /\ in the base lattice).
data AGContract a g = AGContract
  { assumptions :: Op a
  , guarantees  :: g
  } deriving (Eq, Show)

-- | Smart constructor for AGContract.
contract :: a -> g -> AGContract a g
contract a = AGContract (Op a)

-- | Extract the raw assumption value.
getAssumption :: AGContract a g -> a
getAssumption (AGContract (Op a) _) = a

-- | Extract the guarantee value.
getGuarantee :: AGContract a g -> g
getGuarantee (AGContract _ g) = g

instance (Lattice a, Lattice g) => Lattice (AGContract a g) where
  AGContract a1 g1 /\ AGContract a2 g2 = AGContract (a1 /\ a2) (g1 /\ g2)
  AGContract a1 g1 \/ AGContract a2 g2 = AGContract (a1 \/ a2) (g1 \/ g2)

instance (BoundedMeetSemiLattice a, BoundedJoinSemiLattice a, BoundedMeetSemiLattice g)
         => BoundedMeetSemiLattice (AGContract a g) where
  top = AGContract (Op bottom) top

instance (BoundedMeetSemiLattice a, BoundedJoinSemiLattice g)
         => BoundedJoinSemiLattice (AGContract a g) where
  bottom = AGContract (Op top) bottom

-- | Lift component projections/liftings to an observable Galois connection on AGContracts.
deriveAGGalois
  :: (a1 -> a2) -> (a2 -> a1)
  -> (g1 -> g2) -> (g2 -> g1)
  -> Galois ObsMor (AGContract a1 g1) (AGContract a2 g2)
deriveAGGalois aRestrict aCoRestrict gRestrict gCoRestrict = Galois
  { restrict   = SymbolicStep "ag-restrict"   $ \(AGContract (Op a) g) -> AGContract (Op (aRestrict a)) (gRestrict g)
  , coRestrict = SymbolicStep "ag-coRestrict" $ \(AGContract (Op a) g) -> AGContract (Op (aCoRestrict a)) (gCoRestrict g)
  }

-- | Circular Assume-Guarantee Soundness Check on a shared interface:
-- Checks that (A1 /\ G2 ==> G1) /\ (A2 /\ G1 ==> G2) == top.
verifyCircularAG
  :: (Heyting l, Eq l)
  => AGContract l l
  -> AGContract l l
  -> Bool
verifyCircularAG (AGContract (Op a1) g1) (AGContract (Op a2) g2) =
  let dir1 = (a1 /\ g2) ==> g1
      dir2 = (a2 /\ g1) ==> g2
  in (dir1 /\ dir2) == top
