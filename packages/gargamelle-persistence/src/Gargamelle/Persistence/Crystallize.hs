{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# OPTIONS_GHC -Wno-redundant-constraints #-}

module Gargamelle.Persistence.Crystallize
  ( -- * Wake-Phase Raw Artifacts & Sleep-Phase Crystallized Combinators
    VertexId
  , LiquidSymbolicStep (..)
  , WakeStalkArtifact (..)
  , CrystallizedCombinator (..)
  , MeasurePromotionRecord (..)
  , PersistentLibraryBank (..)
    -- * Stage 1: Row-Polymorphic Anti-Unification
  , generalizeToOpenRowSchema
  , extractAccessedRowLabels
    -- * Stage 2: Profunctor & RSchema Crystallization (Qualifier Encapsulation)
  , crystallizeStalkToCombinator
    -- * Stage 3: Semantic Beam Sub-DAG Extraction & MDL Sleep Cycle
  , isAstStructurallySimilar
  , computeSemanticBitvector
  , runSleepPhaseCrystallization
  , injectLibraryIntoStalkSig
  ) where

import qualified Data.Bifunctor as Bifunctor
import Data.IntMap.Strict (IntMap)
import qualified Data.IntMap.Strict as IntMap
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import qualified Data.Maybe as Maybe
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as T
import GHC.Generics (Generic)

import Gargamelle.Core.Institution.Liquid
import Gargamelle.FOL.GaloisSeparator (SeparatorSynthesisResult (..))
import Gargamelle.FOL.LiquidHyperdoctrine
  ( Context (..)
  , FOLFormula (..)
  , Hyperdoctrine (..)
  , LiquidSubHyperdoctrine (..)
  , QualifierBasis (..)
  , QualifierConj (..)
  , strongGaloisConsequence
  , weakGaloisImplicant
  )
import Gargamelle.Model.AmbiguityOracle (compileSynTermToRelPred, evalSynTermInModel)

type VertexId = SymName

--------------------------------------------------------------------------------
-- 1. Data Structures for Wake-Sleep Artifacts and Combinators
--------------------------------------------------------------------------------

-- | A verified symbolic profunctor step representing an atomic synthesis unit.
data LiquidSymbolicStep = LiquidSymbolicStep
  { stepName       :: SymName
  , stepCtxIn      :: Context
  , stepCtxOut     :: Context
  , stepBasisIn    :: QualifierBasis
  , stepBasisOut   :: QualifierBasis
  , stepPreRef     :: QualifierConj
  , stepPostRef    :: QualifierConj
  , stepRelFormula :: FOLFormula
  } deriving stock (Eq, Show, Generic)

-- | Raw verified output artifact from the active synthesis Wake phase.
data WakeStalkArtifact = WakeStalkArtifact
  { wsaVertexId          :: VertexId
  , wsaInputContext      :: Context
  , wsaFinalSig          :: LiquidSig
  , wsaDisambiguatedGoal :: RBase
  , wsaVerifiedTerm      :: SynTerm
  , wsaInventedSeps      :: [SeparatorSynthesisResult]
  , wsaZ3Refutations     :: !Int
  } deriving stock (Eq, Show, Generic)

-- | A crystallized reusable combinator produced during the Sleep phase.
data CrystallizedCombinator = CrystallizedCombinator
  { ccName             :: SymName
  , ccPolySchema       :: RSchema
  , ccSymbolicStep     :: LiquidSymbolicStep
  , ccImplementation   :: SynTerm
  , ccSemanticHash     :: [Bool]
  , ccMdlSavingsScore  :: !Double
  } deriving stock (Eq, Show, Generic)

-- | Record tracking a newly invented measure candidate for library promotion.
data MeasurePromotionRecord = MeasurePromotionRecord
  { mprMeasure      :: MeasureDecl
  , mprCtorAxioms   :: [CtorMeasureAxiom]
  , mprBoundaryQual :: Qualifier
  , mprUsageCount   :: !Int
  , mprNetMdlGain   :: !Double
  } deriving stock (Eq, Show, Generic)

-- | Persistent library bank of crystallized combinators and promoted measures.
data PersistentLibraryBank = PersistentLibraryBank
  { bankCombinators   :: Map SymName CrystallizedCombinator
  , bankPromotedMeas  :: Map SymName MeasurePromotionRecord
  , bankCanonicalBeam :: IntMap LiquidModel
  , bankEvalPred      :: LiquidModel -> LiquidPred -> Bool
  } deriving stock (Generic)

instance Show PersistentLibraryBank where
  show PersistentLibraryBank{..} =
    "PersistentLibraryBank { bankCombinators = " ++ show bankCombinators ++
    ", bankPromotedMeas = " ++ show bankPromotedMeas ++
    ", bankCanonicalBeam = " ++ show bankCanonicalBeam ++ " }"

--------------------------------------------------------------------------------
-- 2. Stage 1: Row-Polymorphic Anti-Unification
--------------------------------------------------------------------------------

-- | Scans a SynTerm and nested predicates for accessed Polytropos row labels,
-- returning (readLabels, writtenLabels).
extractAccessedRowLabels :: SynTerm -> (Set SymName, Set SymName)
extractAccessedRowLabels = go
  where
    unionPairs (r1, w1) (r2, w2) = (Set.union r1 r2, Set.union w1 w2)

    go = \case
      TVar _ -> (Set.empty, Set.empty)
      TIntLit _ -> (Set.empty, Set.empty)
      TBoolLit _ -> (Set.empty, Set.empty)
      TLam _ b -> go b
      TEffPure t -> go t
      TEffBind _ o k -> unionPairs (go o) (go k)
      TIf p t1 t2 ->
        let pLbls = extractPredRowLabels p
            (r1, w1) = go t1
            (r2, w2) = go t2
        in (Set.unions [pLbls, r1, r2], Set.union w1 w2)
      TApp (TVar fn) args
        | "getF_" `T.isPrefixOf` fn ->
            let lbl = T.drop 5 fn
                recLbls = foldr (unionPairs . go) (Set.empty, Set.empty) args
            in Bifunctor.first (Set.insert lbl) recLbls
        | "setF_" `T.isPrefixOf` fn, [valArg, recArg] <- args ->
            let lbl = T.drop 5 fn
                (rv, wv) = go valArg
                (rr, wr) = go recArg
            in (Set.union rv rr, Set.insert lbl (Set.union wv wr))
        | "matchTagF_" `T.isPrefixOf` fn ->
            let lbl = T.drop 10 fn
                argLbls = foldr (unionPairs . go) (Set.empty, Set.empty) args
            in Bifunctor.first (Set.insert lbl) argLbls
        | otherwise ->
            foldr (unionPairs . go) (Set.empty, Set.empty) args
      TApp hd args ->
        foldr (unionPairs . go) (go hd) args

-- | Extracts row labels occurring in a LiquidPred.
extractPredRowLabels :: LiquidPred -> Set SymName
extractPredRowLabels = \case
  PMeasureApp m e
    | "sel_" `T.isPrefixOf` m      -> Set.insert (T.drop 4 m) (extractPredRowLabels e)
    | "vpayload_" `T.isPrefixOf` m -> Set.insert (T.drop 9 m) (extractPredRowLabels e)
    | otherwise                   -> extractPredRowLabels e
  PFieldProj l e -> Set.insert l (extractPredRowLabels e)
  PVariantTag l e -> Set.insert l (extractPredRowLabels e)
  PVar v
    | "Tag_" `T.isPrefixOf` v -> Set.singleton (T.drop 4 v)
    | otherwise               -> Set.empty
  PBinOp _ l r -> Set.union (extractPredRowLabels l) (extractPredRowLabels r)
  PRel _ l r   -> Set.union (extractPredRowLabels l) (extractPredRowLabels r)
  PNot e       -> extractPredRowLabels e
  PAnd es      -> Set.unions (map extractPredRowLabels es)
  POr es       -> Set.unions (map extractPredRowLabels es)
  PImplies l r -> Set.union (extractPredRowLabels l) (extractPredRowLabels r)
  PIff l r     -> Set.union (extractPredRowLabels l) (extractPredRowLabels r)
  _            -> Set.empty

-- | Generalizes a concrete solved stalk signature into an open-row polymorphic
-- `RSchema` by:
-- 1. Stripping unaccessed concrete fields from any `Polytropos` `RecordF` or
-- `VariantF` sort and replacing them with a polymorphic row tail variable `rho_cryst`.
-- 2. Adding explicit frame preservation equalities `sel_l(v) == sel_l(r)` for
-- every accessed read-only field `l in (readLabels \ writtenLabels)`.
generalizeToOpenRowSchema :: WakeStalkArtifact -> RSchema
generalizeToOpenRowSchema WakeStalkArtifact{..} =
  let (readLbls, writtenLbls) = extractAccessedRowLabels wsaVerifiedTerm
      activeLbls = Set.union readLbls writtenLbls
      readOnlyLbls = Set.difference readLbls writtenLbls
      rhoVar = "rho_" <> wsaVertexId

      generalizeSort :: LiquidSort -> (LiquidSort, Bool)
      generalizeSort = \case
        SortADT adtName [SortRecordRow (RowSchema fields), _]
          | "RecordF_" `T.isPrefixOf` adtName ->
              let kept = Map.restrictKeys fields activeLbls
              in (SortADT adtName [SortRecordRow (RowSchema kept), SortVar rhoVar], True)
        SortADT adtName [SortVariantRow (RowSchema fields), _]
          | "VariantF_" `T.isPrefixOf` adtName ->
              let kept = Map.restrictKeys fields activeLbls
              in (SortADT adtName [SortVariantRow (RowSchema kept), SortVar rhoVar], True)
        SortRecordRow (RowSchema fields) ->
          let kept = Map.restrictKeys fields activeLbls
          in (SortADT "RecordF_Open" [SortRecordRow (RowSchema kept), SortVar rhoVar], True)
        SortVariantRow (RowSchema fields) ->
          let kept = Map.restrictKeys fields activeLbls
          in (SortADT "VariantF_Open" [SortVariantRow (RowSchema kept), SortVar rhoVar], True)
        other -> (other, False)

      recordParams =
        [ x
        | (x, RBScalar (RBase _ s _)) <- Map.toList (sigEnv wsaFinalSig)
        , case s of
            SortADT adtName _ -> "RecordF_" `T.isPrefixOf` adtName
            SortRecordRow _ -> True
            _ -> False
        ]
      frameConjuncts = case recordParams of
        (recParam : _) ->
          [ PRel Eq
              (PMeasureApp ("sel_" <> l) (PVar (rValueVar wsaDisambiguatedGoal)))
              (PMeasureApp ("sel_" <> l) (PVar recParam))
          | l <- Set.toList readOnlyLbls
          ]
        [] -> []

      outVar = rValueVar wsaDisambiguatedGoal
      termRel = compileSynTermToRelPred outVar wsaVerifiedTerm
      (genRetSort, retUsesRho) = generalizeSort (rSort wsaDisambiguatedGoal)
      strengthenedRetBase = RBase
        { rValueVar = outVar
        , rSort     = genRetSort
        , rRefine   = PAnd (rRefine wsaDisambiguatedGoal : termRel : frameConjuncts)
        }

      envBindings = Map.toList (sigEnv wsaFinalSig)
      (arrowType, paramsUseRho) = foldr buildArrow (RBScalar strengthenedRetBase, retUsesRho) envBindings
      buildArrow (paramName, paramRType) (accType, usedRho) =
        case paramRType of
          RBScalar (RBase v s p) ->
            let (s', uses) = generalizeSort s
            in (RArrow paramName (RBScalar (RBase v s' p)) accType, usedRho || uses)
          other ->
            (RArrow paramName other accType, usedRho)
      quantifiedVars = [rhoVar | paramsUseRho]
  in RSchema quantifiedVars arrowType

--------------------------------------------------------------------------------
-- 3. Stage 2: Profunctor Summary & Qualifier Encapsulation
--------------------------------------------------------------------------------

-- | Crystallizes a `WakeStalkArtifact` into a reusable `CrystallizedCombinator`.
-- Internal branch qualifiers from `wsaInventedSeps` are absorbed into
-- `stepRelFormula` without inflating `stepBasisOut`.
crystallizeStalkToCombinator
  :: forall h. (Hyperdoctrine h, LiquidSubHyperdoctrine h)
  => h
  -> PersistentLibraryBank
  -> WakeStalkArtifact
  -> IO CrystallizedCombinator
crystallizeStalkToCombinator _proxy bank artifact@WakeStalkArtifact{..} = do
  let combName = "cryst_" <> wsaVertexId
      polySchema = generalizeToOpenRowSchema artifact
      outVar = rValueVar wsaDisambiguatedGoal
      outSort = rSort wsaDisambiguatedGoal
      ctxOut = Context (Map.insert outVar outSort (unContext wsaInputContext))
      relPred = compileSynTermToRelPred outVar wsaVerifiedTerm
      relFormula = FAtom (PAnd [relPred, rRefine wsaDisambiguatedGoal])
      boundaryQuals = Set.filter (mentionsSym outVar) (sigQualifiers wsaFinalSig)
      basisIn = QualifierBasis (sigQualifiers wsaFinalSig)
      basisOut = QualifierBasis boundaryQuals

  guaranteedPost <- strongGaloisConsequence @h ctxOut basisOut relFormula
  mRequiredPre <- weakGaloisImplicant @h wsaInputContext basisIn (FImplies relFormula (FAtom (rRefine wsaDisambiguatedGoal)))
  let requiredPre = Maybe.fromMaybe (QualifierConj Set.empty) mRequiredPre
      symStep = LiquidSymbolicStep
        { stepName       = combName
        , stepCtxIn      = wsaInputContext
        , stepCtxOut     = ctxOut
        , stepBasisIn    = basisIn
        , stepBasisOut   = basisOut
        , stepPreRef     = requiredPre
        , stepPostRef    = guaranteedPost
        , stepRelFormula = relFormula
        }
      semHash = computeSemanticBitvector bank wsaVerifiedTerm (Set.toList boundaryQuals)
      astNodes = countSynTermNodes wsaVerifiedTerm
      mdlScore = fromIntegral (max 0 (astNodes - 1)) * 2.5 + fromIntegral wsaZ3Refutations * 1.2
  pure CrystallizedCombinator
    { ccName            = combName
    , ccPolySchema      = polySchema
    , ccSymbolicStep    = symStep
    , ccImplementation  = wsaVerifiedTerm
    , ccSemanticHash    = semHash
    , ccMdlSavingsScore = mdlScore
    }

mentionsSym :: SymName -> Qualifier -> Bool
mentionsSym sym Qualifier{..} =
  any ((== sym) . fst) qualParams || predMentions sym qualBody
  where
    predMentions s = \case
      PVar v          -> v == s
      PMeasureApp _ e -> predMentions s e
      PFieldProj _ e  -> predMentions s e
      PVariantTag _ e -> predMentions s e
      PBinOp _ l r    -> predMentions s l || predMentions s r
      PRel _ l r      -> predMentions s l || predMentions s r
      PNot e          -> predMentions s e
      PAnd es         -> any (predMentions s) es
      POr es          -> any (predMentions s) es
      PImplies l r    -> predMentions s l || predMentions s r
      PIff l r        -> predMentions s l || predMentions s r
      _               -> False

countSynTermNodes :: SynTerm -> Int
countSynTermNodes = \case
  TVar _         -> 1
  TIntLit _      -> 1
  TBoolLit _     -> 1
  TLam _ b       -> 1 + countSynTermNodes b
  TEffPure t     -> 1 + countSynTermNodes t
  TEffBind _ o k -> 1 + countSynTermNodes o + countSynTermNodes k
  TIf _ t1 t2    -> 1 + countSynTermNodes t1 + countSynTermNodes t2
  TApp hd args   -> 1 + countSynTermNodes hd + sum (map countSynTermNodes args)

--------------------------------------------------------------------------------
-- 4. Stage 3: Semantic Beam Fingerprinting & Sleep-Phase Compression
--------------------------------------------------------------------------------

-- | Structural skeleton similarity check:
-- Returns True when two ASTs share the same branching/application spine up to
-- variable renaming or leaf literals.
isAstStructurallySimilar :: SynTerm -> SynTerm -> Bool
isAstStructurallySimilar t1 t2 = case (t1, t2) of
  (TVar _, TVar _) -> True
  (TIntLit _, TIntLit _) -> True
  (TBoolLit b1, TBoolLit b2) -> b1 == b2
  (TLam _ b1, TLam _ b2) -> isAstStructurallySimilar b1 b2
  (TEffPure x1, TEffPure x2) -> isAstStructurallySimilar x1 x2
  (TEffBind _ o1 k1, TEffBind _ o2 k2) ->
    isAstStructurallySimilar o1 o2 && isAstStructurallySimilar k1 k2
  (TIf _ a1 b1, TIf _ a2 b2) ->
    isAstStructurallySimilar a1 a2 && isAstStructurallySimilar b1 b2
  (TApp (TVar f1) as1, TApp (TVar f2) as2) ->
    f1 == f2 && length as1 == length as2 && and (zipWith isAstStructurallySimilar as1 as2)
  _ -> False

-- | Computes the Semantic Qualifier Bitvector of a candidate `SynTerm` across
-- all canonical witness models in `bankCanonicalBeam` and active qualifiers.
computeSemanticBitvector
  :: PersistentLibraryBank
  -> SynTerm
  -> [Qualifier]
  -> [Bool]
computeSemanticBitvector PersistentLibraryBank{..} term quals =
  [ let outVal = evalSynTermInModel bankEvalPred mdl term
        mdlWithV = mdl { modelVarEnv = Map.insert "v" outVal (modelVarEnv mdl) }
    in bankEvalPred mdlWithV (qualBody q)
  | (_mid, mdl) <- IntMap.toAscList bankCanonicalBeam
  , q <- quals
  ]

-- | Executes the full Sleep-Phase Library Consolidation over a batch of `WakeStalkArtifact`s.
runSleepPhaseCrystallization
  :: forall h. (Hyperdoctrine h, LiquidSubHyperdoctrine h)
  => h
  -> Double
  -> [WakeStalkArtifact]
  -> PersistentLibraryBank
  -> IO PersistentLibraryBank
runSleepPhaseCrystallization proxy mdlThreshold artifacts bank0 = do
  candidates <- mapM (crystallizeStalkToCombinator proxy bank0)
    [ a | a <- artifacts, countSynTermNodes (wsaVerifiedTerm a) >= 3 ]
  let worthyCombinators =
        filter (\c -> ccMdlSavingsScore c >= mdlThreshold) candidates
      updatedCombinators =
        foldl' insertIfNovel (bankCombinators bank0) worthyCombinators
      allSeps = concatMap wsaInventedSeps artifacts
      updatedMeasures = foldl' (scoreAndPromoteMeasure mdlThreshold) (bankPromotedMeas bank0) allSeps
  pure bank0
    { bankCombinators  = updatedCombinators
    , bankPromotedMeas = updatedMeasures
    }
  where
    insertIfNovel
      :: Map SymName CrystallizedCombinator
      -> CrystallizedCombinator
      -> Map SymName CrystallizedCombinator
    insertIfNovel acc cand =
      let isDuplicate = any
            (\existing ->
              ccSemanticHash existing == ccSemanticHash cand
              && isAstStructurallySimilar (ccImplementation existing) (ccImplementation cand))
            (Map.elems acc)
      in if isDuplicate
         then acc
         else Map.insert (ccName cand) cand acc

    scoreAndPromoteMeasure
      :: Double
      -> Map SymName MeasurePromotionRecord
      -> SeparatorSynthesisResult
      -> Map SymName MeasurePromotionRecord
    scoreAndPromoteMeasure threshold acc SeparatorSynthesisResult{..} =
      case sepNewMeasure of
        Nothing -> acc
        Just mDecl ->
          let mName = measureName mDecl
              marginalGain = 10.0
              record = case Map.lookup mName acc of
                Nothing -> MeasurePromotionRecord
                  { mprMeasure      = mDecl
                  , mprCtorAxioms   = sepNewAxioms
                  , mprBoundaryQual = sepQualifier
                  , mprUsageCount   = 1
                  , mprNetMdlGain   = marginalGain
                  }
                Just prev -> prev
                  { mprUsageCount = mprUsageCount prev + 1
                  , mprNetMdlGain = mprNetMdlGain prev + marginalGain
                  }
          in if mprNetMdlGain record >= threshold || mprUsageCount record >= 2
             then Map.insert mName record acc
             else acc

--------------------------------------------------------------------------------
-- 5. Waking Up Smarter: Injecting Crystallized Primitives into New Stalks
--------------------------------------------------------------------------------

-- | Enriches the stalk's `LiquidSig` and component map with all promoted measures
-- and sort-compatible `CrystallizedCombinator`s before starting the next synthesis run.
injectLibraryIntoStalkSig
  :: PersistentLibraryBank
  -> LiquidSig
  -> Map SymName RSchema
  -> (LiquidSig, Map SymName RSchema, [LiquidSymbolicStep])
injectLibraryIntoStalkSig PersistentLibraryBank{..} sig0 comps0 =
  let promotedRecords = Map.elems bankPromotedMeas
      newMeasures = Map.fromList
        [ (measureName (mprMeasure r), mprMeasure r) | r <- promotedRecords ]
      newAxioms = concatMap mprCtorAxioms promotedRecords
      newQuals = Set.fromList (map mprBoundaryQual promotedRecords)
      enrichedSig = sig0
        { sigMeasures   = Map.union newMeasures (sigMeasures sig0)
        , sigCtorAxioms = newAxioms ++ sigCtorAxioms sig0
        , sigQualifiers = Set.union newQuals (sigQualifiers sig0)
        }
      newSchemas = Map.map ccPolySchema bankCombinators
      enrichedComps = Map.union newSchemas comps0
      profunctorSteps = map ccSymbolicStep (Map.elems bankCombinators)
  in (enrichedSig, enrichedComps, profunctorSteps)
