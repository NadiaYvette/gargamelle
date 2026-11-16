#!/usr/bin/env bash
set -euo pipefail

echo "=== [TP-VCS-001D] Setting up darcs-patch-index-prim ==="

PKG_DIR="packages/darcs-patch-index-prim"
mkdir -p "$PKG_DIR/src/Darcs/Repository/PatchIndex"
mkdir -p "$PKG_DIR/test"

cat << 'EOF' > "$PKG_DIR/darcs-patch-index-prim.cabal"
cabal-version:      3.0
name:               darcs-patch-index-prim
version:            0.1.0.0
synopsis:           Unboxed PrimArray Word64 Bitset & SmallArray Footprint Index
license:            BSD-3-Clause
author:             Nadia Yvette Chambers
maintainer:         nadia.yvette.chambers@ik.me
category:           Data, Development
build-type:         Simple

library
    exposed-modules:
        Darcs.Repository.PatchIndex.Prim
    build-depends:
        base >= 4.18 && < 5,
        containers >= 0.6 && < 0.9,
        primitive >= 0.8 && < 0.10,
        text >= 2.0 && < 3
    hs-source-dirs:   src
    default-language: GHC2021
    ghc-options:      -Wall -O2

test-suite darcs-patch-index-prim-test
    type:             exitcode-stdio-1.0
    main-is:          Main.hs
    hs-source-dirs:   test
    build-depends:
        base >= 4.18 && < 5,
        containers >= 0.6 && < 0.9,
        primitive >= 0.8 && < 0.10,
        text >= 2.0 && < 3,
        darcs-patch-index-prim
    default-language: GHC2021
    ghc-options:      -Wall -O2
EOF

cat << 'EOF' > "$PKG_DIR/src/Darcs/Repository/PatchIndex/Prim.hs"
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE OverloadedRecordDot #-}

module Darcs.Repository.PatchIndex.Prim
  ( Word64Bitset (..)
  , emptyBitset
  , fromSymbolIds
  , setBit64
  , testBit64
  , disjointBitset
  , unionBitset
  , PrimPatchIndex (..)
  , arePatchesParallelIndependent
  ) where

import Control.Monad (when)
import Control.Monad.ST (runST)
import Data.Bits ( bit, shiftR, (.&.), (.|.) )
import Data.Map.Strict (Map)
import Data.Primitive.PrimArray
import Data.Primitive.SmallArray
import Data.Text (Text)
import Data.Word (Word64)

-- | Unboxed bitset backed by a flat `PrimArray Word64`.
newtype Word64Bitset = Word64Bitset { unWord64Bitset :: PrimArray Word64 }
  deriving stock (Eq, Show)

emptyBitset :: Int -> Word64Bitset
emptyBitset numWords = runST $ do
  marr <- newPrimArray numWords
  setPrimArray marr 0 numWords 0
  Word64Bitset <$> unsafeFreezePrimArray marr

fromSymbolIds :: Int -> [Int] -> Word64Bitset
fromSymbolIds numWords symIds = runST $ do
  marr <- newPrimArray numWords
  setPrimArray marr 0 numWords 0
  mapM_ (\sid -> do
    let wIdx = sid `shiftR` 6
        bIdx = sid .&. 63
    if wIdx >= 0 && wIdx < numWords
      then do
        old <- readPrimArray marr wIdx
        writePrimArray marr wIdx (old .|. bit bIdx)
      else pure ()
    ) symIds
  Word64Bitset <$> unsafeFreezePrimArray marr

-- | Test if bit at index `i` is set in Word64Bitset.
testBit64 :: Word64Bitset -> Int -> Bool
testBit64 (Word64Bitset arr) bitIdx =
  let wIdx = bitIdx `shiftR` 6
      bIdx = bitIdx .&. 63
  in if wIdx >= 0 && wIdx < sizeofPrimArray arr
     then (indexPrimArray arr wIdx .&. bit bIdx) /= 0
     else False

-- | Set bit at index `i` in Word64Bitset.
setBit64 :: Word64Bitset -> Int -> Word64Bitset
setBit64 (Word64Bitset arr) bitIdx = runST $ do
  let wIdx = bitIdx `shiftR` 6
      bIdx = bitIdx .&. 63
      n = max (sizeofPrimArray arr) (wIdx + 1)
  marr <- newPrimArray n
  copyPrimArray marr 0 arr 0 (sizeofPrimArray arr)
  when (n > sizeofPrimArray arr) $
    setPrimArray marr (sizeofPrimArray arr) (n - sizeofPrimArray arr) 0
  when (wIdx >= 0 && wIdx < n) $ do
    old <- readPrimArray marr wIdx
    writePrimArray marr wIdx (old .|. bit bIdx)
  Word64Bitset <$> unsafeFreezePrimArray marr

-- | O(words) unboxed bitwise check: True iff two patches touch zero shared symbols/spans.
disjointBitset :: Word64Bitset -> Word64Bitset -> Bool
disjointBitset (Word64Bitset a) (Word64Bitset b) =
  let n = min (sizeofPrimArray a) (sizeofPrimArray b)
      go i
        | i >= n    = True
        | otherwise =
            ((indexPrimArray a i .&. indexPrimArray b i) == 0) && go (i + 1)
  in go 0

unionBitset :: Word64Bitset -> Word64Bitset -> Word64Bitset
unionBitset (Word64Bitset a) (Word64Bitset b) = runST $ do
  let n = max (sizeofPrimArray a) (sizeofPrimArray b)
  marr <- newPrimArray n
  let go i
        | i >= n = pure ()
        | otherwise = do
            let wa = if i < sizeofPrimArray a then indexPrimArray a i else 0
                wb = if i < sizeofPrimArray b then indexPrimArray b i else 0
            writePrimArray marr i (wa .|. wb)
            go (i + 1)
  go 0
  Word64Bitset <$> unsafeFreezePrimArray marr

-- | Flat patch footprint table indexed by dense PatchId
data PrimPatchIndex = PrimPatchIndex
  { ppiSymbolTable :: !(Map (FilePath, Text) Int)
  , ppiFootprints  :: !(SmallArray Word64Bitset)
  } deriving stock (Show)

arePatchesParallelIndependent :: PrimPatchIndex -> Int -> Int -> Bool
arePatchesParallelIndependent idx pid1 pid2
  | pid1 < 0 || pid2 < 0 = False
  | pid1 >= sizeofSmallArray idx.ppiFootprints = False
  | pid2 >= sizeofSmallArray idx.ppiFootprints = False
  | otherwise =
      disjointBitset
        (indexSmallArray idx.ppiFootprints pid1)
        (indexSmallArray idx.ppiFootprints pid2)
EOF

cat << 'EOF' > "$PKG_DIR/test/Main.hs"
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import qualified Data.Map.Strict as Map
import Data.Primitive.SmallArray (smallArrayFromList)
import System.Exit (exitFailure, exitSuccess)
import Darcs.Repository.PatchIndex.Prim

assert :: String -> Bool -> IO ()
assert name True  = putStrLn $ "  [PASS] " ++ name
assert name False = do
  putStrLn $ "  [FAIL] " ++ name
  exitFailure

main :: IO ()
main = do
  putStrLn "=== Running darcs-patch-index-prim unit tests ==="
  
  -- Test emptyBitset and disjointBitset
  let e4 = emptyBitset 4
  assert "empty bitset is disjoint with itself" (disjointBitset e4 e4)
  
  -- Test fromSymbolIds and testBit64
  let b1 = fromSymbolIds 4 [0, 63, 64, 127]
  assert "bit 0 is set in b1" (testBit64 b1 0)
  assert "bit 63 is set in b1" (testBit64 b1 63)
  assert "bit 64 is set in b1" (testBit64 b1 64)
  assert "bit 127 is set in b1" (testBit64 b1 127)
  assert "bit 1 is NOT set in b1" (not (testBit64 b1 1))
  assert "bit 65 is NOT set in b1" (not (testBit64 b1 65))
  
  -- Test setBit64
  let b2 = setBit64 (emptyBitset 2) 70
  assert "setBit64 sets bit 70" (testBit64 b2 70)
  assert "setBit64 preserves zero elsewhere" (not (testBit64 b2 69))
  
  -- Test disjointBitset
  let sA = fromSymbolIds 4 [1, 10, 100]
      sB = fromSymbolIds 4 [2, 20, 200]
      sC = fromSymbolIds 4 [10, 30]
  assert "sA and sB are disjoint" (disjointBitset sA sB)
  assert "sA and sC are NOT disjoint" (not (disjointBitset sA sC))
  assert "sB and sC are disjoint" (disjointBitset sB sC)
  
  -- Test unionBitset
  let sAB = unionBitset sA sB
  assert "sAB contains bits from sA" (testBit64 sAB 1 && testBit64 sAB 10 && testBit64 sAB 100)
  assert "sAB contains bits from sB" (testBit64 sAB 2 && testBit64 sAB 20 && testBit64 sAB 200)
  assert "sAB does not contain bit 30" (not (testBit64 sAB 30))
  
  -- Test PrimPatchIndex and arePatchesParallelIndependent
  let symMap = Map.fromList [(("src/Foo.hs", "foo"), 1), (("src/Bar.hs", "bar"), 10)]
      footprints = smallArrayFromList [sA, sB, sC]
      idx = PrimPatchIndex { ppiSymbolTable = symMap, ppiFootprints = footprints }
  
  assert "patch 0 and patch 1 are parallel independent" (arePatchesParallelIndependent idx 0 1)
  assert "patch 0 and patch 2 are NOT parallel independent" (not (arePatchesParallelIndependent idx 0 2))
  assert "patch 1 and patch 2 are parallel independent" (arePatchesParallelIndependent idx 1 2)
  assert "out of bounds patch index 3 returns False" (not (arePatchesParallelIndependent idx 0 3))
  assert "negative patch index returns False" (not (arePatchesParallelIndependent idx (-1) 0))
  
  putStrLn "=== All darcs-patch-index-prim tests PASSED! ==="
  exitSuccess
EOF

if ! grep -q "packages/darcs-patch-index-prim" cabal.project; then
    sed -i '/packages:/a \  packages/darcs-patch-index-prim' cabal.project
fi

echo "=== [TP-VCS-001D] Package setup complete ==="
