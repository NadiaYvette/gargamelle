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

{- Note [Pullback Interface Discovery]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-pullback-interface-discovery]
In distributed architectures, microservices, and multi-agent workflows, independent
subsystems A and B frequently interact with an ambient environment, operating system,
or protocol broker E via morphisms:
  f :: a ~> e
  g :: b ~> e

When engineers or autonomous synthesis engines seek to establish direct peer-to-peer
communication between A and B without routing messages through the centralized broker E,
they must discover the exact common interface or shared session protocol.

In category theory, the universal solution to this problem is the Pullback (Fibered Product):
        P = A ×_E B ────────► B
             │                │
             │ projA          │ g
             ▼                ▼
             A ─────────────► E
                    f

Mathematical Invariants & Operational Utility:
  1. Exact Interface Discovery: The pullback apex P discovers the maximal shared interface
     through which A and B can communicate safely while ensuring environmental compatibility:
       f . projA == g . projB.
  2. Universal Factorization: For any candidate communication protocol Q with projections
     qA :: q ~> a and qB :: q ~> b such that f . qA == g . qB, 'factorInterface' computes
     the unique mediating morphism u :: q ~> p.
  3. Decoupling: Pullbacks allow synthesis engines to automatically discover minimal interface
     contracts between components without manual human schema negotiation.
-}

-- | Protocol and interface discovery via Pullbacks:
-- Given components A and B communicating with an ambient environment E (or host system),
-- discover the minimal shared interface P = A ×_E B.
--
-- See Note [Pullback Interface Discovery] [ref:note-pullback-interface-discovery].
discoverInterface
  :: forall k (o :: k) a b r. HasPullbacks k
  => a ~> o
  -> b ~> o
  -> (forall p. p ~> a -> p ~> b -> r)
  -> r
discoverInterface = pullback

-- | Factor a candidate interface implementation through the universal pullback interface.
--
-- See Note [Pullback Interface Discovery] [ref:note-pullback-interface-discovery].
factorInterface
  :: forall k (a :: k) (b :: k) (p :: k) (q :: k). HasPullbacks k
  => (p ~> a)
  -> (p ~> b)
  -> (q ~> a)
  -> (q ~> b)
  -> q ~> p
factorInterface = factorPullback
