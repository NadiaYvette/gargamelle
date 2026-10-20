{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

module Gargamelle.Core.Discovery
  ( discoverInterface
  , factorInterface
  ) where

import Proarrow.Core (CategoryOf(..), type (~>))
import Proarrow.Limit.Pullback (HasPullbacks(..))

-- | Protocol and interface discovery via Pullbacks:
-- Given components A and B communicating with an ambient environment E (or host system),
-- discover the minimal shared interface P = A ×_E B.
discoverInterface
  :: forall k (o :: k) a b r. HasPullbacks k
  => a ~> o
  -> b ~> o
  -> (forall p. p ~> a -> p ~> b -> r)
  -> r
discoverInterface = pullback

-- | Factor a candidate interface implementation through the universal pullback interface.
factorInterface
  :: forall k (a :: k) (b :: k) (p :: k) (q :: k). HasPullbacks k
  => (p ~> a)
  -> (p ~> b)
  -> (q ~> a)
  -> (q ~> b)
  -> q ~> p
factorInterface = factorPullback
