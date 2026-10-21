{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE BlockArguments #-}

module Gargamelle.Equational.DPO
  ( Rule(..)
  , DPOStepResult(..)
  , applyDPO
  , isDPOApplicable
  , makeRule
  ) where

import Proarrow.Core (CategoryOf(..), type (~>))
import Proarrow.Tools.DPO (HasPushoutComplements(..), Rule(..), dpoStep)

-- | Construct a DPO rewrite rule from a left leg (l <- a) and right leg (a -> r).
makeRule :: forall k (a :: k) (l :: k) (r :: k). (a ~> l) -> (a ~> r) -> Rule a l r
makeRule = Rule

-- | Grounded result of executing a Double-Pushout (DPO) rewrite step.
-- When the gluing condition holds, produces the context/complement object @d@,
-- the rewritten host object @h@, and canonical inclusions.
-- When the gluing condition fails (dangling edge or identification conflict),
-- reports 'DPOGluingFailed'.
data DPOStepResult k g r where
  DPOSuccess
    :: forall k g r (d :: k) (h :: k).
       (d ~> g)  -- ^ Context inclusion into host object g
    -> (d ~> h)  -- ^ Context inclusion into rewritten object h
    -> (r ~> h)  -- ^ Right-hand pattern embedding into rewritten object h
    -> DPOStepResult k g r
  DPOGluingFailed :: DPOStepResult k g r

{- Note [Presheaf Double-Pushout Gluing Conditions]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-dpo-gluing-conditions]
In categorical graph transformation and presheaf rewriting (Ehrig et al., 1973),
a Double-Pushout (DPO) rewrite rule is specified as an interface span:
         l           r
    L ◄─────── K ────────► R

where:
  - L is the left-hand pattern matched in the host structure G via match morphism m : L ~> G.
  - K is the interface/gluing object containing items preserved across the rewrite.
  - R is the right-hand replacement pattern containing items created by the rewrite.

Executing a DPO rewrite involves two categorical pushout squares:
        L ◄───────────── K ─────────────► R
        │      (PO 1)    │      (PO 2)    │
      m │   Pushout      │                │
        │   Complement   │                │
        ▼                ▼                ▼
        G ◄───────────── D ─────────────► H = D ⨿_K R
              context

Theoretical Invariants & The Gluing Condition:
  Step 1 computes the Pushout Complement D = G \ m(L \ K). In adhesive and presheaf
  categories, this pushout complement exists IF AND ONLY IF the Gluing Condition holds:
    1. Identification Condition: If the match morphism m identifies two distinct items
       x, y in L (m(x) == m(y)), both x and y MUST belong to the interface K. Deleting one
       while preserving the other is ill-defined and prohibited.
    2. Dangling Condition: Deleting a node in G must not leave dangling edges that reference
       the deleted node without being deleted themselves.

Failure Handling:
  When the gluing condition is violated, 'applyDPO' safely returns 'DPOGluingFailed'
  without partial mutations or dangling pointers. When satisfied, 'applyDPO' constructs
  the exact context D and pushout H with canonical embedding arrows.
-}

-- | Apply a DPO rewrite rule to a host object along a match morphism (l ~> g).
--
-- See Note [Presheaf Double-Pushout Gluing Conditions] [ref:note-dpo-gluing-conditions].
applyDPO
  :: forall k (a :: k) (l :: k) (r :: k) (g :: k). HasPushoutComplements k
  => Rule a l r
  -> (l ~> g)
  -> DPOStepResult k g r
applyDPO rule match =
  dpoStep rule match DPOSuccess DPOGluingFailed

-- | Check whether a rule can be applied at a match without executing the full rewrite.
--
-- See Note [Presheaf Double-Pushout Gluing Conditions] [ref:note-dpo-gluing-conditions].
isDPOApplicable
  :: forall k (a :: k) (l :: k) (r :: k) (g :: k). HasPushoutComplements k
  => Rule a l r
  -> (l ~> g)
  -> Bool
isDPOApplicable rule match =
  dpoStep rule match (\_ _ _ -> True) False
