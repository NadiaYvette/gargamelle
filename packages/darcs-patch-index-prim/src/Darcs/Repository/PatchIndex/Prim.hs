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
