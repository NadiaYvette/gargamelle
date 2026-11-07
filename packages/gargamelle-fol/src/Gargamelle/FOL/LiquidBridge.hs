{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Gargamelle.FOL.LiquidBridge
  ( SubtypeResult (..)
  , lowerSigToFOL
  , lowerSentenceToNegatedFOL
  , liquidPredToSMTLib
  , checkLiquidSubtypingZ3
  , abductConditionZ3
  ) where

import Data.Char (isDigit)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as T

import Gargamelle.Core.Institution.Liquid
import Gargamelle.Core.Institution.Liquid.Instance (extractEnvAssumptions)
import Gargamelle.FOL.Z3 (SMTResult (..), solveZ3Raw)

-- | Result of a liquid subtyping verification query.
data SubtypeResult
  = SubtypeValid
  | SubtypeRejected LiquidModel
  deriving (Eq, Show)

-- | Convert a LiquidSort to an SMT-LIB2 sort name.
sortToSMT :: LiquidSort -> String
sortToSMT = \case
  SortInt -> "Int"
  SortBool -> "Bool"
  SortSet _ -> "Int" -- modeled or uninterpreted
  SortVar tv -> T.unpack tv
  SortADT name _ -> T.unpack name
  SortRecordRow _ -> "Int"
  SortVariantRow _ -> "Int"
  SortEffectRow _ -> "Int"

-- | Generate SMT-LIB2 declarations for sorts, measures, and environment constants.
lowerSigToFOL :: LiquidSig -> String
lowerSigToFOL LiquidSig{..} =
  let -- Declare uninterpreted sorts
      sortDecls = unlines
        [ "(declare-sort " ++ T.unpack s ++ " 0)"
        | s <- Set.toList sigSorts
        , s `notElem` ["Int", "Bool"]
        ]

      -- Declare measures as uninterpreted functions
      measureDecls = unlines
        [ "(declare-fun " ++ T.unpack measureName
            ++ " (" ++ sortToSMT measureDomain ++ ") "
            ++ sortToSMT measureRange ++ ")"
        | (_, MeasureDecl{..}) <- Map.toList sigMeasures
        ]

      -- Declare environment variables as constants
      envDecls = unlines
        [ case rType of
            RBScalar (RBase _ s _) -> "(declare-const " ++ T.unpack v ++ " " ++ sortToSMT s ++ ")"
            _                      -> "(declare-const " ++ T.unpack v ++ " Int)"
        | (v, rType) <- Map.toList sigEnv
        ]
  in sortDecls ++ measureDecls ++ envDecls

-- | Lower a LiquidSentence to its negated refutation predicate.
--
-- For Subtyping: Gamma /\ PathCond /\ lhs /\ NOT(rhs)
-- If Z3 returns UNSAT, the subtyping obligation is VALID.
-- If Z3 returns SAT, the model is a concrete counterexample witness.
lowerSentenceToNegatedFOL :: LiquidSig -> LiquidSentence -> LiquidPred
lowerSentenceToNegatedFOL sig sen =
  let premises = extractEnvAssumptions sig ++ sigPathCond sig
      ctorAxioms = map axiomBody (sigCtorAxioms sig)
  in case sen of
    SenSubtype _v _s lhs rhs ->
      PAnd (ctorAxioms ++ premises ++ [lhs, PNot rhs])
    SenTermination m recArg initParam ->
      let mRec = PMeasureApp m recArg
          mInit = PMeasureApp m initParam
          wf = PAnd [PRel Lt mRec mInit, PRel Ge mRec (PIntLit 0)]
      in PAnd (ctorAxioms ++ premises ++ [PNot wf])
    SenAbduction _holeId _vars goal ->
      PAnd (ctorAxioms ++ premises ++ [PNot goal])

-- | Collect free variable names in a LiquidPred.
collectFreeVars :: LiquidPred -> Set SymName
collectFreeVars = \case
  PTrue -> Set.empty
  PFalse -> Set.empty
  PVar v -> Set.singleton v
  PIntLit _ -> Set.empty
  PEmptySet _ -> Set.empty
  PMeasureApp _ e -> collectFreeVars e
  PFieldProj _ e -> collectFreeVars e
  PVariantTag _ e -> collectFreeVars e
  PBinOp _ l r -> collectFreeVars l `Set.union` collectFreeVars r
  PRel _ l r -> collectFreeVars l `Set.union` collectFreeVars r
  PNot e -> collectFreeVars e
  PAnd es -> Set.unions (map collectFreeVars es)
  POr es -> Set.unions (map collectFreeVars es)
  PImplies l r -> collectFreeVars l `Set.union` collectFreeVars r
  PIff l r -> collectFreeVars l `Set.union` collectFreeVars r
  PLiquidHole _ vs -> Set.fromList vs

-- | Convert a LiquidPred into an SMT-LIB2 boolean expression.
liquidPredToSMTLib :: LiquidPred -> String
liquidPredToSMTLib = \case
  PTrue -> "true"
  PFalse -> "false"
  PVar v -> T.unpack v
  PIntLit n -> if n < 0 then "(- " ++ show (abs n) ++ ")" else show n
  PEmptySet _ -> "0"
  PMeasureApp m e -> "(" ++ T.unpack m ++ " " ++ liquidPredToSMTLib e ++ ")"
  PFieldProj l e -> "(sel_" ++ T.unpack l ++ " " ++ liquidPredToSMTLib e ++ ")"
  PVariantTag t e -> "(is_" ++ T.unpack t ++ " " ++ liquidPredToSMTLib e ++ ")"
  PBinOp op l r ->
    let opStr = case op of
          Add -> "+"
          Sub -> "-"
          Mul -> "*"
          SetUnion -> "+"
          SetIntersect -> "*"
          SetDiff -> "-"
    in "(" ++ opStr ++ " " ++ liquidPredToSMTLib l ++ " " ++ liquidPredToSMTLib r ++ ")"
  PRel op l r ->
    let opStr = case op of
          Eq -> "="
          Neq -> "distinct"
          Lt -> "<"
          Le -> "<="
          Gt -> ">"
          Ge -> ">="
          SetMember -> "="
          SetSubset -> "<="
    in "(" ++ opStr ++ " " ++ liquidPredToSMTLib l ++ " " ++ liquidPredToSMTLib r ++ ")"
  PNot e -> "(not " ++ liquidPredToSMTLib e ++ ")"
  PAnd [] -> "true"
  PAnd [e] -> liquidPredToSMTLib e
  PAnd es -> "(and " ++ unwords (map liquidPredToSMTLib es) ++ ")"
  POr [] -> "false"
  POr [e] -> liquidPredToSMTLib e
  POr es -> "(or " ++ unwords (map liquidPredToSMTLib es) ++ ")"
  PImplies l r -> "(=> " ++ liquidPredToSMTLib l ++ " " ++ liquidPredToSMTLib r ++ ")"
  PIff l r -> "(= " ++ liquidPredToSMTLib l ++ " " ++ liquidPredToSMTLib r ++ ")"
  PLiquidHole h _ -> T.unpack h

-- | Parse raw model map into LiquidModel, reconstructing record structures from
-- signature environment declarations and projection constants.
z3ModelToLiquidModel :: LiquidSig -> Map String String -> LiquidModel
z3ModelToLiquidModel sig raw =
  let parseVal s = case s of
        "true" -> VBool True
        "false" -> VBool False
        _ | all (\c -> isDigit c || c == '-') s && not (null s) && s /= "-" ->
            VInt (read s)
          | otherwise -> VInt 0
      varEnv = Map.fromList [ (T.pack k, parseVal v) | (k, v) <- Map.toList raw ]
      -- Synthesize records in varEnv from meas_<f>_<v>
      recordVals =
        [ (v, VRecord (Map.fromList [ (f, Map.findWithDefault (VInt 0) (T.pack ("meas_" ++ T.unpack f ++ "_" ++ T.unpack v)) varEnv) | f <- Map.keys fields ]))
        | (v, rType) <- Map.toList (sigEnv sig)
        , fields <- case rType of
                      RBScalar (RBase _ (SortRecordRow (RowSchema fs)) _) -> [fs]
                      RBScalar (RBase _ (SortADT _ [SortRecordRow (RowSchema fs), _]) _) -> [fs]
                      _ -> []
        ]
      varEnvWithRecords = foldr (\(k, v) env -> Map.insert k v env) varEnv recordVals
      -- Populate measure interpretations
      measureInterp = Map.fromList
        [ (("sel_" <> f, recVal), Map.findWithDefault (VInt 0) f fieldMap)
        | (_v, recVal@(VRecord fieldMap)) <- recordVals
        , f <- Map.keys fieldMap
        ]
  in LiquidModel
       { modelVarEnv = varEnvWithRecords
       , modelMeasureInterp = measureInterp
       , modelAbductSol = Map.empty
       }

-- | Discharges a liquid subtyping verification condition via streaming Z3.
-- Pipes lowerSigToFOL and negated VC into solveZ3Raw.
checkLiquidSubtypingZ3 :: LiquidSig -> LiquidSentence -> IO SubtypeResult
checkLiquidSubtypingZ3 sig sen = do
  let negPred = lowerSentenceToNegatedFOL sig sen
      sigDecls = lowerSigToFOL sig
      -- Also declare any free variables occurring in negPred that weren't in sigEnv
      fvs = collectFreeVars negPred
      envVars = Map.keysSet (sigEnv sig)
      extraVars = Set.difference fvs envVars
      extraDecls = unlines [ "(declare-const " ++ T.unpack v ++ " Int)" | v <- Set.toList extraVars ]
      -- Generate scalar projection constants for records in sigEnv to extract measure values directly
      recordProjections =
        [ (v, f, "meas_" ++ T.unpack f ++ "_" ++ T.unpack v)
        | (v, rType) <- Map.toList (sigEnv sig)
        , f <- case rType of
                 RBScalar (RBase _ (SortRecordRow (RowSchema fields)) _) -> Map.keys fields
                 RBScalar (RBase _ (SortADT _ [SortRecordRow (RowSchema fields), _]) _) -> Map.keys fields
                 _ -> []
        ]
      recDecls = unlines
        [ "(declare-const " ++ c ++ " Int)\n(assert (= " ++ c ++ " (sel_" ++ T.unpack f ++ " " ++ T.unpack v ++ ")))"
        | (v, f, c) <- recordProjections
        ]
      assertion = "(assert " ++ liquidPredToSMTLib negPred ++ ")\n"
      query = "(set-logic ALL)\n" ++ sigDecls ++ extraDecls ++ recDecls ++ assertion ++ "(check-sat)\n(get-model)\n"
  res <- solveZ3Raw query
  case res of
    Unsat -> pure SubtypeValid
    Sat mdl -> pure $ SubtypeRejected (z3ModelToLiquidModel sig mdl)
    Unknown _err ->
      let defaultModel = LiquidModel Map.empty Map.empty Map.empty
      in pure $ SubtypeRejected defaultModel

-- | Synthesizes candidate branch guards from sigQualifiers and uses counterexample
-- models from checkLiquidSubtypingZ3 to filter out falsified qualifiers.
abductConditionZ3 :: LiquidSig -> [SymName] -> LiquidPred -> IO (Maybe LiquidPred)
abductConditionZ3 sig scopeVars goal = do
  let quals = Set.toList (sigQualifiers sig)
      candidates = concatMap (instantiateQualifier scopeVars) quals
  solveAbductionLoop sig candidates [] goal
  where
    instantiateQualifier vars qual =
      case qualParams qual of
        [] -> [qualBody qual]
        [(pName, _)] ->
          [ substVar pName v (qualBody qual) | v <- vars ]
        _ -> [qualBody qual]

    substVar oldVar newVar = \case
      PVar v | v == oldVar -> PVar newVar
      PEmptySet s -> PEmptySet s
      PMeasureApp m e -> PMeasureApp m (substVar oldVar newVar e)
      PFieldProj l e -> PFieldProj l (substVar oldVar newVar e)
      PVariantTag t e -> PVariantTag t (substVar oldVar newVar e)
      PBinOp op l r -> PBinOp op (substVar oldVar newVar l) (substVar oldVar newVar r)
      PRel op l r -> PRel op (substVar oldVar newVar l) (substVar oldVar newVar r)
      PNot e -> PNot (substVar oldVar newVar e)
      PAnd es -> PAnd (map (substVar oldVar newVar) es)
      POr es -> POr (map (substVar oldVar newVar) es)
      PImplies l r -> PImplies (substVar oldVar newVar l) (substVar oldVar newVar r)
      PIff l r -> PIff (substVar oldVar newVar l) (substVar oldVar newVar r)
      other -> other

solveAbductionLoop
  :: LiquidSig
  -> [LiquidPred]
  -> [LiquidPred]
  -> LiquidPred
  -> IO (Maybe LiquidPred)
solveAbductionLoop sig remaining chosen goal = do
  let currentGuard = case chosen of
        [] -> PTrue
        [g] -> g
        gs -> PAnd gs
      sigWithGuard = sig { sigPathCond = currentGuard : sigPathCond sig }
      vc = SenSubtype "v" SortBool PTrue goal
  res <- checkLiquidSubtypingZ3 sigWithGuard vc
  case res of
    SubtypeValid -> pure (Just currentGuard)
    SubtypeRejected cexModel ->
      case filter (\q -> not (evalPredInModel cexModel q)) remaining of
        [] -> pure Nothing
        (q:qs) -> solveAbductionLoop sig qs (q : chosen) goal

-- | Fast syntactic/valuation check of predicate against countermodel.
evalPredInModel :: LiquidModel -> LiquidPred -> Bool
evalPredInModel model = \case
  PTrue -> True
  PFalse -> False
  PVar v -> case Map.lookup v (modelVarEnv model) of
    Just (VBool b) -> b
    Just (VInt n)  -> n /= 0
    _              -> False
  PIntLit n -> n /= 0
  PEmptySet _ -> False
  PRel Eq l r -> evalArith model l == evalArith model r
  PRel Neq l r -> evalArith model l /= evalArith model r
  PRel Lt l r -> evalArith model l < evalArith model r
  PRel Le l r -> evalArith model l <= evalArith model r
  PRel Gt l r -> evalArith model l > evalArith model r
  PRel Ge l r -> evalArith model l >= evalArith model r
  PNot e -> not (evalPredInModel model e)
  PAnd es -> all (evalPredInModel model) es
  POr es -> any (evalPredInModel model) es
  PImplies l r -> not (evalPredInModel model l) || evalPredInModel model r
  PIff l r -> evalPredInModel model l == evalPredInModel model r
  _ -> True

evalArith :: LiquidModel -> LiquidPred -> Integer
evalArith model = \case
  PIntLit n -> n
  PVar v -> case Map.lookup v (modelVarEnv model) of
    Just (VInt n) -> n
    _             -> 0
  PBinOp Add l r -> evalArith model l + evalArith model r
  PBinOp Sub l r -> evalArith model l - evalArith model r
  PBinOp Mul l r -> evalArith model l * evalArith model r
  _ -> 0
