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

-- | Pushout Feature Weaving:
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
weaveAspect
  :: forall k (c :: k) (b :: k) (w :: k) r. HasPushouts k
  => (c ~> b)  -- ^ Interface inclusion into Base
  -> (c ~> w)  -- ^ Interface inclusion into Aspect
  -> (forall p. (b ~> p) -> (w ~> p) -> r)
  -> r
weaveAspect = pushout
