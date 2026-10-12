module Main where

import Test.Hspec

main :: IO ()
main = hspec $ do
  describe "Institution framework" $ do
    it "can compile" $ do
      True `shouldBe` True