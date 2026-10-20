{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Gargamelle.Effect.Router
  ( -- * O(1) Variant Router Jump Table
    VariantRouter(..)
  , makeRouter
  , routeVariant
  , routeVariantRope
  , routerSize
    -- * Payload Extraction Helpers
  , getSlot
  , getSlotValue
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
import Polytropos (Variant)
import Polytropos.Core (Rep, RowRep(..), repTag, repVals)

-- | A constant-time O(1) jump table routing open variant effect requests
-- directly to core arrow handlers indexed by their unboxed constructor tags.
newtype VariantRouter core a b = VariantRouter
  { routerTable :: SmallArray (Rep Identity () -> core a b)
  }

-- | Construct a 'VariantRouter' from an ordered list of branch handlers corresponding
-- to the consecutive constructor tags (0, 1, ..., n-1) of the sum row.
makeRouter :: [Rep Identity () -> core a b] -> VariantRouter core a b
makeRouter handlers = VariantRouter (smallArrayFromList handlers)

-- | Dispatch an open variant effect request through the jump table in O(1) time.
routeVariant :: VariantRouter core a b -> Variant s -> core a b
routeVariant (VariantRouter table) (RowRep rep) =
  let idx = fromIntegral (repTag rep)
  in if idx >= 0 && idx < sizeofSmallArray table
       then indexSmallArray table idx rep
       else error ("routeVariant: unhandled variant tag " ++ show idx)

-- | Route an open variant effect into a Kernmantle 'Rope' arrow computation.
routeVariantRope :: VariantRouter core a b -> Variant s -> Rope core mantle a b
routeVariantRope router var = Rope \_ -> routeVariant router var

-- | Number of registered branches in the jump table.
routerSize :: VariantRouter core a b -> Int
routerSize (VariantRouter table) = sizeofSmallArray table

-- | Safely extract a typed value from the i-th payload slot of a variant's active constructor.
getSlot :: forall x. Int -> Rep Identity () -> x
getSlot idx rep =
  let vals = repVals rep
  in if idx >= 0 && idx < sizeofSmallArray vals
       then unsafeCoerce (runIdentity (indexSmallArray vals idx))
       else error ("getSlot: index out of bounds " ++ show idx)

-- | Convenience helper for extracting a payload slot and wrapping it into a pure result.
getSlotValue :: forall x. Int -> Rep Identity () -> x
getSlotValue = getSlot
