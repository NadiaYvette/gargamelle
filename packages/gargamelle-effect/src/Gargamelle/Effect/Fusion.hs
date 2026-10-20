{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Gargamelle.Effect.Fusion
Description : Re-exports Coyoneda pipeline fusion from Kernmantle
Copyright   : (c) 2026 The Gargamelle Authors
License     : EUPL-1.2
Maintainer  : nadia.yvette.chambers@ik.me

Re-exports 'Control.Kernmantle.Rope.Fusion' upstreamed into @kernmantle@,
adapting pipeline fusion to Gargamelle's domain-specific 'Rope'.
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
import Control.Kernmantle.Rope.Fusion
  ( Coyoneda(..)
  , liftCoyoneda
  , lowerCoyoneda
  , coyoneda
  , fuseMap
  , runFused
  )
import Effect.Rope (Rope)

-- | A wrapper for an arrow computation whose post-processing transformations
-- are deferred and fused via Coyoneda.
newtype FusedPipeline arr a b = FusedPipeline
  { unFusedPipeline :: Coyoneda (arr a) b
  }

-- | Chain a pure post-processing function onto a 'Rope' pipeline using Coyoneda fusion.
fuseRopeMap :: (b -> c) -> Coyoneda (Rope core mantle a) b -> Coyoneda (Rope core mantle a) c
fuseRopeMap = fmap
{-# INLINE fuseRopeMap #-}

-- | Fuse and materialize a Coyoneda-wrapped 'Rope' arrow into a standard 'Rope' pipeline
-- in a single composition step.
fuseRope :: Arrow core => Coyoneda (Rope core mantle a) b -> Rope core mantle a b
fuseRope (Coyoneda f r) = arr f <<< r
{-# INLINE fuseRope #-}
