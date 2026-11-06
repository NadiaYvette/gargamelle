{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Gargamelle.FOL.GaloisSeparator
  ( -- * Collision and Synthesis Types
    GaloisCollision (..)
  , SeparatorSynthesisResult (..)
    -- * Separator Synthesis Pipeline
  , synthesizeSeparator
  , tryTier1RelationalQualifier
  , tryTier2CatamorphicMeasure
  , evalTermValInModel
  , fallbackPointSeparator
    -- * Helpers
  , countCtor
  ) where

import Data.List (find)
import qualified Data.Map.Strict as Map
import Data.Maybe (mapMaybe)
import qualified Data.Set as Set

import Gargamelle.Core.Institution.Liquid

-- | A collision in the qualifier abstraction where a positive witness model
-- and a negative counterexample model satisfy the exact same qualifiers in the current basis.
data GaloisCollision = GaloisCollision
  { colPosModel :: LiquidModel
  , colNegModel :: LiquidModel
  } deriving stock (Eq, Ord, Show)

-- | Result of synthesizing a separator: either an existing relational qualifier,
-- or an invented catamorphic measure along with constructor axioms and a separating qualifier.
data SeparatorSynthesisResult = SeparatorSynthesisResult
  { sepNewMeasure :: Maybe MeasureDecl
  , sepNewAxioms  :: [CtorMeasureAxiom]
  , sepQualifier  :: Qualifier
  } deriving stock (Eq, Ord, Show)

-- | Synthesizes a separator for a Galois collision.
-- Attempts Tier 1 (relational qualifier over existing variables and measures),
-- then Tier 2 (catamorphic measure invention over differing ADT constructor frequencies),
-- and finally falls back to a point separator.
synthesizeSeparator :: LiquidSig -> GaloisCollision -> IO SeparatorSynthesisResult
synthesizeSeparator sig (GaloisCollision mPos mNeg) = do
  case tryTier1RelationalQualifier sig mPos mNeg of
    Just qual -> pure SeparatorSynthesisResult
      { sepNewMeasure = Nothing
      , sepNewAxioms  = []
      , sepQualifier  = qual
      }
    Nothing -> case tryTier2CatamorphicMeasure sig mPos mNeg of
      Just res -> pure res
      Nothing  -> pure $ fallbackPointSeparator mPos mNeg

-- | Evaluates a ground or model-bound LiquidPred term in a LiquidModel.
evalTermValInModel :: LiquidModel -> LiquidPred -> Maybe LiquidVal
evalTermValInModel LiquidModel{..} = \case
  PTrue -> Just (VBool True)
  PFalse -> Just (VBool False)
  PIntLit n -> Just (VInt n)
  PEmptySet _ -> Just (VSet Set.empty)
  PVar v -> Map.lookup v modelVarEnv
  PMeasureApp m argPred -> do
    argVal <- evalTermValInModel LiquidModel{..} argPred
    Map.lookup (m, argVal) modelMeasureInterp
  PFieldProj f recPred -> do
    val <- evalTermValInModel LiquidModel{..} recPred
    case val of
      VRecord fields -> Map.lookup f fields
      _              -> Nothing
  PVariantTag tag varPred -> do
    val <- evalTermValInModel LiquidModel{..} varPred
    case val of
      VVariant actualTag _ -> Just (VBool (actualTag == tag))
      _                    -> Nothing
  PBinOp op l r -> do
    vl <- evalTermValInModel LiquidModel{..} l
    vr <- evalTermValInModel LiquidModel{..} r
    evalBinOp op vl vr
  PRel op l r -> do
    vl <- evalTermValInModel LiquidModel{..} l
    vr <- evalTermValInModel LiquidModel{..} r
    evalRelOp op vl vr
  PNot p -> do
    val <- evalTermValInModel LiquidModel{..} p
    case val of
      VBool b -> Just (VBool (not b))
      _       -> Nothing
  PAnd ps -> do
    vs <- traverse (evalTermValInModel LiquidModel{..}) ps
    bools <- traverse expectBool vs
    pure (VBool (and bools))
  POr ps -> do
    vs <- traverse (evalTermValInModel LiquidModel{..}) ps
    bools <- traverse expectBool vs
    pure (VBool (or bools))
  PImplies l r -> do
    vl <- evalTermValInModel LiquidModel{..} l >>= expectBool
    vr <- evalTermValInModel LiquidModel{..} r >>= expectBool
    pure (VBool (not vl || vr))
  PIff l r -> do
    vl <- evalTermValInModel LiquidModel{..} l >>= expectBool
    vr <- evalTermValInModel LiquidModel{..} r >>= expectBool
    pure (VBool (vl == vr))
  PLiquidHole holeId _ ->
    case Map.lookup holeId modelAbductSol of
      Just solPred -> evalTermValInModel LiquidModel{..} solPred
      Nothing      -> Nothing
  where
    expectBool (VBool b) = Just b
    expectBool _         = Nothing

    evalBinOp Add (VInt a) (VInt b) = Just (VInt (a + b))
    evalBinOp Sub (VInt a) (VInt b) = Just (VInt (a - b))
    evalBinOp Mul (VInt a) (VInt b) = Just (VInt (a * b))
    evalBinOp SetUnion (VSet a) (VSet b) = Just (VSet (Set.union a b))
    evalBinOp SetIntersect (VSet a) (VSet b) = Just (VSet (Set.intersection a b))
    evalBinOp SetDiff (VSet a) (VSet b) = Just (VSet (Set.difference a b))
    evalBinOp _ _ _ = Nothing

    evalRelOp Eq a b = Just (VBool (a == b))
    evalRelOp Neq a b = Just (VBool (a /= b))
    evalRelOp Lt (VInt a) (VInt b) = Just (VBool (a < b))
    evalRelOp Le (VInt a) (VInt b) = Just (VBool (a <= b))
    evalRelOp Gt (VInt a) (VInt b) = Just (VBool (a > b))
    evalRelOp Ge (VInt a) (VInt b) = Just (VBool (a >= b))
    evalRelOp SetMember a (VSet s) = Just (VBool (Set.member a s))
    evalRelOp SetSubset (VSet a) (VSet b) = Just (VBool (Set.isSubsetOf a b))
    evalRelOp _ _ _ = Nothing

-- | Tier 1: Relational qualifier synthesis over scalar variables and existing measures.
-- Evaluates candidate depth-1 scalar expressions and existing measures on M+ and M-
-- to find an ordering (e.g., v > c, v <= c, v1 < v2) or equality that holds on M+ and is false on M-.
tryTier1RelationalQualifier :: LiquidSig -> LiquidModel -> LiquidModel -> Maybe Qualifier
tryTier1RelationalQualifier LiquidSig{..} mPos mNeg =
  find separates candidateQuals
  where
    -- Collect candidate integer terms: variables and unary measure applications
    varNames = Map.keys (modelVarEnv mPos)
    measNames = Map.keys sigMeasures

    baseTerms :: [(LiquidPred, LiquidSort)]
    baseTerms =
      [ (PVar v, SortInt) | v <- varNames ]
      ++ [ (PMeasureApp m (PVar v), SortInt) | m <- measNames, v <- varNames ]

    -- Build candidate predicates
    candidatePreds :: [LiquidPred]
    candidatePreds = concatMap mkPredsForTerm baseTerms

    mkPredsForTerm :: (LiquidPred, LiquidSort) -> [LiquidPred]
    mkPredsForTerm (term, SortInt) =
      let valPos = evalTermValInModel mPos term
          valNeg = evalTermValInModel mNeg term
      in case (valPos, valNeg) of
        (Just (VInt posI), Just (VInt negI)) ->
          if posI > negI
            then [ PRel Gt term (PIntLit negI)
                 , PRel Ge term (PIntLit posI)
                 , PRel Eq term (PIntLit posI)
                 ]
            else if posI < negI
              then [ PRel Lt term (PIntLit negI)
                   , PRel Le term (PIntLit posI)
                   , PRel Eq term (PIntLit posI)
                   ]
              else []
        _ -> []
    mkPredsForTerm _ = []

    candidateQuals :: [Qualifier]
    candidateQuals =
      [ Qualifier
          { qualName   = "Q_sep_tier1"
          , qualParams = []
          , qualBody   = predExpr
          }
      | predExpr <- candidatePreds
      ]

    separates qual =
      case (evalTermValInModel mPos (qualBody qual), evalTermValInModel mNeg (qualBody qual)) of
        (Just (VBool True), Just (VBool False)) -> True
        _                                       -> False

-- | Helper to count occurrences of a constructor in an ADT value tree.
countCtor :: SymName -> LiquidVal -> Integer
countCtor targetCtor = \case
  VADT ctor args ->
    let here = if ctor == targetCtor then 1 else 0
        recCount = sum (map (countCtor targetCtor) args)
    in here + recCount
  _ -> 0

-- | Tier 2: Catamorphic measure invention over differing ADT constructor frequencies.
-- Inspects ADT values in M+ and M- that differ in constructor counts (or variant tags),
-- and synthesizes a new catamorphic measure (e.g., count_Ctor) and separating qualifier.
tryTier2CatamorphicMeasure :: LiquidSig -> LiquidModel -> LiquidModel -> Maybe SeparatorSynthesisResult
tryTier2CatamorphicMeasure _sig mPos mNeg =
  findDifferingADT (Map.toList (modelVarEnv mPos))
  where
    findDifferingADT [] = Nothing
    findDifferingADT ((v, valPos@(VADT posCtor _)):rest) =
      case Map.lookup v (modelVarEnv mNeg) of
        Just valNeg@(VADT negCtor _) ->
          let ctorToCount = if posCtor /= negCtor then posCtor else "Cons"
              cPos = countCtor ctorToCount valPos
              cNeg = countCtor ctorToCount valNeg
          in if cPos /= cNeg
               then Just $ mkCountResult v ctorToCount cPos cNeg
               else findDifferingADT rest
        _ -> findDifferingADT rest
    findDifferingADT (_:rest) = findDifferingADT rest

    mkCountResult varName ctor cPos cNeg =
      let mName = "count_" <> ctor
          measure = MeasureDecl
            { measureName        = mName
            , measureDomain      = SortADT "Tree" []
            , measureRange       = SortInt
            , measureWellFounded = True
            }
          axioms =
            [ CtorMeasureAxiom
                { axiomCtor    = ctor
                , axiomParams  = [("x", SortInt), ("xs", SortADT "Tree" [])]
                , axiomMeasure = mName
                , axiomBody    = PBinOp Add (PIntLit 1) (PMeasureApp mName (PVar "xs"))
                }
            , CtorMeasureAxiom
                { axiomCtor    = "Nil"
                , axiomParams  = []
                , axiomMeasure = mName
                , axiomBody    = PIntLit 0
                }
            ]
          term = PMeasureApp mName (PVar varName)
          qualBody =
            if cPos > cNeg
              then PRel Gt term (PIntLit cNeg)
              else PRel Lt term (PIntLit cNeg)
          qual = Qualifier
            { qualName   = "Q_sep_tier2_" <> mName
            , qualParams = []
            , qualBody   = qualBody
            }
      in SeparatorSynthesisResult
          { sepNewMeasure = Just measure
          , sepNewAxioms  = axioms
          , sepQualifier  = qual
          }

-- | Fallback point separator that discriminates M+ from M- by asserting exact variable valuations.
fallbackPointSeparator :: LiquidModel -> LiquidModel -> SeparatorSynthesisResult
fallbackPointSeparator mPos _mNeg =
  let equalities = mapMaybe mkEq (Map.toList (modelVarEnv mPos))
      body = case equalities of
        []  -> PTrue
        [e] -> e
        es  -> PAnd es
      qual = Qualifier
        { qualName   = "Q_point_sep"
        , qualParams = []
        , qualBody   = body
        }
  in SeparatorSynthesisResult
      { sepNewMeasure = Nothing
      , sepNewAxioms  = []
      , sepQualifier  = qual
      }
  where
    mkEq (v, VInt n)  = Just (PRel Eq (PVar v) (PIntLit n))
    mkEq (v, VBool b) = Just (PRel Eq (PVar v) (if b then PTrue else PFalse))
    mkEq _            = Nothing
