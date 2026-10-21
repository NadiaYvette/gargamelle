module Main (main) where

import Test.Hspec
import Data.Functor.Contravariant (contramap)
import Data.Functor.Contravariant.Divisible (conquer, divide, choose)
import Gargamelle.Model.Satisfaction
import Gargamelle.Model.Structure

main :: IO ()
main = hspec $ do
  describe "Gargamelle.Model.Satisfaction (Evidence Monoid)" $ do
    -- See Note [Free Verifier AST and Algebraic Counterexample Evidence] [ref:note-free-verifier-ast]
    it "treats VerifiedSection as identity" $ do
      let v = VerifiedSection
      let c = Counterexample "sym" "witness"
      (v <> c) `shouldBe` c
      (c <> v) `shouldBe` c
      (mempty :: Evidence) `shouldBe` VerifiedSection

    it "accumulates multiple counterexamples" $ do
      let c1 = Counterexample "boundCheck" "x > 10"
      let c2 = Counterexample "typeCheck" "expected Int"
      let acc = c1 <> c2
      case acc of
        Counterexample sym payload -> do
          sym `shouldBe` "boundCheck; typeCheck"
          payload `shouldBe` "x > 10 | expected Int"
        VerifiedSection -> expectationFailure "Expected Counterexample, got VerifiedSection"

  describe "Gargamelle.Model.Satisfaction (Free Verifier AST)" $ do
    -- See Note [Free Verifier AST and Algebraic Counterexample Evidence] [ref:note-free-verifier-ast]
    it "evaluates conquer as universally verified" $ do
      let v = conquer :: Verifier Int
      evalVerifier v 42 `shouldBe` VerifiedSection

    it "evaluates atomic predicates" $ do
      let v = verifyPredicate "isPositive" (> (0 :: Int))
      evalVerifier v 5 `shouldBe` VerifiedSection
      evalVerifier v (-2) `shouldBe` Counterexample "isPositive" "Predicate violated: isPositive"

    it "composes verifiers across products via Divisible divide" $ do
      let vInt = verifyPredicate "pos" (> (0 :: Int))
      let vStr = verifyPredicate "nonEmpty" (not . null :: String -> Bool)
      let vPair = divide id vInt vStr
      evalVerifier vPair (5, "hello") `shouldBe` VerifiedSection
      evalVerifier vPair (-1, "hello") `shouldBe` Counterexample "pos" "Predicate violated: pos"
      evalVerifier vPair (5, "") `shouldBe` Counterexample "nonEmpty" "Predicate violated: nonEmpty"
      -- Both failing accumulates counterexamples
      case evalVerifier vPair (-1, "") of
        Counterexample sym _ -> sym `shouldBe` "pos; nonEmpty"
        VerifiedSection -> expectationFailure "Expected Counterexample, got VerifiedSection"

    it "composes verifiers across sums via Decidable choose" $ do
      let vInt = verifyPredicate "even" (\n -> (n `mod` (2 :: Int)) == 0)
      let vStr = verifyPredicate "validTag" (== "OK")
      let vEither = choose id vInt vStr
      evalVerifier vEither (Left 4 :: Either Int String) `shouldBe` VerifiedSection
      evalVerifier vEither (Left 3 :: Either Int String) `shouldBe` Counterexample "even" "Predicate violated: even"
      evalVerifier vEither (Right "OK" :: Either Int String) `shouldBe` VerifiedSection
      evalVerifier vEither (Right "ERR" :: Either Int String) `shouldBe` Counterexample "validTag" "Predicate violated: validTag"

    it "supports contravariant pre-composition" $ do
      let vLength = verifyPredicate "short" (<= (5 :: Int))
      let vStrLength = contramap length vLength
      evalVerifier vStrLength "abc" `shouldBe` VerifiedSection
      evalVerifier vStrLength "abcdefgh" `shouldBe` Counterexample "short" "Predicate violated: short"

    it "provides 100% static inspection of the verification plan" $ do
      let v1 = verifyPredicate "pos" (> (0 :: Int))
      let v2 = verifyPredicate "nonEmpty" (not . null :: String -> Bool)
      let vPair = divide id v1 v2
      inspectVerifierPlan vPair `shouldBe` ["Step:divide", "AtomCheck:pos", "AtomCheck:nonEmpty"]

  describe "Gargamelle.Model.Structure" $ do
    -- See Note [Universal LogicModel Sorting and Product Splittings] [ref:note-logic-model-sorting]
    it "evaluates compilePairVerifier and compileEitherVerifier helpers" $ do
      let vA = verifyPredicate "gtZero" (> (0 :: Int))
      let vB = verifyPredicate "gtTen" (> (10 :: Int))
      let vPair = compilePairVerifier vA vB
      evalVerifier vPair (1, 20) `shouldBe` VerifiedSection
      let vEither = compileEitherVerifier vA vB
      evalVerifier vEither (Left 2) `shouldBe` VerifiedSection
      evalVerifier vEither (Right 5) `shouldBe` Counterexample "gtTen" "Predicate violated: gtTen"
