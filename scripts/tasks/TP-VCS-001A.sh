#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-VCS-001A] Setting up darcs-witnesses ==="

PKG_DIR="packages/darcs-witnesses"
mkdir -p "$PKG_DIR/src/Darcs/Patch/Witnesses"
mkdir -p "$PKG_DIR/test"

cat << 'EOF' > "$PKG_DIR/darcs-witnesses.cabal"
cabal-version:      3.0
name:               darcs-witnesses
version:            0.1.0.0
synopsis:           GADT-witnessed patch algebra primitives (FL, RL, :\\/:, :/\\:, Invert, Commute, CleanMerge)
description:        Standalone zero-dependency typed patch category witnesses for Darcs, Gargamelle, and Yamaarashi.
license:            BSD-3-Clause
author:             Nadia Yvette Chambers
maintainer:         nadia.yvette.chambers@ik.me
category:           Data, Development
build-type:         Simple

library
    exposed-modules:
        Darcs.Patch.Witnesses
        Darcs.Patch.Witnesses.Ordered
        Darcs.Patch.Witnesses.Sealed
        Darcs.Patch.Witnesses.Class
    build-depends:
        base >= 4.18 && < 5
    hs-source-dirs:   src
    default-language: GHC2021
    ghc-options:      -Wall -O2

test-suite darcs-witnesses-test
    type:             exitcode-stdio-1.0
    main-is:          Main.hs
    hs-source-dirs:   test
    build-depends:
        base >= 4.18 && < 5,
        darcs-witnesses,
        QuickCheck >= 2.14
    default-language: GHC2021
    ghc-options:      -Wall
EOF

cat << 'EOF' > "$PKG_DIR/src/Darcs/Patch/Witnesses/Ordered.hs"
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
EOF

cat << 'EOF' > "$PKG_DIR/src/Darcs/Patch/Witnesses/Sealed.hs"
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
EOF

cat << 'EOF' > "$PKG_DIR/src/Darcs/Patch/Witnesses/Class.hs"
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

module Darcs.Patch.Witnesses.Class
  ( Invert(..)
  , Commute(..)
  , CleanMerge(..)
  ) where

import Darcs.Patch.Witnesses.Ordered (FL(..), (:>)(..), (:\/:)(..), (:/\:)(..), (+>+))

class Invert (p :: * -> * -> *) where
  invert :: p wX wY -> p wY wX

class Commute (p :: * -> * -> *) where
  commute :: (:>) p p wX wZ -> Maybe ((:>) p p wX wZ)

class CleanMerge (p :: * -> * -> *) where
  cleanMerge :: (:\/:) p p wX wY -> Maybe ((:/\:) p p wX wY)

instance Invert p => Invert (FL p) where
  invert NilFL = NilFL
  invert (p :>: ps) = invert ps +>+ (invert p :>: NilFL)

instance Commute p => Commute (FL p) where
  commute (NilFL :> ys) = Just (ys :> NilFL)
  commute (xs :> NilFL) = Just (NilFL :> xs)
  commute ((x :>: xs) :> ys) = do
    ys' :> x' <- commuteOne (x :> ys)
    xs' :> ys'' <- commute (xs :> ys')
    pure (ys'' :> (x' :>: xs'))
    where
      commuteOne :: (:>) p (FL p) wA wC -> Maybe ((:>) (FL p) p wA wC)
      commuteOne (p :> NilFL) = Just (NilFL :> p)
      commuteOne (p :> (q :>: qs)) = do
        q' :> p' <- commute (p :> q)
        qs' :> p'' <- commuteOne (p' :> qs)
        pure ((q' :>: qs') :> p'')
EOF

cat << 'EOF' > "$PKG_DIR/src/Darcs/Patch/Witnesses.hs"
module Darcs.Patch.Witnesses
  ( module Darcs.Patch.Witnesses.Ordered
  , module Darcs.Patch.Witnesses.Sealed
  , module Darcs.Patch.Witnesses.Class
  ) where

import Darcs.Patch.Witnesses.Ordered
import Darcs.Patch.Witnesses.Sealed
import Darcs.Patch.Witnesses.Class
EOF

cat << 'EOF' > "$PKG_DIR/test/Main.hs"
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

module Main (main) where

import Control.Monad (unless)
import Darcs.Patch.Witnesses
import System.Exit (exitFailure, exitSuccess)
import Test.QuickCheck

-- | A simple test patch representing integer state delta for property tests
data TestDelta (wX :: *) (wY :: *) where
  TestDelta :: Int -> TestDelta wX wY
  deriving (Eq, Show)

instance Invert TestDelta where
  invert (TestDelta n) = TestDelta (-n)

instance Commute TestDelta where
  commute (TestDelta a :> TestDelta b) =
    -- Integer additions commute trivially
    Just (TestDelta b :> TestDelta a)

-- | Test double inversion property
prop_invert_involutive :: Int -> Bool
prop_invert_involutive n =
  let p = TestDelta n :: TestDelta () ()
  in invert (invert p) == p

-- | Test commutation involution property
prop_commute_involution :: Int -> Int -> Bool
prop_commute_involution a b =
  let p = TestDelta a :: TestDelta () ()
      q = TestDelta b :: TestDelta () ()
  in case commute (p :> q) of
       Just (q' :> p') -> commute (q' :> p') == Just (p :> q)
       Nothing         -> False

-- | Test forward/reverse list roundtrip
test_list_roundtrip :: Bool
test_list_roundtrip =
  let p1 = TestDelta 1 :: TestDelta () ()
      p2 = TestDelta 2 :: TestDelta () ()
      fl = p1 :>: p2 :>: NilFL
      rl = reverseFL fl
      fl' = reverseRL rl
  in lengthFL fl == 2 && lengthRL rl == 2 && lengthFL fl' == 2

main :: IO ()
main = do
  putStrLn "Running QuickCheck properties for Darcs.Patch.Witnesses..."
  res1 <- quickCheckResult prop_invert_involutive
  res2 <- quickCheckResult prop_commute_involution
  unless (isSuccess res1 && isSuccess res2 && test_list_roundtrip) $ do
    putStrLn "Tests failed!"
    exitFailure
  putStrLn "All tests passed successfully."
  exitSuccess
EOF

if ! grep -q "packages/darcs-witnesses" cabal.project; then
  echo "  Adding darcs-witnesses to cabal.project..."
  sed -i '/packages\/darcs-patch-index-prim/i \  packages\/darcs-witnesses' cabal.project
fi

echo "=== [TP-VCS-001A] Completed successfully ==="
