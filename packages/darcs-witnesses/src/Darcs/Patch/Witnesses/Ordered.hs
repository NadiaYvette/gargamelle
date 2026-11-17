{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

module Darcs.Patch.Witnesses.Ordered
  ( FL(..)
  , RL(..)
  , (:>)(..)
  , (:\/:)(..)
  , (:/\:)(..)
  , (+>+)
  , (+<+)
  , mapFL_FL
  , mapRL_RL
  , reverseFL
  , reverseRL
  , lengthFL
  , lengthRL
  , nullFL
  , nullRL
  ) where

import Data.Kind (Type)

-- | Forward list: patch sequence extending from left to right.
data FL (p :: Type -> Type -> Type) (wX :: Type) (wZ :: Type) where
  NilFL :: FL p wW wW
  (:>:) :: p wW wX -> FL p wX wY -> FL p wW wY

infixr 5 :>:

-- | Reverse list: patch sequence extending backwards from right to left.
data RL (p :: Type -> Type -> Type) (wX :: Type) (wZ :: Type) where
  NilRL :: RL p wW wW
  (:<:) :: RL p wW wX -> p wX wY -> RL p wW wY

infixl 5 :<:

-- | Sequential pair: patch p followed by patch q.
data (:>) (p1 :: Type -> Type -> Type) (p2 :: Type -> Type -> Type) (wA :: Type) (wC :: Type) where
  (:>) :: p1 wA wB -> p2 wB wC -> (:>) p1 p2 wA wC

infixr 1 :>

-- | Parallel pair: two patches sharing initial context wA.
data (:\/:) (p1 :: Type -> Type -> Type) (p2 :: Type -> Type -> Type) (wB :: Type) (wC :: Type) where
  (:\/:) :: p1 wA wB -> p2 wA wC -> (:\/:) p1 p2 wB wC

infix 1 :\/:

-- | Parallel pair: two patches sharing final context wC.
data (:/\:) (p1 :: Type -> Type -> Type) (p2 :: Type -> Type -> Type) (wA :: Type) (wB :: Type) where
  (:/\:) :: p1 wA wC -> p2 wB wC -> (:/\:) p1 p2 wA wB

infix 1 :/\:

(+>+) :: FL p wX wY -> FL p wY wZ -> FL p wX wZ
NilFL +>+ ys = ys
(x :>: xs) +>+ ys = x :>: (xs +>+ ys)

(+<+) :: RL p wY wZ -> RL p wX wY -> RL p wX wZ
NilRL +<+ ys = ys
(xs :<: x) +<+ ys = (xs +<+ ys) :<: x

mapFL_FL :: (forall wA wB. p wA wB -> q wA wB) -> FL p wX wY -> FL q wX wY
mapFL_FL _ NilFL = NilFL
mapFL_FL f (x :>: xs) = f x :>: mapFL_FL f xs

mapRL_RL :: (forall wA wB. p wA wB -> q wA wB) -> RL p wX wY -> RL q wX wY
mapRL_RL _ NilRL = NilRL
mapRL_RL f (xs :<: x) = mapRL_RL f xs :<: f x

reverseFL :: FL p wX wY -> RL p wX wY
reverseFL = go NilRL
  where
    go :: RL p wA wB -> FL p wB wC -> RL p wA wC
    go acc NilFL = acc
    go acc (p :>: ps) = go (acc :<: p) ps

reverseRL :: RL p wX wY -> FL p wX wY
reverseRL = go NilFL
  where
    go :: FL p wB wC -> RL p wA wB -> FL p wA wC
    go acc NilRL = acc
    go acc (ps :<: p) = go (p :>: acc) ps

lengthFL :: FL p wX wY -> Int
lengthFL NilFL = 0
lengthFL (_ :>: xs) = 1 + lengthFL xs

lengthRL :: RL p wX wY -> Int
lengthRL NilRL = 0
lengthRL (xs :<: _) = 1 + lengthRL xs

nullFL :: FL p wX wY -> Bool
nullFL NilFL = True
nullFL (_ :>: _) = False

nullRL :: RL p wX wY -> Bool
nullRL NilRL = True
nullRL (_ :<: _) = False
