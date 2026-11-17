{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}

module Darcs.Patch.Witnesses.Sealed
  ( Sealed(..)
  , Sealed2(..)
  , seal
  , seal2
  , unseal
  , unseal2
  , mapSeal
  , mapSeal2
  ) where

import Data.Kind (Type)

data Sealed (a :: Type -> Type) where
  Sealed :: a wX -> Sealed a

data Sealed2 (a :: Type -> Type -> Type) where
  Sealed2 :: a wX wY -> Sealed2 a

seal :: a wX -> Sealed a
seal = Sealed

seal2 :: a wX wY -> Sealed2 a
seal2 = Sealed2

unseal :: (forall wX. a wX -> b) -> Sealed a -> b
unseal f (Sealed x) = f x

unseal2 :: (forall wX wY. a wX wY -> b) -> Sealed2 a -> b
unseal2 f (Sealed2 x) = f x

mapSeal :: (forall wX. a wX -> b wX) -> Sealed a -> Sealed b
mapSeal f (Sealed x) = Sealed (f x)

mapSeal2 :: (forall wX wY. a wX wY -> b wX wY) -> Sealed2 a -> Sealed2 b
mapSeal2 f (Sealed2 x) = Sealed2 (f x)
