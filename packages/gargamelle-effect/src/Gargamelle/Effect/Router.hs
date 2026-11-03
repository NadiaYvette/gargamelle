{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

{-|
Module      : Gargamelle.Effect.Router
Description : O(1) variant jump table routing for Penelope and Gargamelle ropes
Copyright   : (c) 2026 The Gargamelle Authors
License     : EUPL-1.2
Maintainer  : nadia.yvette.chambers@ik.me

Provides constant-time \(O(1)\) jump table dispatch and extensible multi-branch choice
for effect arrow computations over 'Polytropos.Variant' open sums, powered by
@polytropos@ and @penelope@.
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
    -- * Re-exports from Penelope & Polytropos
  , deriveRouter
  ) where

import Data.Functor.Identity (Identity(..))
import Data.Primitive.SmallArray
  ( SmallArray
  , sizeofSmallArray
  , indexSmallArray
  , smallArrayFromList
  )
import Unsafe.Coerce (unsafeCoerce)

import Effect.Rope (Rope(..))
import Penelope.Effects.Binary (deriveRouter)
import Polytropos
  ( Variant
  , Record
  , HandlerRecordRow
  , eliminateUniform
  )
import Polytropos.Core (Rep, RowRep(..), repTag, repVals)

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

-- | A constant-time O(1) jump table routing open variant effect requests
-- directly to core arrow handlers indexed by their unboxed constructor tags.
newtype VariantRouter core a b = VariantRouter
  { routerTable :: SmallArray (Rep Identity () -> core a b)
  }

-- | Construct a 'VariantRouter' from an ordered list of branch handlers corresponding
-- to consecutive constructor tags (0, 1, ..., n-1) of the sum row.
makeRouter :: [Rep Identity () -> core a b] -> VariantRouter core a b
makeRouter handlers = VariantRouter (smallArrayFromList handlers)
{-# INLINE makeRouter #-}

-- | Dispatch an open variant effect request through the jump table in O(1) time.
routeVariant :: VariantRouter core a b -> Variant s -> core a b
routeVariant (VariantRouter table) (RowRep rep) =
  let idx = fromIntegral (repTag rep)
  in if idx >= 0 && idx < sizeofSmallArray table
       then indexSmallArray table idx rep
       else error ("routeVariant: unhandled variant tag " ++ show idx)
{-# INLINE routeVariant #-}

-- | Route an open variant effect into a Gargamelle 'Effect.Rope.Rope' arrow computation.
--
-- See Note [O(1) Variant Jump-Table Dispatch Physics] [ref:note-variant-jump-table-physics].
routeVariantRope :: VariantRouter core a b -> Variant s -> Rope core mantle a b
routeVariantRope router var = Rope \_ -> routeVariant router var
{-# INLINE routeVariantRope #-}

-- | Route an open variant effect into a 'Rope' computation using a statically-typed
-- 'Polytropos.Record' of core arrow handlers. The compiler verifies full row exhaustiveness.
routeVariantWith :: Record (HandlerRecordRow s (core a b)) -> Variant s -> Rope core mantle a b
routeVariantWith handlers var = Rope \_ -> eliminateUniform handlers var
{-# INLINE routeVariantWith #-}

-- | Multi-way branch combinator for 'Rope' arrows over an open variant in O(1) time.
-- Eliminates the need for binary 'Control.Arrow.ArrowChoice' cascades over nested 'Either's.
branchRope :: Record (HandlerRecordRow s (Rope core mantle a b)) -> Variant s -> Rope core mantle a b
branchRope handlers var = eliminateUniform handlers var
{-# INLINE branchRope #-}

-- | Number of registered branches in the jump table.
routerSize :: VariantRouter core a b -> Int
routerSize (VariantRouter table) = sizeofSmallArray table
{-# INLINE routerSize #-}

-- | Safely extract a typed value from the i-th payload slot of a variant's active constructor.
getSlot :: forall x. Int -> Rep Identity () -> x
getSlot idx rep =
  let vals = repVals rep
  in if idx >= 0 && idx < sizeofSmallArray vals
       then unsafeCoerce (runIdentity (indexSmallArray vals idx))
       else error ("getSlot: index out of bounds " ++ show idx)
{-# INLINE getSlot #-}

-- | Convenience helper for extracting a payload slot.
getSlotValue :: forall x. Int -> Rep Identity () -> x
getSlotValue = getSlot
{-# INLINE getSlotValue #-}
