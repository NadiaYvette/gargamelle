{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Wno-redundant-constraints #-}

module Gargamelle.Persistence.RewriteMining
  ( -- * Rewrite Motifs & Candidate Schemas
    RewriteMotifKind (..)
  , CandidateLawSchema (..)
  , DiscoveredConditionalLaw (..)
  , Z3StreamPoolOrSession (..)
    -- * Stage 1: Motif Enumeration
  , enumerateCandidateMotifs
  , buildMotifsForPair
    -- * Stage 2: Semantic Beam Overlap Filter
  , computeBeamEqualityOverlap
    -- * Stage 3: Galois Guard Abduction & Z3 Soundness Verification
  , abductAndVerifyConditionalLaw
    -- * Stage 4: DPORule Compilation & Pushout Materialization
  , compileLawToDPORule
  , materializeRHS
  , buildRhsRepTerm
  , upsertENode
    -- * Top-Level Concurrent Miner
  , mineConditionalDPORules
  ) where

import Control.Monad (forM)
import qualified Data.IntMap.Strict as IntMap
import Data.IntSet (IntSet)
import qualified Data.IntSet as IntSet
import Data.List (sortOn)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Ord (Down (..))
import qualified Data.Set as Set
import GHC.Generics (Generic)

import Gargamelle.Core.Institution.Liquid
import Gargamelle.Equational.AbductiveEGraph
  ( AbductiveEGraph (..)
  , DPORule (..)
  , EClassData (..)
  , EClassId (..)
  , ENode (..)
  , Z3StreamSession (..)
  , unEClassId
  )
import Gargamelle.FOL.LiquidBridge (SubtypeResult (..), checkLiquidSubtypingZ3)
import Gargamelle.FOL.LiquidHyperdoctrine
  ( Context (..)
  , FOLFormula (..)
  , Hyperdoctrine (..)
  , LiquidSubHyperdoctrine (..)
  , QualifierBasis (..)
  , QualifierConj (..)
  , weakGaloisImplicant
  )
import Gargamelle.Model.AmbiguityOracle
  ( compileSynTermToRelPredWithSig
  , evalSynTermInModel
  , observationalEqPred
  )
import Gargamelle.Persistence.Crystallize
  ( CrystallizedCombinator (..)
  , LiquidSymbolicStep (..)
  , PersistentLibraryBank (..)
  , extractAccessedRowLabels
  )

--------------------------------------------------------------------------------
-- 1. Data Structures for Rewrite Motifs and Discovered Laws
--------------------------------------------------------------------------------

-- | The algebraic motif category of a candidate rewrite law.
data RewriteMotifKind
  = MotifIdempotence
  | MotifCancellation
  | MotifScalarFusion
  | MotifAbsorption
  | MotifDisjointRowCommute
  deriving stock (Eq, Ord, Show, Generic)

-- | Proposed candidate rewrite law schema prior to beam verification.
data CandidateLawSchema = CandidateLawSchema
  { clsName         :: SymName
  , clsMotif        :: RewriteMotifKind
  , clsOuterComb    :: CrystallizedCombinator
  , clsInnerComb    :: CrystallizedCombinator
  , clsTargetSort   :: LiquidSort
  , clsVars         :: Map SymName LiquidSort
  , clsLHS          :: SynTerm
  , clsRHS          :: SynTerm
  , clsExpandedLHS  :: SynTerm
  , clsExpandedRHS  :: SynTerm
  , clsCostDelta    :: !Int
  } deriving stock (Eq, Show, Generic)

-- | A verified conditional DPO rewrite law discovered by the mining engine.
data DiscoveredConditionalLaw = DiscoveredConditionalLaw
  { dclSchema        :: CandidateLawSchema
  , dclAbductedGuard :: QualifierConj
  , dclBeamOverlap   :: IntSet
  , dclMdlScore      :: !Double
  } deriving stock (Eq, Show, Generic)

-- | Handle for Z3 session dispatch (single session or concurrent worker pool).
data Z3StreamPoolOrSession
  = UseSingleSession Z3StreamSession
  | UseConcurrentPool Int
  deriving (Eq, Show)

--------------------------------------------------------------------------------
-- 2. Stage 1: Sort- and Row-Directed Motif Enumeration
--------------------------------------------------------------------------------

-- | Enumerates all sort-compatible candidate rewrite schemas across pairs of
-- crystallized combinators in `PersistentLibraryBank`.
enumerateCandidateMotifs :: PersistentLibraryBank -> [CandidateLawSchema]
enumerateCandidateMotifs PersistentLibraryBank{..} =
  let combs = Map.elems bankCombinators
  in [ schema
     | f <- combs
     , g <- combs
     , areSortCompatible f g
     , schema <- buildMotifsForPair f g
     ]
  where
    areSortCompatible f g =
      let outCtxF = unContext (stepCtxOut (ccSymbolicStep f))
          inCtxG  = unContext (stepCtxIn (ccSymbolicStep g))
      in case (Map.lookup "v" outCtxF, Map.elems inCtxG) of
        (Just outSortF, inSortsG) -> outSortF `elem` inSortsG
        _                         -> True

-- | Generates candidate motif schemas for a specific pair of combinators (f, g).
buildMotifsForPair
  :: CrystallizedCombinator
  -> CrystallizedCombinator
  -> [CandidateLawSchema]
buildMotifsForPair f g =
  let fName = ccName f
      gName = ccName g
      inCtxF = unContext (stepCtxIn (ccSymbolicStep f))
      outCtxG = unContext (stepCtxOut (ccSymbolicStep g))
      retSort = Map.findWithDefault SortInt "v" outCtxG

      -- Thread state variable of matching sort (or first variable)
      (xSym, xSort) = case [ (v, s) | (v, s) <- Map.toList inCtxF, s == retSort ] of
        (p : _) -> p
        []      -> case Map.toList inCtxF of
          (p : _) -> p
          []      -> ("r", retSort)
      scalarVar = case [ v | (v, _) <- Map.toList inCtxF, v /= xSym ] of
        (v : _) -> v
        []      -> "d"
      varsMap = Map.fromList
        [ (xSym, xSort)
        , ("a_arg", SortInt)
        , ("b_arg", SortInt)
        ]

      lhsSameArg = TApp (TVar gName) [TApp (TVar fName) [TVar xSym, TVar "a_arg"], TVar "a_arg"]
      lhsTwoArgs = TApp (TVar gName) [TApp (TVar fName) [TVar xSym, TVar "a_arg"], TVar "b_arg"]

      inlineComb :: CrystallizedCombinator -> SynTerm -> SynTerm -> SynTerm
      inlineComb comb stateArg scalarArg =
        substSynTermVar xSym stateArg $
        substSynTermVar scalarVar scalarArg (ccImplementation comb)

      rMid = xSym <> "_mid"

      expLhsSame = TEffBind rMid (inlineComb f (TVar xSym) (TVar "a_arg"))
                                 (inlineComb g (TVar rMid) (TVar "a_arg"))
      expLhsTwo  = TEffBind rMid (inlineComb f (TVar xSym) (TVar "a_arg"))
                                 (inlineComb g (TVar rMid) (TVar "b_arg"))

      -- 1. Idempotence & 2. Scalar Fusion (when f == g)
      sameCombMotifs
        | fName == gName =
            [ CandidateLawSchema
                { clsName         = "DPO_Idemp_" <> fName
                , clsMotif        = MotifIdempotence
                , clsOuterComb    = g
                , clsInnerComb    = f
                , clsTargetSort   = retSort
                , clsVars         = varsMap
                , clsLHS          = lhsSameArg
                , clsRHS          = TApp (TVar fName) [TVar xSym, TVar "a_arg"]
                , clsExpandedLHS  = expLhsSame
                , clsExpandedRHS  = inlineComb f (TVar xSym) (TVar "a_arg")
                , clsCostDelta    = -3
                }
            , CandidateLawSchema
                { clsName         = "DPO_Fusion_" <> fName
                , clsMotif        = MotifScalarFusion
                , clsOuterComb    = g
                , clsInnerComb    = f
                , clsTargetSort   = retSort
                , clsVars         = varsMap
                , clsLHS          = lhsTwoArgs
                , clsRHS          = TApp (TVar fName) [TVar xSym, TApp (TVar "add") [TVar "a_arg", TVar "b_arg"]]
                , clsExpandedLHS  = expLhsTwo
                , clsExpandedRHS  = inlineComb f (TVar xSym) (TApp (TVar "add") [TVar "a_arg", TVar "b_arg"])
                , clsCostDelta    = -2
                }
            ]
        | otherwise = []

      -- 3. Cancellation Motif: g(f(x, a), a) ~> x
      cancelMotif = CandidateLawSchema
        { clsName         = "DPO_Cancel_" <> gName <> "_" <> fName
        , clsMotif        = MotifCancellation
        , clsOuterComb    = g
        , clsInnerComb    = f
        , clsTargetSort   = retSort
        , clsVars         = varsMap
        , clsLHS          = lhsSameArg
        , clsRHS          = TVar xSym
        , clsExpandedLHS  = expLhsSame
        , clsExpandedRHS  = TVar xSym
        , clsCostDelta    = -5
        }

      -- 4. Absorption Motif: g(f(x, a), b) ~> g(x, b)
      absorbMotif = CandidateLawSchema
        { clsName         = "DPO_Absorb_" <> gName <> "_" <> fName
        , clsMotif        = MotifAbsorption
        , clsOuterComb    = g
        , clsInnerComb    = f
        , clsTargetSort   = retSort
        , clsVars         = varsMap
        , clsLHS          = lhsTwoArgs
        , clsRHS          = TApp (TVar gName) [TVar xSym, TVar "b_arg"]
        , clsExpandedLHS  = expLhsTwo
        , clsExpandedRHS  = inlineComb g (TVar xSym) (TVar "b_arg")
        , clsCostDelta    = -3
        }

      -- 5. Disjoint-Row Commutation: g(f(x, a), b) ~> f(g(x, b), a)
      (_, writtenF) = extractAccessedRowLabels (ccImplementation f)
      (_, writtenG) = extractAccessedRowLabels (ccImplementation g)
      commuteMotifs
        | fName < gName && Set.disjoint writtenF writtenG =
            [ CandidateLawSchema
                { clsName         = "DPO_RowCommute_" <> gName <> "_" <> fName
                , clsMotif        = MotifDisjointRowCommute
                , clsOuterComb    = g
                , clsInnerComb    = f
                , clsTargetSort   = retSort
                , clsVars         = varsMap
                , clsLHS          = lhsTwoArgs
                , clsRHS          = TApp (TVar fName) [TApp (TVar gName) [TVar xSym, TVar "b_arg"], TVar "a_arg"]
                , clsExpandedLHS  = expLhsTwo
                , clsExpandedRHS  = TEffBind rMid (inlineComb g (TVar xSym) (TVar "b_arg"))
                                                  (inlineComb f (TVar rMid) (TVar "a_arg"))
                , clsCostDelta    = -1
                }
            ]
        | otherwise = []
  in sameCombMotifs ++ [cancelMotif, absorbMotif] ++ commuteMotifs

termToPredExpr :: SynTerm -> Maybe LiquidPred
termToPredExpr = \case
  TVar v -> Just (PVar v)
  TIntLit i -> Just (PIntLit i)
  TApp (TVar "add") [a, b] -> do
    pa <- termToPredExpr a
    pb <- termToPredExpr b
    Just (PBinOp Add pa pb)
  TApp (TVar "sub") [a, b] -> do
    pa <- termToPredExpr a
    pb <- termToPredExpr b
    Just (PBinOp Sub pa pb)
  _ -> Nothing

substSynTermVar :: SymName -> SynTerm -> SynTerm -> SynTerm
substSynTermVar target replacement = go
  where
    mPredRepl = termToPredExpr replacement
    substG g = case mPredRepl of
      Just p  -> substMapInPred (Map.singleton target p) g
      Nothing -> g
    go = \case
      TVar v
        | v == target -> replacement
        | otherwise   -> TVar v
      TIntLit i -> TIntLit i
      TBoolLit b -> TBoolLit b
      TLam x b
        | x == target -> TLam x b
        | otherwise   -> TLam x (go b)
      TIf g t1 t2 -> TIf (substG g) (go t1) (go t2)
      TEffPure t -> TEffPure (go t)
      TEffBind x o k -> TEffBind x (go o) (if x == target then k else go k)
      TApp hd args -> TApp (go hd) (map go args)

--------------------------------------------------------------------------------
-- 3. Stage 2: Semantic Beam Partial-Overlap Filter
--------------------------------------------------------------------------------

-- | Evaluates `clsExpandedLHS` and `clsExpandedRHS` across every canonical
-- witness model in `bankCanonicalBeam` and returns the `IntSet` of model IDs
-- where both expressions produce the exact same `LiquidVal`.
computeBeamEqualityOverlap
  :: PersistentLibraryBank
  -> CandidateLawSchema
  -> IntSet
computeBeamEqualityOverlap PersistentLibraryBank{..} CandidateLawSchema{..} =
  IntMap.keysSet $ IntMap.filter agreesOnModel bankCanonicalBeam
  where
    agreesOnModel :: LiquidModel -> Bool
    agreesOnModel mdl =
      let valL = evalSynTermInModel bankEvalPred mdl clsExpandedLHS
          valR = evalSynTermInModel bankEvalPred mdl clsExpandedRHS
      in valL == valR

--------------------------------------------------------------------------------
-- 4. Stage 3 & 4: Galois Guard Abduction, Z3 Proof, & DPORule Compilation
--------------------------------------------------------------------------------

-- | Abducts the weakest qualifier conjunction `q_law` entailing equivalence
-- between LHS and RHS using the right Galois adjoint `weakGaloisImplicant`,
-- and verifies universal validity with Z3.
abductAndVerifyConditionalLaw
  :: forall h. (Hyperdoctrine h, LiquidSubHyperdoctrine h)
  => h
  -> Z3StreamPoolOrSession
  -> LiquidSig
  -> QualifierBasis
  -> Int
  -> PersistentLibraryBank
  -> CandidateLawSchema
  -> IO (Maybe DiscoveredConditionalLaw)
abductAndVerifyConditionalLaw _proxy _z3Handle baseSig basis minOverlap bank schema@CandidateLawSchema{..} = do
  let overlapSet = computeBeamEqualityOverlap bank schema
  if IntMap.null (bankCanonicalBeam bank) || IntSet.size overlapSet >= minOverlap
    then do
      let outL = "v_law_lhs"
          outR = "v_law_rhs"
          relL = compileSynTermToRelPredWithSig (Just baseSig) outL clsExpandedLHS
          relR = compileSynTermToRelPredWithSig (Just baseSig) outR clsExpandedRHS
          obsEq = observationalEqPred baseSig clsTargetSort outL outR
          xPrimary = case [ v | (v, s) <- Map.toList clsVars, s == clsTargetSort ] of
            (v : _) -> v
            []      -> case [ v | v <- Map.keys clsVars, v /= "a_arg", v /= "b_arg" ] of
              (v : _) -> v
              []      -> "r"
          rMid = xPrimary <> "_mid"
          lawCtx = Context $
            Map.insert outL clsTargetSort $
            Map.insert outR clsTargetSort $
            Map.insert rMid clsTargetSort clsVars

          abductTarget = FImplies (FAtom (PAnd [relL, relR])) (FAtom obsEq)

      mAbducted <- weakGaloisImplicant @h lawCtx basis abductTarget
      case mAbducted of
        Nothing -> pure Nothing
        Just qGuard -> do
          let guardPred = PAnd (Set.toList (qcConjuncts qGuard))
              guardCover = if IntMap.null (bankCanonicalBeam bank)
                           then IntSet.empty
                           else IntMap.keysSet $
                                IntMap.filter (\m -> bankEvalPred bank m guardPred) (bankCanonicalBeam bank)
              verifiedOverlap = if IntMap.null (bankCanonicalBeam bank)
                                then IntSet.singleton 0
                                else IntSet.intersection overlapSet guardCover

          if not (IntMap.null (bankCanonicalBeam bank)) && IntSet.size verifiedOverlap < minOverlap
            then pure Nothing
            else do
              let sigWithGuard = baseSig
                    { sigEnv      = Map.insert outL (RBScalar (RBase "v" clsTargetSort PTrue)) $
                                    Map.insert outR (RBScalar (RBase "v" clsTargetSort PTrue)) $
                                    Map.insert rMid (RBScalar (RBase "v" clsTargetSort PTrue)) $
                                    Map.union (Map.map (\s -> RBScalar (RBase "v" s PTrue)) clsVars) (sigEnv baseSig)
                    , sigPathCond = guardPred : sigPathCond baseSig
                    }
                  vc = SenSubtype outL clsTargetSort (PAnd [relL, relR]) obsEq
              res <- checkLiquidSubtypingZ3 sigWithGuard vc
              case res of
                SubtypeRejected _ -> pure Nothing
                SubtypeValid -> do
                  let overlapSize = fromIntegral (max 1 (IntSet.size verifiedOverlap)) :: Double
                      qualCount = fromIntegral (Set.size (qcConjuncts qGuard)) :: Double
                      costSavings = fromIntegral (abs clsCostDelta) :: Double
                      mdlScore = (overlapSize * costSavings) - (qualCount * 1.5)
                  pure $ Just DiscoveredConditionalLaw
                    { dclSchema        = schema
                    , dclAbductedGuard = qGuard
                    , dclBeamOverlap   = verifiedOverlap
                    , dclMdlScore      = mdlScore
                    }
    else pure Nothing

-- | Compiles a verified `DiscoveredConditionalLaw` into an executable `DPORule`.
compileLawToDPORule :: DiscoveredConditionalLaw -> DPORule
compileLawToDPORule DiscoveredConditionalLaw{..} =
  let CandidateLawSchema{..} = dclSchema
      guardPred = PAnd (Set.toList (qcConjuncts dclAbductedGuard))
      xSym = case [ v | (v, s) <- Map.toList clsVars, s == clsTargetSort ] of
        (v : _) -> v
        []      -> case [ v | v <- Map.keys clsVars, v /= "a_arg", v /= "b_arg" ] of
          (v : _) -> v
          []      -> "r"
      fName = ccName clsInnerComb
      gName = ccName clsOuterComb
      ruleName = clsName
  in DPORule
       { dpoName       = ruleName
       , dpoSort       = clsTargetSort
       , dpoCostDelta  = clsCostDelta
       , dpoExtraOblig = (`substMapInPred` guardPred)
       , dpoMatchLHS   = \targetId eg ->
           case IntMap.lookup (unEClassId targetId) (egClasses eg) of
             Nothing -> []
             Just targetData ->
               [ (subst, lhsTerm, rhsTerm)
               | EApp g [cidInner, cidB] <- Set.toList (ecNodes targetData)
               , g == gName
               , Just innerData <- [IntMap.lookup (unEClassId cidInner) (egClasses eg)]
               , EApp f [cidX, cidA] <- Set.toList (ecNodes innerData)
               , f == fName
               , let subst = Map.fromList [ (xSym, cidX), ("a_arg", cidA), ("b_arg", cidB) ]
                     repX = fromMaybe (TVar xSym) (pickRepresentativeTerm eg cidX)
                     repA = fromMaybe (TVar "a_arg") (pickRepresentativeTerm eg cidA)
                     repB = fromMaybe (TVar "b_arg") (pickRepresentativeTerm eg cidB)
                     lhsTerm = TApp (TVar gName) [TApp (TVar fName) [repX, repA], repB]
                     rhsTerm = buildRhsRepTerm clsMotif fName gName repX repA repB
               ]
       , dpoRHSBuilder = materializeRHS clsMotif fName gName xSym
       }

buildRhsRepTerm :: RewriteMotifKind -> SymName -> SymName -> SynTerm -> SynTerm -> SynTerm -> SynTerm
buildRhsRepTerm motif fName gName repX repA repB = case motif of
  MotifIdempotence        -> TApp (TVar fName) [repX, repA]
  MotifCancellation       -> repX
  MotifScalarFusion       -> TApp (TVar fName) [repX, TApp (TVar "add") [repA, repB]]
  MotifAbsorption         -> TApp (TVar gName) [repX, repB]
  MotifDisjointRowCommute -> TApp (TVar fName) [TApp (TVar gName) [repX, repB], repA]

pickRepresentativeTerm :: AbductiveEGraph -> EClassId -> Maybe SynTerm
pickRepresentativeTerm AbductiveEGraph{..} cid = do
  ec <- IntMap.lookup (unEClassId cid) egClasses
  listToMaybe $ mapMaybe nodeToSimpleTerm (Set.toList (ecNodes ec))
  where
    nodeToSimpleTerm = \case
      EVar v     -> Just (TVar v)
      EIntLit i  -> Just (TIntLit i)
      EBoolLit b -> Just (TBoolLit b)
      _          -> Nothing

-- | Materializes the pushout RHS e-class in `AbductiveEGraph`.
materializeRHS
  :: RewriteMotifKind
  -> SymName
  -> SymName
  -> SymName
  -> Map SymName EClassId
  -> AbductiveEGraph
  -> (EClassId, AbductiveEGraph)
materializeRHS motif fName gName xSym subst eg0 =
  let cidX = Map.findWithDefault (EClassId 0) xSym subst
      cidA = Map.findWithDefault (EClassId 0) "a_arg" subst
      cidB = Map.findWithDefault (EClassId 0) "b_arg" subst
  in case motif of
    MotifCancellation ->
      (cidX, eg0)
    MotifIdempotence ->
      upsertENode (EApp fName [cidX, cidA]) eg0
    MotifAbsorption ->
      upsertENode (EApp gName [cidX, cidB]) eg0
    MotifScalarFusion ->
      let (cidSum, eg1) = upsertENode (EApp "add" [cidA, cidB]) eg0
      in upsertENode (EApp fName [cidX, cidSum]) eg1
    MotifDisjointRowCommute ->
      let (cidInnerG, eg1) = upsertENode (EApp gName [cidX, cidB]) eg0
      in upsertENode (EApp fName [cidInnerG, cidA]) eg1

upsertENode :: ENode -> AbductiveEGraph -> (EClassId, AbductiveEGraph)
upsertENode node eg@AbductiveEGraph{..} =
  case Map.lookup node egHashcons of
    Just existingCid -> (existingCid, eg)
    Nothing ->
      let nextId = case IntMap.lookupMax egClasses of
            Nothing     -> 0
            Just (k, _) -> k + 1
          newCid = EClassId nextId
          newEc = EClassData
            { ecId       = newCid
            , ecSort     = SortInt
            , ecNodes    = Set.singleton node
            , ecEdges    = []
            , ecMeasures = []
            , ecFrontier = []
            }
      in ( newCid
         , eg { egClasses  = IntMap.insert nextId newEc egClasses
              , egHashcons = Map.insert node newCid egHashcons
              }
         )

substMapInPred :: Map SymName LiquidPred -> LiquidPred -> LiquidPred
substMapInPred subst = go
  where
    go = \case
      PVar v          -> Map.findWithDefault (PVar v) v subst
      PMeasureApp m e -> PMeasureApp m (go e)
      PFieldProj l e  -> PFieldProj l (go e)
      PVariantTag t e -> PVariantTag t (go e)
      PBinOp op l r   -> PBinOp op (go l) (go r)
      PRel op l r     -> PRel op (go l) (go r)
      PNot e          -> PNot (go e)
      PAnd es         -> PAnd (map go es)
      POr es          -> POr (map go es)
      PImplies l r    -> PImplies (go l) (go r)
      PIff l r        -> PIff (go l) (go r)
      other           -> other

--------------------------------------------------------------------------------
-- 5. Top-Level Sleep-Phase Rewrite Miner
--------------------------------------------------------------------------------

-- | Mines, abducts, verifies, and compiles conditional DPO rules from crystallized combinators.
mineConditionalDPORules
  :: forall h. (Hyperdoctrine h, LiquidSubHyperdoctrine h)
  => h
  -> Z3StreamSession
  -> LiquidSig
  -> QualifierBasis
  -> Int
  -> Double
  -> PersistentLibraryBank
  -> IO ([DiscoveredConditionalLaw], [DPORule])
mineConditionalDPORules proxy session baseSig basis minOverlap mdlThreshold bank = do
  let rawSchemas = enumerateCandidateMotifs bank
      beamSurvivors =
        [ (schema, IntSet.size overlap)
        | schema <- rawSchemas
        , let overlap = computeBeamEqualityOverlap bank schema
        , IntMap.null (bankCanonicalBeam bank) || IntSet.size overlap >= minOverlap
        ]
  verifiedMaybes <- forM beamSurvivors $ \(schema, _) ->
    abductAndVerifyConditionalLaw
      proxy
      (UseSingleSession session)
      baseSig
      basis
      minOverlap
      bank
      schema
  let worthyLaws =
        sortOn (Down . dclMdlScore)
          [ law
          | Just law <- verifiedMaybes
          , dclMdlScore law >= mdlThreshold
          ]
      compiledRules = map compileLawToDPORule worthyLaws
  pure (worthyLaws, compiledRules)
