{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

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
import Data.Functor.Coyoneda (Coyoneda(..), lowerCoyoneda, liftCoyoneda)
import Effect.Rope (Rope)

-- | Smart constructor for 'Coyoneda' applying a function to a functorial carrier.
coyoneda :: (a -> b) -> f a -> Coyoneda f b
coyoneda = Coyoneda

-- | Fuse an additional transformation onto a Coyoneda pipeline.
-- All mappings are accumulated in pure function composition without
-- executing intermediate passes or allocating intermediate arrays.
fuseMap :: (b -> c) -> Coyoneda f b -> Coyoneda f c
fuseMap = fmap

-- | Materialize the accumulated Coyoneda pipeline over an arbitrary functor carrier.
runFused :: Functor f => Coyoneda f a -> f a
runFused = lowerCoyoneda

-- | A wrapper for an arrow computation whose post-processing transformations
-- are deferred and fused via Coyoneda.
newtype FusedPipeline arr a b = FusedPipeline
  { unFusedPipeline :: Coyoneda (arr a) b
  }

-- | Fuse and materialize a Coyoneda-wrapped 'Rope' arrow into a standard 'Rope' pipeline
-- in a single composition step.
fuseRope :: Arrow core => Coyoneda (Rope core mantle a) b -> Rope core mantle a b
fuseRope (Coyoneda f r) = arr f <<< r

-- | Chain a pure post-processing function onto a 'Rope' pipeline using Coyoneda fusion.
fuseRopeMap :: (b -> c) -> Coyoneda (Rope core mantle a) b -> Coyoneda (Rope core mantle a) c
fuseRopeMap = fmap
