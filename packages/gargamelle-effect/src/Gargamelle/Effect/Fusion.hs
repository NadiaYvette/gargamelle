{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Gargamelle.Effect.Fusion
Description : Coyoneda pipeline fusion for Penelope and Gargamelle ropes
Copyright   : (c) 2026 The Gargamelle Authors
License     : EUPL-1.2
Maintainer  : nadia.yvette.chambers@ik.me

Provides Coyoneda pipeline fusion for 'Effect.Rope.Rope' and Penelope arrow computations.
-}
module Gargamelle.Effect.Fusion
  ( -- * Coyoneda Array and Effect Fusion
    Coyoneda(..)
  , liftCoyoneda
  , lowerCoyoneda
  , coyoneda
  , fuseMap
  , runFused
    -- * Fused Arrow Pipelines
  , FusedPipeline(..)
  , fuseRope
  , fuseRopeMap
  ) where

import Control.Arrow (Arrow, arr, (<<<))
import Data.Functor.Coyoneda (Coyoneda(..), liftCoyoneda, lowerCoyoneda)
import Effect.Rope (Rope)

-- | Smart constructor for 't:Coyoneda' applying a function to a carrier.
coyoneda :: (a -> b) -> f a -> Coyoneda f b
coyoneda = Coyoneda
{-# INLINE coyoneda #-}

-- | Fuse an additional transformation onto a Coyoneda pipeline.
fuseMap :: (b -> c) -> Coyoneda f b -> Coyoneda f c
fuseMap = fmap
{-# INLINE fuseMap #-}

-- | Materialize the accumulated Coyoneda pipeline over an arbitrary functor carrier.
runFused :: Functor f => Coyoneda f a -> f a
runFused = lowerCoyoneda
{-# INLINE runFused #-}

-- | A wrapper for an arrow computation whose post-processing transformations
-- are deferred and fused via Coyoneda.
newtype FusedPipeline arr a b = FusedPipeline
  { unFusedPipeline :: Coyoneda (arr a) b
  }

-- | Chain a pure post-processing function onto a 't:Effect.Rope.Rope' pipeline using Coyoneda fusion.
fuseRopeMap :: (b -> c) -> Coyoneda (Rope core mantle a) b -> Coyoneda (Rope core mantle a) c
fuseRopeMap = fmap
{-# INLINE fuseRopeMap #-}

{- Note [Coyoneda Pipeline Fusion]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-coyoneda-pipeline-fusion]
In Arrow-based effect pipelines, appending successive post-processing transformations
  (f >>> g >>> h)
normally requires lifting each pure function into an arrow constructor:
  arr h <<< arr g <<< arr f <<< r
In deeply nested workflow architectures (such as CEGIS counterexample extraction and
sheaf localization), this creates multiple intermediate closure frames and redundant
arrow composition overhead.

The Coyoneda lemma states that for any type constructor F:
  Coyoneda F A ≅ ∃ B. (B -> A) × F B

By wrapping the arrow computation inside 'Coyoneda (Rope core mantle a)', intermediate
post-processing transformations ('fuseRopeMap' / 'fmap') are not applied immediately to
the arrow. Instead, they are accumulated via standard Haskell function composition:
  fmap h (fmap g (fmap f (Coyoneda id r)))  ==  Coyoneda (h . g . f) r

When the pipeline is finally materialized via 'fuseRope', the accumulated transformation
is lifted into the underlying arrow in a single atomic composition:
  fuseRope (Coyoneda (h . g . f) r) = arr (h . g . f) <<< r

This guarantees zero intermediate arrow nodes, eliminating allocations and maximizing
GHC worker-wrapper inlining.
-}

-- | Fuse and materialize a Coyoneda-wrapped 't:Effect.Rope.Rope' arrow into a standard 't:Effect.Rope.Rope' pipeline
-- in a single composition step.
--
-- See Note [Coyoneda Pipeline Fusion] [ref:note-coyoneda-pipeline-fusion].
fuseRope :: Arrow core => Coyoneda (Rope core mantle a) b -> Rope core mantle a b
fuseRope (Coyoneda f r) = arr f <<< r
{-# INLINE fuseRope #-}
