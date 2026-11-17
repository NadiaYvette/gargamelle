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
       Just (q' :> p') ->
         case commute (q' :> p') of
           Just (TestDelta a' :> TestDelta b') -> a' == a && b' == b
           Nothing                             -> False
       Nothing -> False

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
