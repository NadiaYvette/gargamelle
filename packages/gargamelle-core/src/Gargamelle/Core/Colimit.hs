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

-- | Given a pushout (a -> p <- b) and an updated candidate cocone (a -> q <- b),
-- compute the unique mediating morphism / semantic delta factorizer (p -> q).
factorSemanticDelta
  :: forall k (a :: k) (b :: k) (p :: k) (q :: k). HasPushouts k
  => (a ~> p)
  -> (b ~> p)
  -> (a ~> q)
  -> (b ~> q)
  -> p ~> q
factorSemanticDelta = factorPushout
