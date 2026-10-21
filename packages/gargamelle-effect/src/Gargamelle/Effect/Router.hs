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
adapting variant routing to Gargamelle's domain-specific 'Effect.Rope.Rope'.
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

{- Note [O(1) Variant Jump-Table Dispatch Physics]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-variant-jump-table-physics]
Traditional extensible effect systems (e.g., Freer, Polysemy, Eff) dispatch dynamic
effects by traversing a type-level type list using 'Member eff r' evidence. At runtime,
this induces two substantial overheads:
  1. O(N) linear search through the effect mantle, where N is the number of active effects.
  2. Recursive dictionary unpackings and intermediate constructor allocations on the heap.

Gargamelle leverages the structural open ADT representation of @polytropos@ to achieve
true hardware-level O(1) jump-table dispatch:
  1. A Polytropos 'Variant' is represented internally by 'Polytropos.Core.Rep':
     a machine-word constructor tag ('tag :: Int') plus a flat 'SmallArray' of payload slots.
  2. The 'VariantRouter' stores a flat 'SmallArray' of handler closures indexed directly
     by integer constructor tag (0 .. N-1).
  3. Dispatch via 'routeVariant' or 'routeVariantRope' reads the unboxed tag from the
     incoming variant and performs an immediate O(1) array index:
       handler = indexSmallArray table tag
       handler (payload rep)
  4. The CPU executes a single indirect jump with zero allocation on the hot path,
     guaranteeing constant-time effect resolution regardless of how many strands are woven
     into the mantle.
-}

-- | Route an open variant effect into a Gargamelle 'Effect.Rope.Rope' arrow computation.
--
-- See Note [O(1) Variant Jump-Table Dispatch Physics] [ref:note-variant-jump-table-physics].
routeVariantRope :: VariantRouter core a b -> Variant s -> Rope core mantle a b
routeVariantRope router var = Rope \_ -> routeVariant router var
{-# INLINE routeVariantRope #-}
