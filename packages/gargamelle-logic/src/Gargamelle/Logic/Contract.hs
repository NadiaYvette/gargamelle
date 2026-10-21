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

{- Note [Lattice Inversion via Op Dualization]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-lattice-op-dualization]
In formal verification and contract-based design, contract refinement
(C1 ⊑ C2, or meet C1 ∧ C2) means that C1 is a stricter, more capable specification
that can safely substitute for C2 in any environment.

For guarantees G, substitution requires strengthening: if C2 promised G2, C1 must
promise at least G2 (i.e. G1 ⊑ G2, which in standard logic or lattice refinement
corresponds to meet G1 ∧ G2).

For assumptions A, the direction of refinement is fundamentally reversed: if C2
required the environment to satisfy demanding assumption A2, a more capable component
C1 should require LESS of its environment (i.e. accept a wider range of behaviors,
A2 ⊑ A1, or A1 ∨ A2 in the base lattice).

Rather than writing manual ad-hoc case analyses or bifurcated order checks, Gargamelle
exploits the functorial order-dual operator 'Algebra.Lattice.Op' from the @lattices@
package:
  Op a ∧ Op b = Op (a ∨ b)
  Op a ∨ Op b = Op (a ∧ b)

By wrapping assumptions inside 'Op a', contract refinement becomes the standard product
meet:
  (Op A1, G1) ∧ (Op A2, G2) = (Op (A1 ∨ A2), G1 ∧ G2)

This mechanically weakens assumptions (expands admitted environments) while simultaneously
strengthening guarantees (restricts emitted behaviors) with zero runtime branching or
heuristic case splits.
-}

{- Note [Circular Assume-Guarantee Soundness]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-circular-ag-soundness]
When two components C1 = (A1, G1) and C2 = (A2, G2) interact concurrently across a shared
interface, mutual dependencies can lead to apparent cyclic reasoning:
  - C1 guarantees G1 provided C2 satisfies assumption A1.
  - C2 guarantees G2 provided C1 satisfies assumption A2.

In a Heyting algebra or intuitionistic logic lattice, circular reasoning is sound if and
only if each component's guarantee discharges the other component's assumption under the
shared interface context:
  dir1 = (A1 ∧ G2) ⟹ G1
  dir2 = (A2 ∧ G1) ⟹ G2

Sound composition holds when both entailments evaluate to the top element of the lattice:
  (dir1 ∧ dir2) == ⊤

If either component fails to establish its guarantee under the environment provided by
its partner, the circular check evaluates to a non-top element, pinpointing an interface
mismatch before deployment.
-}

-- | Assume-Guarantee contract using 'Algebra.Lattice.Op' from @lattices@.
--
-- See Note [Lattice Inversion via Op Dualization] [ref:note-lattice-op-dualization].
--
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
--
-- See Note [Circular Assume-Guarantee Soundness] [ref:note-circular-ag-soundness].
verifyCircularAG
  :: (Heyting l, Eq l)
  => AGContract l l
  -> AGContract l l
  -> Bool
verifyCircularAG (AGContract (Op a1) g1) (AGContract (Op a2) g2) =
  let dir1 = (a1 /\ g2) ==> g1
      dir2 = (a2 /\ g1) ==> g2
  in (dir1 /\ dir2) == top
