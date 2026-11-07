{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Wno-redundant-constraints #-}

module Gargamelle.Model.AmbiguityOracle
  ( -- * Semantic Equivalence Classes & Ambiguity Queries
    VertexId
  , SemanticClass (..)
  , CandidateBehaviorOption (..)
  , AmbiguityQuery (..)
  , AmbiguityResolution (..)
  , StalkDisambiguationResult (..)
    -- * Symbolic Relational Compilation & Concrete Evaluation
  , compileSynTermToRelPred
  , compileSynTermToRelPredWithSig
  , observationalEqPred
  , evalSynTermInModel
    -- * Quotienting & Distinguishing Model Synthesis
  , findDistinguishingModelZ3
  , partitionIntoSemanticQuotients
  , analyzeStalkAmbiguity
    -- * Applying LLM 1-Bit Feedback to the Sheaf & E-Graph
  , applyAmbiguityResolution
  ) where

import Control.Monad (foldM)
import qualified Data.IntMap.Strict as IntMap
import Data.List (maximumBy, minimumBy)
import qualified Data.Map.Strict as Map
import Data.Ord (comparing)
import qualified Data.Set as Set
import qualified Data.Text as T
import GHC.Generics (Generic)

import Gargamelle.Core.Institution.Liquid
import Gargamelle.Equational.AbductiveEGraph (AbductiveEGraph (..), Z3StreamSession (..))
import Gargamelle.FOL.LiquidBridge (SubtypeResult (..), checkLiquidSubtypingZ3)
import Gargamelle.FOL.LiquidHyperdoctrine
  ( Context (..)
  , FOLFormula (..)
  , Hyperdoctrine (..)
  , LiquidSubHyperdoctrine (..)
  , QualifierBasis (..)
  , QualifierConj (..)
  , strongGaloisConsequence
  )

--------------------------------------------------------------------------------
-- 1. Data Structures for Semantic Quotients & LLM Ambiguity Queries
--------------------------------------------------------------------------------

type VertexId = SymName

-- | An equivalence class of verified SynTerms that are provably observationally
-- isomorphic across 100% of models satisfying Gamma and PathCond.
data SemanticClass = SemanticClass
  { scCanonicalTerm        :: SynTerm
  -- ^ Minimum-cost representative AST in this semantic equivalence class
  , scCanonicalCost        :: !Int
  , scEquivalentASTs       :: [SynTerm]
  -- ^ Other syntactically distinct ASTs proven equivalent by Z3
  , scDistinguishingModels :: [(LiquidModel, LiquidVal)]
  -- ^ Witness models discovered during quotienting paired with this class's output
  } deriving stock (Eq, Show, Generic)

-- | One distinct runtime outcome presented to the LLM on a distinguishing input.
data CandidateBehaviorOption = CandidateBehaviorOption
  { optOptionId         :: !Int
  , optOutputValue      :: LiquidVal
  -- ^ The concrete output produced on `aqDistinguishingInput`
  , optInducedPostQual  :: QualifierConj
  -- ^ Strongest postcondition qualifiers characterizing this behavior class
  , optRepresentative   :: SynTerm
  -- ^ Kept internally by gargamelle; the LLM only needs to inspect `optOutputValue`
  -- and `optInducedPostQual`!
  } deriving stock (Eq, Show, Generic)

-- | A zero-code ambiguity query emitted to the `sarutahiko` LLM controller
-- whenever a sheaf stalk admits >= 2 non-isomorphic verified implementations.
data AmbiguityQuery = AmbiguityQuery
  { aqVertexId             :: VertexId
  , aqGoalBase             :: RBase
  , aqDistinguishingInput  :: LiquidModel
  -- ^ Concrete input valuation M_diff where competing valid programs diverge
  , aqBehaviorOptions      :: [CandidateBehaviorOption]
  -- ^ Distinct concrete outputs v_1, v_2, ... produced on M_diff
  , aqShannonBalanceScore  :: !Double
  -- ^ Entropy score measuring how evenly M_diff bisects the candidate classes
  } deriving stock (Show, Generic)

-- | The LLM's 1-bit/multi-choice answer pinning down the intended semantics.
data AmbiguityResolution = AmbiguityResolution
  { arVertexId       :: VertexId
  , arChosenOptionId :: !Int
  -- ^ Index of the selected `CandidateBehaviorOption`
  } deriving stock (Eq, Show, Generic)

data StalkDisambiguationResult
  = UnambiguousTerm SynTerm
  -- ^ All valid candidates collapsed into a single semantic equivalence class!
  | AmbiguousStalk AmbiguityQuery
  -- ^ Multiple non-isomorphic valid classes exist; query the LLM with M_diff.
  deriving stock (Show, Generic)

--------------------------------------------------------------------------------
-- 2. Compiling Branching `SynTerm`s to Relational SMT Predicates
--------------------------------------------------------------------------------

-- | Lowers an arbitrary `SynTerm` (including nested `TIf` decision trees from
-- `AbductiveEGraph` and `TEffBind` steps) into a quantifier-free relational
-- predicate `Rel(T, outVar)` asserting that evaluating `T` yields `outVar`.
compileSynTermToRelPred :: SymName -> SynTerm -> LiquidPred
compileSynTermToRelPred = compileSynTermToRelPredWithSig Nothing

-- | Lowers an arbitrary `SynTerm` into a relational predicate under an optional `LiquidSig`.
compileSynTermToRelPredWithSig :: Maybe LiquidSig -> SymName -> SynTerm -> LiquidPred
compileSynTermToRelPredWithSig mSig outVar = go
  where
    go = \case
      TVar v ->
        PRel Eq (PVar outVar) (PVar v)
      TIntLit i ->
        PRel Eq (PVar outVar) (PIntLit i)
      TBoolLit True ->
        PRel Eq (PVar outVar) PTrue
      TBoolLit False ->
        PRel Eq (PVar outVar) PFalse
      TLam _ body ->
        go body
      TIf guardPred thenBranch elseBranch ->
        let thenRel = compileSynTermToRelPredWithSig mSig outVar thenBranch
            elseRel = compileSynTermToRelPredWithSig mSig outVar elseBranch
        in PAnd
             [ PImplies guardPred thenRel
             , PImplies (PNot guardPred) elseRel
             ]
      TEffPure innerTerm ->
        go innerTerm
      TEffBind nextStVar effOpTerm contTerm ->
        let stepRel = compileSynTermToRelPredWithSig mSig nextStVar effOpTerm
            contRel = compileSynTermToRelPredWithSig mSig outVar contTerm
        in PAnd [stepRel, contRel]
      appTerm@(TApp (TVar fn) args) ->
        case termToLiquidPred appTerm of
          Just p -> PRel Eq (PVar outVar) p
          Nothing ->
            case (fn, map termToLiquidPred args) of
              ("add", [Just l, Just r]) -> PRel Eq (PVar outVar) (PBinOp Add l r)
              ("sub", [Just l, Just r]) -> PRel Eq (PVar outVar) (PBinOp Sub l r)
              _ | "setF_" `T.isPrefixOf` fn, [valArg, recArg] <- args ->
                    let lbl = T.drop 5 fn
                        valPred = case termToLiquidPred valArg of
                          Just p -> p
                          Nothing -> PVar (outVar <> "_val")
                        recPred = case termToLiquidPred recArg of
                          Just p -> p
                          Nothing -> PVar (outVar <> "_rec")
                        valEq = PRel Eq (PMeasureApp ("sel_" <> lbl) (PVar outVar)) valPred
                        frameEqs = case mSig of
                          Nothing -> []
                          Just sig ->
                            [ PRel Eq (PMeasureApp ("sel_" <> other) (PVar outVar))
                                      (PMeasureApp ("sel_" <> other) recPred)
                            | (mName, _) <- Map.toList (sigMeasures sig)
                            , let other = if "sel_" `T.isPrefixOf` mName then T.drop 4 mName else mName
                            , other /= lbl
                            ]
                    in PAnd (valEq : frameEqs)
                | "getF_" `T.isPrefixOf` fn, [recArg] <- args ->
                    let lbl = T.drop 5 fn
                        recPred = case termToLiquidPred recArg of
                          Just p -> p
                          Nothing -> PVar (outVar <> "_rec")
                    in PRel Eq (PVar outVar) (PMeasureApp ("sel_" <> lbl) recPred)
                | otherwise -> PTrue
      TApp _ _ -> PTrue

-- | Constructs the observational equality predicate `v1 ===_S v2` for sort `S`.
-- For Polytropos open rows (`SortRecordRow`, `SortVariantRow`), observational
-- equivalence holds iff all known row fields/tags and active measures agree.
observationalEqPred :: LiquidSig -> LiquidSort -> SymName -> SymName -> LiquidPred
observationalEqPred LiquidSig{..} sortS v1 v2 =
  case sortS of
    SortRecordRow (RowSchema fields) ->
      PAnd
        [ PRel Eq
            (PMeasureApp ("sel_" <> l) (PVar v1))
            (PMeasureApp ("sel_" <> l) (PVar v2))
        | l <- Map.keys fields
        ]
    SortVariantRow (RowSchema fields) ->
      let tagEq = PRel Eq (PMeasureApp "vtags" (PVar v1)) (PMeasureApp "vtags" (PVar v2))
          payEqs =
            [ PRel Eq
                (PMeasureApp ("vpayload_" <> l) (PVar v1))
                (PMeasureApp ("vpayload_" <> l) (PVar v2))
            | l <- Map.keys fields
            ]
      in PAnd (tagEq : payEqs)
    SortADT adtName [SortRecordRow (RowSchema fields), _tailSort]
      | "RecordF_" `T.isPrefixOf` adtName ->
          PAnd
            [ PRel Eq
                (PMeasureApp ("sel_" <> l) (PVar v1))
                (PMeasureApp ("sel_" <> l) (PVar v2))
            | l <- Map.keys fields
            ]
    SortADT adtName [SortVariantRow (RowSchema fields), _tailSort]
      | "VariantF_" `T.isPrefixOf` adtName ->
          let tagEq = PRel Eq (PMeasureApp "vtags" (PVar v1)) (PMeasureApp "vtags" (PVar v2))
              payEqs =
                [ PRel Eq
                    (PMeasureApp ("vpayload_" <> l) (PVar v1))
                    (PMeasureApp ("vpayload_" <> l) (PVar v2))
                | l <- Map.keys fields
                ]
          in PAnd (tagEq : payEqs)
    _ ->
      let domainMeasures =
            [ mName
            | (mName, MeasureDecl{..}) <- Map.toList sigMeasures
            , measureDomain == sortS
            ]
          measEqs =
            [ PRel Eq (PMeasureApp m (PVar v1)) (PMeasureApp m (PVar v2))
            | m <- domainMeasures
            ]
      in PAnd (PRel Eq (PVar v1) (PVar v2) : measEqs)

--------------------------------------------------------------------------------
-- 3. Concrete Evaluation of `SynTerm` on Z3 Distinguishing Models
--------------------------------------------------------------------------------

-- | Evaluates a synthesized `SynTerm` (including `TIf` guards and `Polytropos`
-- row combinators) against a concrete `LiquidModel` returned by Z3.
evalSynTermInModel
  :: (LiquidModel -> LiquidPred -> Bool)
  -> LiquidModel
  -> SynTerm
  -> LiquidVal
evalSynTermInModel evalPred mdl = go
  where
    go = \case
      TVar v ->
        Map.findWithDefault (VInt 0) v (modelVarEnv mdl)
      TIntLit i ->
        VInt i
      TBoolLit b ->
        VBool b
      TLam _ body ->
        go body
      TEffPure t ->
        go t
      TEffBind _ opTerm contTerm ->
        let _ = go opTerm in go contTerm
      TIf g t1 t2 ->
        if evalPred mdl g then go t1 else go t2
      TApp (TVar fn) args
        | fn == "add", [a, b] <- map go args, VInt i1 <- a, VInt i2 <- b ->
            VInt (i1 + i2)
        | fn == "sub", [a, b] <- map go args, VInt i1 <- a, VInt i2 <- b ->
            VInt (i1 - i2)
        | "getF_" `T.isPrefixOf` fn, [recTerm] <- args ->
            let lbl = T.drop 5 fn
            in case go recTerm of
              VRecord rMap -> Map.findWithDefault (VInt 0) lbl rMap
              recVal ->
                Map.findWithDefault (VInt 0) ("sel_" <> lbl, recVal) (modelMeasureInterp mdl)
        | "setF_" `T.isPrefixOf` fn, [valTerm, recTerm] <- args ->
            let lbl = T.drop 5 fn
                vVal = go valTerm
            in case go recTerm of
              VRecord rMap -> VRecord (Map.insert lbl vVal rMap)
              _ -> VRecord (Map.singleton lbl vVal)
        | "injF_" `T.isPrefixOf` fn, [payTerm] <- args ->
            VVariant (T.drop 5 fn) (go payTerm)
        | "matchTagF_" `T.isPrefixOf` fn, [varTerm] <- args ->
            case go varTerm of
              VVariant _ pay -> pay
              varVal ->
                let lbl = T.drop 10 fn
                in Map.findWithDefault (VInt 0) ("vpayload_" <> lbl, varVal) (modelMeasureInterp mdl)
        | otherwise -> VInt 0
      TApp _ _ -> VInt 0

--------------------------------------------------------------------------------
-- 4. Semantic Quotienting & Distinguishing Witness Synthesis via Z3
--------------------------------------------------------------------------------

-- | Queries Z3 to check if `term1` and `term2` are observationally equivalent
-- under `sig`.
-- * Returns `Nothing` if `sig |= term1 ===_obs term2` (semantically isomorphic).
-- * Returns `Just diffModel` if Z3 finds a valid input where `term1` and `term2`
-- produce distinct outputs.
findDistinguishingModelZ3
  :: Z3StreamSession
  -> LiquidSig
  -> LiquidSort
  -> SynTerm
  -> SynTerm
  -> IO (Maybe LiquidModel)
findDistinguishingModelZ3 _session sig resultSort term1 term2 = do
  let out1 = "v_oracle_out1"
      out2 = "v_oracle_out2"
      rel1 = compileSynTermToRelPredWithSig (Just sig) out1 term1
      rel2 = compileSynTermToRelPredWithSig (Just sig) out2 term2
      eqPred = observationalEqPred sig resultSort out1 out2
      -- Extend signature environment with temporary output variables `out1`, `out2`
      sigExtended = sig
        { sigEnv = Map.insert out1 (RBScalar (RBase "v" resultSort PTrue))
                 $ Map.insert out2 (RBScalar (RBase "v" resultSort PTrue))
                 $ sigEnv sig
        }
      -- Check validity of: (rel1 /\ rel2) ==> (out1 ===_obs out2)
      vc = SenSubtype out1 resultSort (PAnd [rel1, rel2]) eqPred
  res <- checkLiquidSubtypingZ3 sigExtended vc
  pure $ case res of
    SubtypeValid -> Nothing
    SubtypeRejected diffMdl -> Just diffMdl

-- | Partitions a list of verified candidate `(SynTerm, Cost)` pairs into
-- observationally distinct `SemanticClass` quotients, collecting the concrete
-- Z3 distinguishing models discovered along the way.
partitionIntoSemanticQuotients
  :: Z3StreamSession
  -> LiquidSig
  -> (LiquidModel -> LiquidPred -> Bool)
  -> LiquidSort
  -> [(SynTerm, Int)]
  -> IO ([SemanticClass], [LiquidModel])
partitionIntoSemanticQuotients session sig evalPred resultSort candidates =
  foldM insertCandidate ([], []) candidates
  where
    insertCandidate
      :: ([SemanticClass], [LiquidModel])
      -> (SynTerm, Int)
      -> IO ([SemanticClass], [LiquidModel])
    insertCandidate (classes, diffModels) (term, cost) =
      matchExistingClass classes diffModels
      where
        matchExistingClass [] accModels = do
          let newClass = SemanticClass
                { scCanonicalTerm        = term
                , scCanonicalCost        = cost
                , scEquivalentASTs       = [term]
                , scDistinguishingModels =
                    [ (m, evalSynTermInModel evalPred m term) | m <- accModels ]
                }
          pure ([newClass], accModels)
        matchExistingClass (sc:scs) accModels = do
          mDiff <- findDistinguishingModelZ3 session sig resultSort term (scCanonicalTerm sc)
          case mDiff of
            Nothing -> do
              -- `term` is observationally isomorphic to `scCanonicalTerm sc`
              let (bestTerm, bestCost) =
                    if cost < scCanonicalCost sc
                    then (term, cost)
                    else (scCanonicalTerm sc, scCanonicalCost sc)
                  scMerged = sc
                    { scCanonicalTerm  = bestTerm
                    , scCanonicalCost  = bestCost
                    , scEquivalentASTs = term : scEquivalentASTs sc
                    }
              pure (scMerged : scs, accModels)
            Just newDiffModel -> do
              -- `term` and `sc` diverge on `newDiffModel`
              let accModels' = newDiffModel : accModels
              (restClasses, finalModels) <- matchExistingClass scs accModels'
              pure (sc : restClasses, finalModels)

--------------------------------------------------------------------------------
-- 5. Max-Entropy Ambiguity Query Construction & Specification Tightening
--------------------------------------------------------------------------------

-- | Analyzes all verified candidate trees for a sheaf vertex stalk:
-- * If all candidates belong to a single `SemanticClass`, returns `UnambiguousTerm` immediately.
-- * If multiple `SemanticClass` quotients exist, selects the distinguishing model
-- `M_diff*` that maximizes Shannon entropy across the classes and constructs
-- the `AmbiguityQuery` for the LLM.
analyzeStalkAmbiguity
  :: forall h. (Hyperdoctrine h, LiquidSubHyperdoctrine h)
  => h
  -> Z3StreamSession
  -> VertexId
  -> Context
  -> QualifierBasis
  -> LiquidSig
  -> (LiquidModel -> LiquidPred -> Bool)
  -> RBase
  -> [(SynTerm, Int)]
  -> IO StalkDisambiguationResult
analyzeStalkAmbiguity _proxy session vid ctx basis sig evalPred goalBase@RBase{..} verifiedCandidates = do
  (quotients, diffModels) <-
    partitionIntoSemanticQuotients session sig evalPred rSort verifiedCandidates
  case quotients of
    [] -> pure $ UnambiguousTerm (TVar ("empty_stalk_" <> vid))
    [uniq] ->
      -- Every valid candidate is observationally isomorphic! Emit the minimum-cost AST.
      pure $ UnambiguousTerm (scCanonicalTerm uniq)
    _ -> do
      -- Multiple non-isomorphic valid programs exist!
      -- Pick distinguishing model M_diff* maximizing Shannon entropy.
      let bestModel = selectMaxEntropyModel evalPred quotients diffModels
      options <- mapM (buildOptionForClass bestModel) (zip [0..] quotients)
      let dedupedOptions = deduplicateByOutputValue options
          entropyScore = computePartitionEntropy evalPred quotients bestModel
      pure $ AmbiguousStalk AmbiguityQuery
        { aqVertexId            = vid
        , aqGoalBase            = goalBase
        , aqDistinguishingInput = bestModel
        , aqBehaviorOptions     = dedupedOptions
        , aqShannonBalanceScore = entropyScore
        }
  where
    buildOptionForClass :: LiquidModel -> (Int, SemanticClass) -> IO CandidateBehaviorOption
    buildOptionForClass mdl (idx, sc) = do
      let outVal = evalSynTermInModel evalPred mdl (scCanonicalTerm sc)
          relPred = compileSynTermToRelPredWithSig (Just sig) rValueVar (scCanonicalTerm sc)
          ctxWithOut = Context (Map.insert rValueVar rSort (unContext ctx))
      inducedQuals <- strongGaloisConsequence @h ctxWithOut basis (FAtom relPred)
      pure CandidateBehaviorOption
        { optOptionId        = idx
        , optOutputValue     = outVal
        , optInducedPostQual = inducedQuals
        , optRepresentative  = scCanonicalTerm sc
        }

    deduplicateByOutputValue :: [CandidateBehaviorOption] -> [CandidateBehaviorOption]
    deduplicateByOutputValue opts =
      Map.elems $ Map.fromListWith const [ (optOutputValue o, o) | o <- opts ]

    selectMaxEntropyModel
      :: (LiquidModel -> LiquidPred -> Bool)
      -> [SemanticClass]
      -> [LiquidModel]
      -> LiquidModel
    selectMaxEntropyModel _ _ [] = LiquidModel Map.empty Map.empty Map.empty
    selectMaxEntropyModel evalP classes models =
      maximumBy (comparing (computePartitionEntropy evalP classes)) models

    -- | Computes Shannon entropy H(M) = - sum (p_i * log2 p_i) of the output value
    -- distribution induced by evaluating all semantic classes on `mdl`.
    computePartitionEntropy
      :: (LiquidModel -> LiquidPred -> Bool)
      -> [SemanticClass]
      -> LiquidModel
      -> Double
    computePartitionEntropy evalP classes mdl =
      let total = fromIntegral (length classes) :: Double
          outputs = [ evalSynTermInModel evalP mdl (scCanonicalTerm sc) | sc <- classes ]
          counts = Map.elems $ Map.fromListWith (+) [ (v, 1 :: Int) | v <- outputs ]
      in if total <= 1
         then 0.0
         else negate $ sum
           [ let p = fromIntegral c / total
             in p * (log p / log 2.0)
           | c <- counts
           , c > 0
           ]

--------------------------------------------------------------------------------
-- 6. Closing the Loop: Applying the LLM's 1-Bit Resolution
--------------------------------------------------------------------------------

-- | Applies the LLM's `AmbiguityResolution` to both the vertex's `LiquidSig`
-- (via an Institution Signature Morphism) and its `AbductiveEGraph`:
-- 1. Injects the pinned input-output witness `M_diff[v |-> optOutputValue]` into
-- `egWitnessModels`.
-- 2. Extracts discriminating postcondition qualifiers $\Delta_Q = Q(\text{chosen}) \setminus \bigcap Q(\text{rejected})$,
-- constructs `LiquidSigMorphism`, and strengthens the goal refinement `rRefine`.
applyAmbiguityResolution
  :: AmbiguityQuery
  -> AmbiguityResolution
  -> AbductiveEGraph
  -> (RBase, LiquidSigMorphism, AbductiveEGraph)
applyAmbiguityResolution AmbiguityQuery{..} AmbiguityResolution{..} eg0 =
  let chosenOpt = case filter (\o -> optOptionId o == arChosenOptionId) aqBehaviorOptions of
        (o:_) -> o
        [] -> minimumBy (comparing optOptionId) aqBehaviorOptions
      rejectedOpts = filter (\o -> optOptionId o /= optOptionId chosenOpt) aqBehaviorOptions
      -- 1. Compute discriminating postcondition qualifiers
      rejectedCommon = case rejectedOpts of
        [] -> Set.empty
        (r:rs) -> foldr Set.intersection (qcConjuncts (optInducedPostQual r))
                    [ qcConjuncts (optInducedPostQual x) | x <- rs ]
      discriminatingQuals =
        Set.difference (qcConjuncts (optInducedPostQual chosenOpt)) rejectedCommon
      strengthenedPred = PAnd (rRefine aqGoalBase : Set.toList discriminatingQuals)
      strengthenedGoal = aqGoalBase { rRefine = strengthenedPred }
      -- 2. Construct the Institution Signature Morphism
      srcSig = egSig eg0
      tgtSig = srcSig { sigPathCond = Set.toList discriminatingQuals ++ sigPathCond srcSig }
      pinMorphism = LiquidSigMorphism
        { morphSource  = srcSig
        , morphTarget  = tgtSig
        , morphSortMap = Map.empty
        , morphVarMap  = Map.fromSet id (Map.keysSet (sigEnv srcSig))
        , morphMeasMap = Map.fromSet id (Map.keysSet (sigMeasures srcSig))
        }
      -- 3. Pin concrete input-output witness into `egWitnessModels`
      pinnedModel = aqDistinguishingInput
        { modelVarEnv = Map.insert
            (rValueVar aqGoalBase)
            (optOutputValue chosenOpt)
            (modelVarEnv aqDistinguishingInput)
        }
      nextModelKey = case IntMap.lookupMax (egWitnessModels eg0) of
        Nothing -> 0
        Just (k, _) -> k + 1
      egUpdated = eg0
        { egSig           = tgtSig
        , egWitnessModels = IntMap.insert nextModelKey pinnedModel (egWitnessModels eg0)
        }
  in (strengthenedGoal, pinMorphism, egUpdated)
