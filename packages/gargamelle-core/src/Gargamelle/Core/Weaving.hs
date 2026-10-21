{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableSuperClasses #-}
{-# LANGUAGE AllowAmbiguousTypes #-}

module Gargamelle.Core.Weaving
  ( PushoutWeaving(..)
  , weaveAspect
  , AmalgamatedModel(..)
  ) where

import Data.Kind (Type)
import Proarrow.Core (CategoryOf(..), type (~>))
import Proarrow.Colimit.Pushout (HasPushouts(..))
import Gargamelle.Core.Institution (Sig, CategoricalInstitution(..), ModelTheory(..))

-- | Data container for an amalgamated model combining base model M_B and aspect model M_W.
data AmalgamatedModel mb mw = AmalgamatedModel
  { baseModel   :: mb
  , aspectModel :: mw
  } deriving (Eq, Show)

{- Note [Categorical Pushout Feature Weaving]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-pushout-feature-weaving]
In aspect-oriented software engineering and formal program synthesis, modifying a base
specification B directly to inject an aspect or concern W (e.g. logging, audit trails,
persistent storage, transactional locking) creates three major hazards:
  1. Destructive Mutation: Modifying the base AST invalidates prior proofs and regression
     test guarantees established for B.
  2. Syntactic Collision: Injected variable names, sorts, and operations can unintentionally
     clash with base identifiers.
  3. Ad-Hoc Weaving Rules: Custom text-based or AST-grafting rules fail to preserve logical
     satisfaction conditions.

Gargamelle formulates non-invasive feature weaving algebraically as a categorical Pushout:
  Given base signature B, aspect extension W, and their shared common interface C:
    inclB :: c ~> b
    inclW :: c ~> w

  The woven system signature P is the categorical pushout apex:
          C ──────────────► W
          │                 │
          │ inclB           │ injAspect
          ▼                 ▼
          B ──────────────► P = B ⨿_C W
                injBase

Universal Property & Soundness:
  1. Canonical Injections: 'weaveAspect' yields injection arrows (injBase, injAspect) such that
     the square commutes: injBase . inclB == injAspect . inclW.
  2. Model Amalgamation: Because the model functor Mod is contravariant, it maps the pushout
     in Sig to a pullback in Cat. When models M_B and M_W agree on interface C, 'amalgamate'
     constructs a unique, canonical amalgamated model M_P.
  3. Preservation of Invariants: All theorems proven about B in isolation translate
     functorially along injBase into P with zero re-verification cost.
-}

-- | Pushout Feature Weaving:
--
-- See Note [Categorical Pushout Feature Weaving] [ref:note-pushout-feature-weaving].
--
-- Combines base logic B with aspect extension W over common interface C.
class (CategoricalInstitution i, HasPushouts (Sig i)) => PushoutWeaving (i :: Type) where
  -- | Amalgamate models M_B and M_W that agree on common interface C.
  amalgamate
    :: forall (c :: Sig i) (b :: Sig i) (w :: Sig i) (p :: Sig i).
       (c ~> b)
    -> (c ~> w)
    -> (b ~> p)
    -> (w ~> p)
    -> Mod i b
    -> Mod i w
    -> Maybe (Mod i p)

-- | Non-invasively weave an aspect extension into a base signature over a shared interface C.
-- Returns the pushout signature P and canonical injection morphisms (inclB, inclW).
--
-- See Note [Categorical Pushout Feature Weaving] [ref:note-pushout-feature-weaving].
weaveAspect
  :: forall k (c :: k) (b :: k) (w :: k) r. HasPushouts k
  => (c ~> b)  -- ^ Interface inclusion into Base
  -> (c ~> w)  -- ^ Interface inclusion into Aspect
  -> (forall p. (b ~> p) -> (w ~> p) -> r)
  -> r
weaveAspect = pushout
