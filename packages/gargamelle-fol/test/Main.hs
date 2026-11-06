{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Main (main) where

import Test.Hspec
import Data.Proxy (Proxy(..))
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set

import qualified FirstOrder as FO
import qualified Hyperdoctrine as HD
import qualified RefinementCalculus as RC
import Gargamelle.FOL.Z3
import Gargamelle.FOL.LiquidBridge
import Gargamelle.FOL.PenelopeBridge
import Gargamelle.FOL.LiquidHyperdoctrine
import Gargamelle.FOL.GaloisSeparator
import Gargamelle.Core.Institution.Liquid
import Gargamelle.Core.Institution.Liquid.Penelope
import Gargamelle.Model.Satisfaction (Evidence(..))
import qualified Institution as Legacy

main :: IO ()
main = hspec do
  describe "Native FirstOrder Logic" do
    it "evaluates closed first-order formula under a concrete model" do
      let pVar = FO.Pred (Proxy @"p") []
          qVar = FO.Pred (Proxy @"q") []
          formula = FO.And pVar (FO.Not qVar)
          model = FO.FOLModel
            { FO.predicateInterpretation = Map.fromList [("p", Set.singleton []), ("q", Set.empty)]
            , FO.functionInterpretation  = Map.empty
            , FO.constants               = Set.empty
            }
      Legacy.satisfies (Proxy @(FO.FOLSig '["p", "q"])) model formula `shouldBe` True

    it "evaluates universal quantifiers over Herbrand constants" do
      let xVar = FO.var "x"
          predP = FO.Pred (Proxy @"P") [xVar]
          formula = FO.Forall (Proxy @"x") predP
          model = FO.FOLModel
            { FO.predicateInterpretation = Map.fromList [("P", Set.fromList [["c1"], ["c2"]])]
            , FO.functionInterpretation  = Map.empty
            , FO.constants               = Set.fromList ["c1", "c2"]
            }
      Legacy.satisfies (Proxy @(FO.FOLSig '["P"])) model formula `shouldBe` True

  -- Tested against Note [Streaming Z3 SMT-LIB2 Piping and Model Extraction] [ref:note-z3-smt-pipe-extraction]
  describe "Gargamelle.FOL.Z3 SMT-LIB2 Pipe" do
    it "solves satisfiable formula and extracts model assignments" do
      let pVar = FO.Pred (Proxy @"p") []
          qVar = FO.Pred (Proxy @"q") []
          formula = FO.And pVar (FO.Not qVar)
      res <- checkFormulaZ3 formula
      case res of
        Sat model -> do
          Map.lookup "p" model `shouldBe` Just "true"
          Map.lookup "q" model `shouldBe` Just "false"
        _ -> expectationFailure ("Expected Sat, but got: " ++ show res)

    it "identifies unsatisfiable formula as Unsat" do
      let pVar = FO.Pred (Proxy @"p") []
          formula = FO.And pVar (FO.Not pVar)
      res <- checkFormulaZ3 formula
      res `shouldBe` Unsat

    it "formally verifies tautological validity returning VerifiedSection" do
      -- Law of excluded middle: p \/ (not p) is universally valid
      let pVar = FO.Pred (Proxy @"p") []
          tautology = FO.Or pVar (FO.Not pVar)
      evidence <- verifyValidityZ3 tautology
      evidence `shouldBe` VerifiedSection

    it "detects countermodel when verifying non-valid formula" do
      -- p /\ q is not valid (counterexample exists where p=false)
      let pVar = FO.Pred (Proxy @"p") []
          qVar = FO.Pred (Proxy @"q") []
          nonTautology = FO.And pVar qVar
      evidence <- verifyValidityZ3 nonTautology
      case evidence of
        Counterexample sym _ -> sym `shouldBe` "Z3-Countermodel"
        VerifiedSection      -> expectationFailure "Expected counterexample for non-valid formula"

  -- Tested against Note [Categorical Hyperdoctrine Quantifier Adjunctions] [ref:note-hyperdoctrine-adjunctions]
  describe "Hyperdoctrine & Refinement Calculus" do
    it "evaluates hyperdoctrine context satisfaction" do
      let pVar = FO.Pred (Proxy @"p") []
          model = FO.FOLModel
            { FO.predicateInterpretation = Map.fromList [("p", Set.singleton [])]
            , FO.functionInterpretation  = Map.empty
            , FO.constants               = Set.empty
            }
      Legacy.satisfies (Proxy @(HD.HDCSig '["p"])) model pVar `shouldBe` True

    it "evaluates specification refinement (Spec1 ⊑ Spec2)" do
      let pre1 = FO.Pred (Proxy @"preA") []
          post1 = FO.Pred (Proxy @"postA") []
          pre2 = FO.Pred (Proxy @"preB") []
          post2 = FO.Pred (Proxy @"postB") []
          spec1 = RC.spec pre1 post1
          spec2 = RC.spec pre2 post2
          refinement = RC.refine spec1 spec2
          -- For spec1 to refine spec2: pre2 => pre1 and post1 => post2
          -- We set up a model where pre1, pre2, post1, post2 all hold
          model = FO.FOLModel
            { FO.predicateInterpretation = Map.fromList
                [ ("preA", Set.singleton [])
                , ("postA", Set.singleton [])
                , ("preB", Set.singleton [])
                , ("postB", Set.singleton [])
                ]
            , FO.functionInterpretation  = Map.empty
            , FO.constants               = Set.empty
            }
      Legacy.satisfies (Proxy @(RC.RCSig '["preA", "postA", "preB", "postB"])) model refinement `shouldBe` True

  describe "Gargamelle.FOL.LiquidBridge & PenelopeBridge" do
    let emptySig = LiquidSig
          { sigSorts      = Set.empty
          , sigMeasures   = Map.empty
          , sigCtorAxioms = []
          , sigQualifiers = Set.empty
          , sigEnv        = Map.empty
          , sigPathCond   = []
          }

    it "validates tautological liquid subtyping obligations (x > 0 <: x >= 0)" do
      let sen = SenSubtype
            { subValueVar = "x"
            , subSort     = SortInt
            , subLhs      = PRel Gt (PVar "x") (PIntLit 0)
            , subRhs      = PRel Ge (PVar "x") (PIntLit 0)
            }
      res <- checkLiquidSubtypingZ3 emptySig sen
      res `shouldBe` SubtypeValid

    it "rejects non-subtypes and produces counterexample model (x >= 0 </: x > 0)" do
      let sen = SenSubtype
            { subValueVar = "x"
            , subSort     = SortInt
            , subLhs      = PRel Ge (PVar "x") (PIntLit 0)
            , subRhs      = PRel Gt (PVar "x") (PIntLit 0)
            }
      res <- checkLiquidSubtypingZ3 emptySig sen
      case res of
        SubtypeRejected (LiquidModel varEnv _ _) -> do
          Map.lookup "x" varEnv `shouldBe` Just (VInt 0)
        SubtypeValid -> expectationFailure "Expected SubtypeRejected for non-subtype"

    it "abducts branch guard condition from qualifiers" do
      let qualXPos = Qualifier
            { qualName   = "Q_pos"
            , qualParams = [("n", SortInt)]
            , qualBody   = PRel Gt (PVar "n") (PIntLit 0)
            }
          sig = emptySig { sigQualifiers = Set.singleton qualXPos }
          goal = PRel Ge (PVar "x") (PIntLit 0)
      mGuard <- abductConditionZ3 sig ["x"] goal
      mGuard `shouldBe` Just (PRel Gt (PVar "x") (PIntLit 0))

    it "verifies Penelope effect resource budget bounds via verifyEffectBudgetZ3" do
      let effType = EffectType
            { effOpName     = "consumeFuel"
            , effOpParams   = []
            , effOpResult   = SortInt
            , effOpPreCond  = PRel Gt (PVar "fuel") (PIntLit 0)
            , effOpPostCond = PRel Ge (PVar "fuel") (PIntLit 1)
            }
      valid <- verifyEffectBudgetZ3 emptySig effType
      valid `shouldBe` True

    it "rejects invalid Penelope effect resource budget bounds" do
      let effTypeInvalid = EffectType
            { effOpName     = "badFuel"
            , effOpParams   = []
            , effOpResult   = SortInt
            , effOpPreCond  = PRel Ge (PVar "fuel") (PIntLit 0)
            , effOpPostCond = PRel Gt (PVar "fuel") (PIntLit 5)
            }
      valid <- verifyEffectBudgetZ3 emptySig effTypeInvalid
      valid `shouldBe` False

  describe "Gargamelle.FOL.LiquidHyperdoctrine with Galois Adjoints" do
    let ctx = Context (Map.singleton "x" SortInt)
        qualPos = Qualifier "Q_pos" [("n", SortInt)] (PRel Gt (PVar "n") (PIntLit 0))
        qualNonNeg = Qualifier "Q_nonneg" [("n", SortInt)] (PRel Ge (PVar "n") (PIntLit 0))
        basis = QualifierBasis (Set.fromList [qualPos, qualNonNeg])

    it "verifies left Galois adjunction law: phi => i(q) entails alpha^strong(phi) <= q" do
      -- Let phi be x > 5. In context {x : Int}, phi entails both x > 0 and x >= 0.
      -- So alpha^strong(phi) will contain both {x > 0, x >= 0}.
      -- If q is {x >= 0}, then phi entails i(q).
      -- In the subset lattice of conjuncts (ordering where stronger = larger subset of conjuncts),
      -- alpha^strong(phi) contains all conjuncts entailed by phi, hence q is a subset of alpha^strong(phi),
      -- which means alpha^strong(phi) <= q in the dual / logical implication order:
      -- i(alpha^strong(phi)) entails i(q), and as sets of conjuncts, q is a subset of qcConjuncts alpha^strong(phi).
      let phi = FAtom (PRel Gt (PVar "x") (PIntLit 5))
          q = QualifierConj (Set.singleton (PRel Ge (PVar "x") (PIntLit 0)))
      -- 1. Check phi entails i(q)
      hyp <- entails @Z3Hyperdoctrine ctx phi (embedQualifier @Z3Hyperdoctrine q)
      hyp `shouldBe` True

      -- 2. Compute alpha^strong(phi)
      alphaStrong <- strongGaloisConsequence @Z3Hyperdoctrine ctx basis phi
      -- Conjuncts of q must be a subset of alphaStrong conjuncts
      Set.isSubsetOf (qcConjuncts q) (qcConjuncts alphaStrong) `shouldBe` True

    it "verifies right Galois adjunction law: i(q) => psi entails q <= alpha^weak(psi)" do
      -- Let psi be x >= 0.
      -- If q is {x > 0}, then i(q) = (x > 0) entails psi = (x >= 0).
      -- weakGaloisImplicant finds a valid implicant q_weak such that i(q_weak) entails psi.
      let psi = FAtom (PRel Ge (PVar "x") (PIntLit 0))
          q = QualifierConj (Set.singleton (PRel Gt (PVar "x") (PIntLit 0)))
      -- 1. Check i(q) entails psi
      premise <- entails @Z3Hyperdoctrine ctx (embedQualifier @Z3Hyperdoctrine q) psi
      premise `shouldBe` True

      -- 2. Compute alpha^weak(psi)
      mAlphaWeak <- weakGaloisImplicant @Z3Hyperdoctrine ctx basis psi
      case mAlphaWeak of
        Nothing -> expectationFailure "Expected weakGaloisImplicant to find a candidate"
        Just alphaWeak -> do
          -- Both i(q) and i(alphaWeak) entail psi
          valid <- entails @Z3Hyperdoctrine ctx (embedQualifier @Z3Hyperdoctrine alphaWeak) psi
          valid `shouldBe` True

  describe "Gargamelle.FOL.GaloisSeparator for Meta-Abduction" do
    let emptySig = LiquidSig
          { sigSorts      = Set.empty
          , sigMeasures   = Map.empty
          , sigCtorAxioms = []
          , sigQualifiers = Set.empty
          , sigEnv        = Map.empty
          , sigPathCond   = []
          }

    it "separates models with differing integer values via tryTier1RelationalQualifier" do
      let mPos = LiquidModel
            { modelVarEnv        = Map.singleton "x" (VInt 10)
            , modelMeasureInterp = Map.empty
            , modelAbductSol     = Map.empty
            }
          mNeg = LiquidModel
            { modelVarEnv        = Map.singleton "x" (VInt 2)
            , modelMeasureInterp = Map.empty
            , modelAbductSol     = Map.empty
            }
      case tryTier1RelationalQualifier emptySig mPos mNeg of
        Nothing -> expectationFailure "Expected Tier 1 relational qualifier to separate models"
        Just qual -> do
          evalTermValInModel mPos (qualBody qual) `shouldBe` Just (VBool True)
          evalTermValInModel mNeg (qualBody qual) `shouldBe` Just (VBool False)

    it "invents a catamorphic measure separating distinct ADT structures via tryTier2CatamorphicMeasure" do
      -- Model + has a list [1, 2] represented as Cons(1, Cons(2, Nil))
      -- Model - has a list [1] represented as Cons(1, Nil)
      let treePos = VADT "Cons" [VInt 1, VADT "Cons" [VInt 2, VADT "Nil" []]]
          treeNeg = VADT "Cons" [VInt 1, VADT "Nil" []]
          mPos = LiquidModel
            { modelVarEnv        = Map.singleton "t" treePos
            , modelMeasureInterp = Map.empty
            , modelAbductSol     = Map.empty
            }
          mNeg = LiquidModel
            { modelVarEnv        = Map.singleton "t" treeNeg
            , modelMeasureInterp = Map.empty
            , modelAbductSol     = Map.empty
            }
      case tryTier2CatamorphicMeasure emptySig mPos mNeg of
        Nothing -> expectationFailure "Expected Tier 2 catamorphic measure invention to separate models"
        Just SeparatorSynthesisResult{..} -> do
          case sepNewMeasure of
            Nothing -> expectationFailure "Expected new measure declaration"
            Just m  -> measureName m `shouldBe` "count_Cons"
          length sepNewAxioms `shouldBe` 2
          -- Check qualifier body separates
          -- For mPos, count_Cons is 2, for mNeg count_Cons is 1
          -- Qual body is PRel Gt (PMeasureApp "count_Cons" (PVar "t")) (PIntLit 1)
          let mPosInterp = mPos
                { modelMeasureInterp = Map.fromList
                    [ (("count_Cons", treePos), VInt 2)
                    , (("count_Cons", treeNeg), VInt 1)
                    ]
                }
              mNegInterp = mNeg
                { modelMeasureInterp = Map.fromList
                    [ (("count_Cons", treePos), VInt 2)
                    , (("count_Cons", treeNeg), VInt 1)
                    ]
                }
          evalTermValInModel mPosInterp (qualBody sepQualifier) `shouldBe` Just (VBool True)
          evalTermValInModel mNegInterp (qualBody sepQualifier) `shouldBe` Just (VBool False)

    it "synthesizes separator end-to-end via synthesizeSeparator" do
      let mPos = LiquidModel
            { modelVarEnv        = Map.singleton "v" (VInt 42)
            , modelMeasureInterp = Map.empty
            , modelAbductSol     = Map.empty
            }
          mNeg = LiquidModel
            { modelVarEnv        = Map.singleton "v" (VInt 0)
            , modelMeasureInterp = Map.empty
            , modelAbductSol     = Map.empty
            }
          collision = GaloisCollision mPos mNeg
      res <- synthesizeSeparator emptySig collision
      evalTermValInModel mPos (qualBody (sepQualifier res)) `shouldBe` Just (VBool True)
      evalTermValInModel mNeg (qualBody (sepQualifier res)) `shouldBe` Just (VBool False)


