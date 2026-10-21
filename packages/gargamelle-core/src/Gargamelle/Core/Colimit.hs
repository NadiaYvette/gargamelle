{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

module Gargamelle.Core.Colimit
  ( Cocone(..)
  , factorSemanticDelta
  ) where

import Proarrow.Core (CategoryOf(..), type (~>))
import Proarrow.Colimit.Pushout (HasPushouts(..))

-- | A cocone under a cospan (a <- c -> b) into target object q.
data Cocone k (a :: k) (b :: k) (q :: k) = Cocone
  { legA :: a ~> q
  , legB :: b ~> q
  }

{- Note [Colimit Mediating Morphisms and Semantic Delta Propagation]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-colimit-semantic-delta]
Colimits (including pushouts, coproducts, and general diagram colimits) represent
the universal composition of architectural and logical fragments along shared boundaries.
When one or more component specifications or implementations undergo revision (such as
a schema evolution, policy refinement, or security patch), the modified system forms
a candidate cocone Q under the original boundary cospan:
       A ──────► P ◄────── B
       │         ▲         │
       │         │ ?       │
       ▼         │         ▼
       A ──────► Q ◄────── B

By the universal property of the colimit apex P, there exists a unique mediating morphism
  u :: P ~> Q
such that the cocone commutes (u . legA == legA_Q and u . legB == legB_Q).

Architectural Role in Incremental Synthesis:
  1. Semantic Delta Reification: The mediating morphism @u@ precisely characterizes the
     semantic diff or migration required between the original composite system P and the
     updated target Q.
  2. Incremental Proof Translation: Rather than re-verifying the composed system from scratch,
     theorems and certificates established in P translate functorially across @u@ into Q,
     preserving already-verified properties.
  3. Incremental Re-synthesis: Synthesis engines use 'factorSemanticDelta' to isolate the
     minimal delta morphism that must be checked against host verification invariants.
-}

-- | Given a pushout (a -> p <- b) and an updated candidate cocone (a -> q <- b),
-- compute the unique mediating morphism / semantic delta factorizer (p -> q).
--
-- See Note [Colimit Mediating Morphisms and Semantic Delta Propagation] [ref:note-colimit-semantic-delta].
factorSemanticDelta
  :: forall k (a :: k) (b :: k) (p :: k) (q :: k). HasPushouts k
  => (a ~> p)
  -> (b ~> p)
  -> (a ~> q)
  -> (b ~> q)
  -> p ~> q
factorSemanticDelta = factorPushout
