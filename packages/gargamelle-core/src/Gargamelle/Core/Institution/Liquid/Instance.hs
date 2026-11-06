{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

module Gargamelle.Core.Institution.Liquid.Instance
  ( Institution (..)
  , LiquidInstitution (..)
  , translatePred
  , translateSort
  , extractEnvAssumptions
  , evalPred
  , checkSatisfactionCondition
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Gargamelle.Core.Institution.Liquid

-- | Goguen-Burstall Institution class indexed by an institution tag type.
class Institution inst where
  type Sig inst
  type SigMorphism inst
  type Sen inst
  type Mod inst
  senMap    :: SigMorphism inst -> Sen inst -> Sen inst
  modReduct :: SigMorphism inst -> Mod inst -> Mod inst
  satisfies :: Sig inst -> Mod inst -> Sen inst -> Bool

data LiquidInstitution = LiquidInstitution

instance Institution LiquidInstitution where
  type Sig LiquidInstitution          = LiquidSig
  type SigMorphism LiquidInstitution = LiquidSigMorphism
  type Sen LiquidInstitution          = LiquidSentence
  type Mod LiquidInstitution          = LiquidModel

  -- | Push a verification obligation along a signature morphism (covariant).
  senMap sigma sen = case sen of
    SenSubtype v s lhs rhs ->
      SenSubtype
        (renameVar sigma v)
        (translateSort sigma s)
        (translatePred sigma lhs)
        (translatePred sigma rhs)
    SenTermination m recArg initParam ->
      SenTermination
        (renameMeas sigma m)
        (translatePred sigma recArg)
        (translatePred sigma initParam)
    SenAbduction holeId vars goal ->
      SenAbduction
        holeId
        (map (renameVar sigma) vars)
        (translatePred sigma goal)

  -- | Pull a model back along a signature morphism (contravariant reduct).
  modReduct sigma model2 = LiquidModel
    { modelVarEnv = Map.fromList
        [ (v1, val)
        | (v1, v2) <- Map.toList (morphVarMap sigma)
        , Just val <- [Map.lookup v2 (modelVarEnv model2)]
        ]
    , modelMeasureInterp = Map.fromList
        [ ((m1, argVal), resVal)
        | (m1, m2) <- Map.toList (morphMeasMap sigma)
        , ((m2', argVal), resVal) <- Map.toList (modelMeasureInterp model2)
        , m2 == m2'
        ]
    , modelAbductSol = Map.map (translatePredInverse sigma) (modelAbductSol model2)
    }

  -- | Semantic satisfaction M |=_Sigma phi
  satisfies sig model sen =
    let envAssumptions = extractEnvAssumptions sig
        pathAssumptions = sigPathCond sig
        premises = PAnd (envAssumptions ++ pathAssumptions)
    in case sen of
      SenSubtype _v _s lhs rhs ->
        -- A model satisfies the subtyping obligation if for the model's valuation of v,
        -- (Premises /\ lhs) => rhs holds.
        evalPred model (PImplies (PAnd [premises, lhs]) rhs)
      SenTermination m recArg initParam ->
        let mRec = PMeasureApp m recArg
            mInit = PMeasureApp m initParam
            wfCond = PAnd
              [ PRel Lt mRec mInit
              , PRel Ge mRec (PIntLit 0)
              ]
        in evalPred model (PImplies premises wfCond)
      SenAbduction holeId _vars goal ->
        case Map.lookup holeId (modelAbductSol model) of
          Nothing -> False
          Just abductedPred ->
            -- Abducted condition must entail the goal under premises AND be non-vacuous
            evalPred model (PImplies (PAnd [premises, abductedPred]) goal)
              && evalPred model (PAnd [premises, abductedPred])

--------------------------------------------------------------------------------
-- Translation Helpers Preserving the Satisfaction Condition
--------------------------------------------------------------------------------

renameVar :: LiquidSigMorphism -> SymName -> SymName
renameVar sigma v = Map.findWithDefault v v (morphVarMap sigma)

renameMeas :: LiquidSigMorphism -> SymName -> SymName
renameMeas sigma m = Map.findWithDefault m m (morphMeasMap sigma)

translateSort :: LiquidSigMorphism -> LiquidSort -> LiquidSort
translateSort sigma s = case s of
  SortVar tv
    -> Map.findWithDefault s tv (morphSortMap sigma)
  SortSet elemS
    -> SortSet (translateSort sigma elemS)
  SortADT n args
    -> SortADT n (map (translateSort sigma) args)
  SortRecordRow r  -> SortRecordRow (RowSchema (Map.map (translateSort sigma) (unRowSchema r)))
  SortVariantRow r -> SortVariantRow (RowSchema (Map.map (translateSort sigma) (unRowSchema r)))
  other
    -> other

translatePred :: LiquidSigMorphism -> LiquidPred -> LiquidPred
translatePred sigma p = case p of
  PTrue
    -> PTrue
  PFalse
    -> PFalse
  PVar v
    -> PVar (renameVar sigma v)
  PIntLit i
    -> PIntLit i
  PEmptySet s
    -> PEmptySet (translateSort sigma s)
  PMeasureApp m e
    -> PMeasureApp (renameMeas sigma m) (translatePred sigma e)
  PFieldProj l e
    -> PFieldProj l (translatePred sigma e)
  PVariantTag t e
    -> PVariantTag t (translatePred sigma e)
  PBinOp op l r
    -> PBinOp op (translatePred sigma l) (translatePred sigma r)
  PRel op l r
    -> PRel op (translatePred sigma l) (translatePred sigma r)
  PNot e
    -> PNot (translatePred sigma e)
  PAnd es
    -> PAnd (map (translatePred sigma) es)
  POr es
    -> POr (map (translatePred sigma) es)
  PImplies l r
    -> PImplies (translatePred sigma l) (translatePred sigma r)
  PIff l r
    -> PIff (translatePred sigma l) (translatePred sigma r)
  PLiquidHole h vs
    -> PLiquidHole h (map (renameVar sigma) vs)

translatePredInverse :: LiquidSigMorphism -> LiquidPred -> LiquidPred
translatePredInverse sigma = translatePred invSigma
  where
    invMap m = Map.fromList [(v, k) | (k, v) <- Map.toList m]
    invSigma = sigma
      { morphVarMap = invMap (morphVarMap sigma)
      , morphMeasMap = invMap (morphMeasMap sigma)
      }

-- | Extracts scalar refinement assumptions from Gamma:
-- Every binding (x : {v : S | phi(v)}) in Gamma contributes phi[v := x] to premises.
extractEnvAssumptions :: LiquidSig -> [LiquidPred]
extractEnvAssumptions sig =
  [ substVar v x phi
  | (x, RBScalar (RBase v _ phi)) <- Map.toList (sigEnv sig)
  ]

substVar :: SymName -> SymName -> LiquidPred -> LiquidPred
substVar oldV newV = translatePred (LiquidSigMorphism emptySig emptySig Map.empty (Map.singleton oldV newV) Map.empty)
  where
    emptySig = LiquidSig mempty mempty [] mempty mempty []

-- | Concrete evaluator for decidable QF predicates against a LiquidModel.
-- Evaluates linear arithmetic, sets, and measure lookups against modelVarEnv
-- and modelMeasureInterp.
evalPred :: LiquidModel -> LiquidPred -> Bool
evalPred model pred0 = go pred0
  where
    go PTrue = True
    go PFalse = False
    go (PNot p) = not (go p)
    go (PAnd ps) = all go ps
    go (POr ps) = any go ps
    go (PImplies p q) = not (go p) || go q
    go (PIff p q) = go p == go q
    go (PRel op l r) = case (evalVal l, evalVal r) of
      (Just vl, Just vr) -> evalRel op vl vr
      _                  -> True
    go _ = True

    evalVal :: LiquidPred -> Maybe LiquidVal
    evalVal (PIntLit i) = Just (VInt i)
    evalVal (PVar v) = Map.lookup v (modelVarEnv model)
    evalVal (PEmptySet _) = Just (VSet mempty)
    evalVal (PMeasureApp m e) = do
      ve <- evalVal e
      Map.lookup (m, ve) (modelMeasureInterp model)
    evalVal (PBinOp op l r) = do
      vl <- evalVal l
      vr <- evalVal r
      evalBin op vl vr
    evalVal (PFieldProj f e) = do
      ve <- evalVal e
      case ve of
        VRecord m -> Map.lookup f m
        _         -> Nothing
    evalVal _ = Nothing

    evalBin :: BinOp -> LiquidVal -> LiquidVal -> Maybe LiquidVal
    evalBin Add (VInt a) (VInt b) = Just (VInt (a + b))
    evalBin Sub (VInt a) (VInt b) = Just (VInt (a - b))
    evalBin Mul (VInt a) (VInt b) = Just (VInt (a * b))
    evalBin SetUnion (VSet s1) (VSet s2) = Just (VSet (s1 <> s2))
    evalBin SetIntersect (VSet s1) (VSet s2) = Just (VSet (Set.intersection s1 s2))
    evalBin SetDiff (VSet s1) (VSet s2) = Just (VSet (Set.difference s1 s2))
    evalBin _ _ _ = Nothing

    evalRel :: RelOp -> LiquidVal -> LiquidVal -> Bool
    evalRel Eq vl vr = vl == vr
    evalRel Neq vl vr = vl /= vr
    evalRel Lt (VInt a) (VInt b) = a < b
    evalRel Le (VInt a) (VInt b) = a <= b
    evalRel Gt (VInt a) (VInt b) = a > b
    evalRel Ge (VInt a) (VInt b) = a >= b
    evalRel SetMember v (VSet s) = Set.member v s
    evalRel SetSubset (VSet s1) (VSet s2) = Set.isSubsetOf s1 s2
    evalRel _ _ _ = False

-- | Verifies Goguen-Burstall satisfaction condition invariance across a signature morphism:
-- satisfies (morphTarget sigma) m2 (senMap sigma phi) == satisfies (morphSource sigma) (modReduct sigma m2) phi
checkSatisfactionCondition :: LiquidSigMorphism -> LiquidModel -> LiquidSentence -> Bool
checkSatisfactionCondition sigma m2 phi =
  satisfies @LiquidInstitution (morphTarget sigma) m2 (senMap @LiquidInstitution sigma phi)
    == satisfies @LiquidInstitution (morphSource sigma) (modReduct @LiquidInstitution sigma m2) phi
