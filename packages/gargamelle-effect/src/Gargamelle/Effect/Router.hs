{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

{-|
Module      : Gargamelle.Effect.Router
Description : Re-exports O(1) variant jump table routing from Kernmantle
Copyright   : (c) 2026 The Gargamelle Authors
License     : EUPL-1.2
Maintainer  : nadia.yvette.chambers@ik.me

Re-exports 'Control.Kernmantle.Rope.Variant' upstreamed into @kernmantle@,
adapting variant routing to Gargamelle's domain-specific 'Rope'.
-}
module Gargamelle.Effect.Router
  ( -- * O(1) Variant Router Jump Table
    VariantRouter(..)
  , makeRouter
  , routeVariant
  , routeVariantRope
  , routerSize
    -- * Type-Safe Variant Routing & Multi-Way Branching
  , routeVariantWith
  , branchRope
    -- * Payload Extraction Helpers
  , getSlot
  , getSlotValue
  ) where

import Control.Kernmantle.Rope.Variant
  ( VariantRouter(..)
  , makeRouter
  , routeVariant
  , routerSize
  , routeVariantWith
  , branchRope
  , getSlot
  , getSlotValue
  )
import Effect.Rope (Rope(..))
import Polytropos (Variant)

-- | Route an open variant effect into a Gargamelle 'Rope' arrow computation.
routeVariantRope :: VariantRouter core a b -> Variant s -> Rope core mantle a b
routeVariantRope router var = Rope \_ -> routeVariant router var
{-# INLINE routeVariantRope #-}
