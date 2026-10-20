{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Gargamelle.Effect.Optics
  ( -- * Profunctor Optics Types
    Lens
  , Lens'
  , Prism
  , Prism'
  , lens
  , prism
    -- * Viewers & Modifiers
  , view
  , preview
  , over
  , set
    -- * Polytropos Structural Optics
  , slotLens
  , typedSlotLens
  , variantPrism
  , typedVariantPrism
  ) where

import Control.Monad.ST (runST)
import Data.Functor.Identity (Identity(..))
import Data.Monoid (First(..))
import Data.Primitive.SmallArray
  ( SmallArray
  , sizeofSmallArray
  , indexSmallArray
  , smallArrayFromList
  , thawSmallArray
  , writeSmallArray
  , unsafeFreezeSmallArray
  )
import Data.Profunctor (Profunctor(..), Strong(..), Choice(..))
import Data.Profunctor.Types (Forget(..))
import GHC.Exts (Any)
import Unsafe.Coerce (unsafeCoerce)

import Polytropos (Record, Variant)
import Polytropos.Core (Rep(..), RowRep(..))

-- | Standard Profunctor Lens.
type Lens s t a b = forall p. Strong p => p a b -> p s t

-- | Monomorphic Profunctor Lens.
type Lens' s a = Lens s s a a

-- | Standard Profunctor Prism.
type Prism s t a b = forall p. Choice p => p a b -> p s t

-- | Monomorphic Profunctor Prism.
type Prism' s a = Prism s s a a

-- | Construct a profunctor lens from a getter and setter.
lens :: (s -> a) -> (s -> b -> t) -> Lens s t a b
lens getter setter = dimap (\s -> (getter s, s)) (\(b, s) -> setter s b) . first'

-- | Construct a profunctor prism from an injector and matcher.
prism :: (b -> t) -> (s -> Either t a) -> Prism s t a b
prism build match = dimap match (either id build) . right'

-- | Extract the target of a lens using the 'Forget' profunctor.
view :: Lens' s a -> s -> a
view l = runForget (l (Forget id))

-- | Attempt to extract the target of a prism using 'Forget (First a)'.
preview :: Prism' s a -> s -> Maybe a
preview p = getFirst . runForget (p (Forget (First . Just)))

-- | Modify the focus of an optic using the (->) profunctor.
over :: Lens s t a b -> (a -> b) -> s -> t
over l = l

-- | Set the focus of a lens to a specific value.
set :: Lens s t a b -> b -> s -> t
set l val = over l (const val)

-- | Pure in-place slot replacement on a 'SmallArray'.
updateSmallArray :: SmallArray a -> Int -> a -> SmallArray a
updateSmallArray arr idx val = runST do
  m <- thawSmallArray arr 0 (sizeofSmallArray arr)
  writeSmallArray m idx val
  unsafeFreezeSmallArray m

-- | A zero-cost profunctor lens focusing on the raw i-th slot of an open 'Record'.
slotLens :: Int -> Lens' (Record r) (Identity Any)
slotLens idx = lens getter setter
  where
    getter (RowRep (Rep _ vals)) = indexSmallArray vals idx
    setter (RowRep (Rep tag vals)) newVal =
      RowRep (Rep tag (updateSmallArray vals idx newVal))

-- | A typed profunctor lens focusing on the i-th field of an open 'Record'.
typedSlotLens :: forall a r. Int -> Lens' (Record r) a
typedSlotLens idx = lens getter setter
  where
    getter (RowRep (Rep _ vals)) =
      unsafeCoerce (runIdentity (indexSmallArray vals idx))
    setter (RowRep (Rep tag vals)) newVal =
      let boxed = Identity (unsafeCoerce newVal :: Any)
      in RowRep (Rep tag (updateSmallArray vals idx boxed))

-- | A profunctor prism focusing on an open 'Variant' branch with a given constructor tag.
variantPrism :: Word -> Prism' (Variant s) (SmallArray (Identity Any))
variantPrism targetTag = prism build match
  where
    build vals = RowRep (Rep targetTag vals)
    match (RowRep rep@(Rep t vals))
      | t == targetTag = Right vals
      | otherwise      = Left (RowRep rep)

-- | A typed profunctor prism focusing on a single-payload 'Variant' constructor.
typedVariantPrism :: forall a s. Word -> Prism' (Variant s) a
typedVariantPrism targetTag = prism build match
  where
    build x =
      let payload = smallArrayFromList [Identity (unsafeCoerce x :: Any)]
      in RowRep (Rep targetTag payload)
    match (RowRep rep@(Rep t vals))
      | t == targetTag && sizeofSmallArray vals >= 1 =
          Right (unsafeCoerce (runIdentity (indexSmallArray vals 0)))
      | otherwise =
          Left (RowRep rep)
