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
