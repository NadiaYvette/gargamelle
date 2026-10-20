{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main (main) where

import Test.Hspec
import Control.Arrow (Kleisli(..), arr)
import Control.Category ((.))
import Prelude hiding ((.))
import Data.Functor.Identity (Identity(..))
import Data.Primitive.SmallArray (smallArrayFromList)
import qualified Data.Text as T
import GHC.Exts (Any)
import Unsafe.Coerce (unsafeCoerce)

import Effect.Rope
import Effect.Handlers
import Gargamelle.Effect.Router
import Gargamelle.Effect.Optics
import Gargamelle.Effect.Fusion
import Polytropos (Record, Variant)
import Polytropos.Core (Rep(..), RowRep(..))

main :: IO ()
main = hspec do
  describe "Gargamelle.Effect.Router (O(1) Variant Jump Table)" do
    it "dispatches open variants directly through the O(1) jump table" do
      -- Define 3 handlers corresponding to tags 0, 1, 2
      let handler0 rep = Kleisli \_ -> pure ("Tag0: " ++ getSlot 0 rep :: String)
          handler1 rep = Kleisli \_ -> pure ("Tag1: " ++ show (getSlot 0 rep :: Int))
          handler2 _rep = Kleisli \_ -> pure ("Tag2: empty" :: String)
          router = makeRouter [handler0, handler1, handler2]

      routerSize router `shouldBe` 3

      -- Variant with tag 0 and string payload
      let var0 :: Variant '[] = RowRep (Rep 0 (smallArrayFromList [Identity (unsafeCoerce ("hello" :: String) :: Any)]))
          act0 = routeVariant router var0
      res0 <- runKleisli act0 ()
      res0 `shouldBe` "Tag0: hello"

      -- Variant with tag 1 and int payload
      let var1 :: Variant '[] = RowRep (Rep 1 (smallArrayFromList [Identity (unsafeCoerce (42 :: Int) :: Any)]))
          act1 = routeVariant router var1
      res1 <- runKleisli act1 ()
      res1 `shouldBe` "Tag1: 42"

    it "integrates variant router into Kernmantle Rope pipeline" do
      let router = makeRouter
            [ \rep -> Kleisli \_ -> Right (getSlot 0 rep :: Int)
            ]
          var :: Variant '[] = RowRep (Rep 0 (smallArrayFromList [Identity (unsafeCoerce (100 :: Int) :: Any)]))
          rope = routeVariantRope router var
      case runKleisli (runRope rope pureMockHandlers) () of
        Right res -> res `shouldBe` 100
        Left err  -> expectationFailure (T.unpack err)

  describe "Gargamelle.Effect.Optics (Profunctor Lenses & Prisms)" do
    it "views and updates open record field slots in-place" do
      -- Record with two slots: [0: "Alice", 1: 30 :: Int]
      let p0 = Identity (unsafeCoerce ("Alice" :: String) :: Any)
          p1 = Identity (unsafeCoerce (30 :: Int) :: Any)
          rec0 :: Record '[] = RowRep (Rep 0 (smallArrayFromList [p0, p1]))

      view (typedSlotLens 0) rec0 `shouldBe` ("Alice" :: String)
      view (typedSlotLens 1) rec0 `shouldBe` (30 :: Int)

      -- Update name using set
      let rec1 = set (typedSlotLens 0) ("Bob" :: String) rec0
      view (typedSlotLens 0) rec1 `shouldBe` ("Bob" :: String)
      view (typedSlotLens 1) rec1 `shouldBe` (30 :: Int)

      -- Update age using over
      let rec2 = over (typedSlotLens 1) (+ (1 :: Int)) rec1
      view (typedSlotLens 1) rec2 `shouldBe` (31 :: Int)

    it "projects and matches open variant constructors via prisms" do
      let var0 = RowRep (Rep 0 (smallArrayFromList [Identity (unsafeCoerce ("payload" :: String) :: Any)])) :: Variant '[]
      preview (typedVariantPrism 0) var0 `shouldBe` (Just "payload" :: Maybe String)
      preview (typedVariantPrism 1 :: Prism' (Variant '[]) Int) var0 `shouldBe` Nothing

  describe "Gargamelle.Effect.Fusion (Coyoneda Pipeline Fusion)" do
    it "fuses multiple intermediate mappings into a single pass" do
      let initialVal = Just (10 :: Int)
          fused = fuseMap (+ 5) (fuseMap (* 2) (fuseMap (+ 3) (liftCoyoneda initialVal)))
      -- ((10 + 3) * 2) + 5 = 26 + 5 = 31
      runFused fused `shouldBe` Just 31

    it "fuses pure post-processing transformations onto Rope pipelines" do
      let baseRope = ropeFromCore (arr (\(x :: Int) -> x * 2))
          fusedRope = fuseRope (fuseRopeMap (+ 10) (fuseRopeMap (+ 5) (liftCoyoneda baseRope)))
      case runKleisli (runRope fusedRope pureMockHandlers) (10 :: Int) of
        Right res -> res `shouldBe` 35
        Left err  -> expectationFailure (T.unpack err)

  describe "Kernmantle Rope Backward Compatibility" do
    it "executes standard strands under pure mock handlers" do
      let pipeline = getRandomWordRope . logInfoRope "initializing"
      case runKleisli (runRope pipeline pureMockHandlers) () of
        Right res -> res `shouldBe` 42
        Left err  -> expectationFailure (T.unpack err)
