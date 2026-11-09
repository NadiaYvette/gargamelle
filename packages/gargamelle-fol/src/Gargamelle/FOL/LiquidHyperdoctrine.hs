{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}

module Gargamelle.FOL.LiquidHyperdoctrine
  ( -- * Context & Formula AST
    Context (..)
  , FOLFormula (..)
    -- * Qualifier Basis & Conjunctions
  , QualifierBasis (..)
  , QualifierConj (..)
    -- * Hyperdoctrine Typeclasses
  , Hyperdoctrine (..)
  , LiquidSubHyperdoctrine (..)
    -- * Galois Adjoints
  , strongGaloisConsequence
  , weakGaloisImplicant
    -- * Concrete Z3 Instance
  , Z3Hyperdoctrine (..)
    -- * Helper functions
  , folFormulaToSMTLib
  , substPredInFOL
  ) where

import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Set (Set)
import qualified Data.Set as Set
import qualified Data.Text as T

import Gargamelle.Core.Institution.Liquid
import Gargamelle.FOL.LiquidBridge (liquidPredToSMTLib)
import Gargamelle.FOL.Z3 (SMTResult (..), solveZ3Raw)

-- | Categorical logic context Gamma: Map from variable symbol to liquid sort.
newtype Context = Context { unContext :: Map SymName LiquidSort }
  deriving (Eq, Ord, Show)

-- | First-order logic formula fibered over contexts.
data FOLFormula
  = FTrue
  | FFalse
  | FAtom LiquidPred
  | FAnd [FOLFormula]
  | FOr [FOLFormula]
  | FImplies FOLFormula FOLFormula
  | FExists SymName LiquidSort FOLFormula
  | FForall SymName LiquidSort FOLFormula
  | FNot FOLFormula
  deriving (Eq, Ord, Show)

-- | Finite basis of Synquid qualifier templates.
newtype QualifierBasis = QualifierBasis { qbQualifiers :: Set Qualifier }
  deriving (Eq, Ord, Show)

-- | Conjunction of instantiated liquid predicates from the qualifier lattice.
newtype QualifierConj = QualifierConj { qcConjuncts :: Set LiquidPred }
  deriving (Eq, Ord, Show)

-- | Lawvere Hyperdoctrine interface fibered over sorted contexts.
class Hyperdoctrine h where
  -- | Pullback / substitution morphism: sigma* : P(Gamma) -> P(Gamma')
  pullback :: Map SymName LiquidPred -> FOLFormula -> FOLFormula

  -- | Entailment check: Gamma |- phi => psi
  entails :: Context -> FOLFormula -> FOLFormula -> IO Bool

-- | Sub-hyperdoctrine embedding finite distributive qualifier lattices into FOL fibers.
class Hyperdoctrine h => LiquidSubHyperdoctrine h where
  -- | Instantiates qualifier templates in context Gamma over candidate scope variables.
  instantiateBasis :: Context -> QualifierBasis -> [QualifierConj]

  -- | Canonical embedding functor i_Gamma : Q_Gamma -> FOL_Gamma.
  embedQualifier :: QualifierConj -> FOLFormula

-- | Left Adjoint: alpha_Gamma^strong(phi) -| i_Gamma
-- Computes the strongest qualifier conjunction entailed by phi (Houdini strengthening).
-- That is: { q in Basis | phi entails q }.
-- By construction, phi entails /\\ { q | phi entails q }, and whenever phi entails q',
-- every conjunct in q' is entailed by phi, so {q'} subset-of {q in Basis | phi entails q}.
strongGaloisConsequence
  :: forall h. LiquidSubHyperdoctrine h
  => Context
  -> QualifierBasis
  -> FOLFormula
  -> IO QualifierConj
strongGaloisConsequence ctx basis phi = do
  let candidates = instantiateBasis @h ctx basis
      allPreds = Set.toList (Set.unions (map qcConjuncts candidates))
  -- Filter predicates q such that phi entails q
  validPreds <- filterM (entails @h ctx phi . FAtom) allPreds
  pure $ QualifierConj (Set.fromList validPreds)
  where
    filterM _ [] = pure []
    filterM p (x:xs) = do
      flg <- p x
      rest <- filterM p xs
      pure (if flg then x : rest else rest)

-- | Right Adjoint: i_Gamma -| alpha_Gamma^weak(psi)
-- Computes the weakest qualifier conjunction that entails psi (Synquid condition abduction).
-- Returns Just q if there exists a qualifier conjunction q such that i(q) entails psi,
-- choosing the weakest (minimal conjuncts) valid candidate. If none entails psi, returns Nothing.
weakGaloisImplicant
  :: forall h. LiquidSubHyperdoctrine h
  => Context
  -> QualifierBasis
  -> FOLFormula
  -> IO (Maybe QualifierConj)
weakGaloisImplicant ctx basis psi = do
  let candidates = instantiateBasis @h ctx basis
      -- Sort candidates by ascending size (fewer conjuncts = logically weaker)
      sortedCandidates = sortCandidates candidates
  findFirstValid sortedCandidates
  where
    sortCandidates = id -- Candidates generated from powerset / subsets or individual conjunctions

    findFirstValid [] = pure Nothing
    findFirstValid (c:cs) = do
      valid <- entails @h ctx (embedQualifier @h c) psi
      if valid
        then pure (Just c)
        else findFirstValid cs

--------------------------------------------------------------------------------
-- Standard Z3 Hyperdoctrine Instance
--------------------------------------------------------------------------------

data Z3Hyperdoctrine = Z3Hyperdoctrine

-- | Substitution in LiquidPred.
substLiquidPred :: Map SymName LiquidPred -> LiquidPred -> LiquidPred
substLiquidPred sMap = \case
  PTrue -> PTrue
  PFalse -> PFalse
  PVar v -> case Map.lookup v sMap of
    Just replacement -> replacement
    Nothing -> PVar v
  PIntLit n -> PIntLit n
  PEmptySet s -> PEmptySet s
  PMeasureApp m e -> PMeasureApp m (substLiquidPred sMap e)
  PFieldProj l e -> PFieldProj l (substLiquidPred sMap e)
  PVariantTag t e -> PVariantTag t (substLiquidPred sMap e)
  PBinOp op l r -> PBinOp op (substLiquidPred sMap l) (substLiquidPred sMap r)
  PRel op l r -> PRel op (substLiquidPred sMap l) (substLiquidPred sMap r)
  PNot e -> PNot (substLiquidPred sMap e)
  PAnd es -> PAnd (map (substLiquidPred sMap) es)
  POr es -> POr (map (substLiquidPred sMap) es)
  PImplies l r -> PImplies (substLiquidPred sMap l) (substLiquidPred sMap r)
  PIff l r -> PIff (substLiquidPred sMap l) (substLiquidPred sMap r)
  PLiquidHole h vs -> PLiquidHole h vs

-- | Pullback term substitution into FOLFormula.
substPredInFOL :: Map SymName LiquidPred -> FOLFormula -> FOLFormula
substPredInFOL sMap = \case
  FTrue -> FTrue
  FFalse -> FFalse
  FAtom p -> FAtom (substLiquidPred sMap p)
  FAnd fs -> FAnd (map (substPredInFOL sMap) fs)
  FOr fs -> FOr (map (substPredInFOL sMap) fs)
  FImplies f1 f2 -> FImplies (substPredInFOL sMap f1) (substPredInFOL sMap f2)
  FNot f -> FNot (substPredInFOL sMap f)
  FExists v s f ->
    let sMap' = Map.delete v sMap
    in FExists v s (substPredInFOL sMap' f)
  FForall v s f ->
    let sMap' = Map.delete v sMap
    in FForall v s (substPredInFOL sMap' f)

sortToSMTLib :: LiquidSort -> String
sortToSMTLib = \case
  SortInt -> "Int"
  SortBool -> "Bool"
  SortSet _ -> "Int"
  SortVar tv -> T.unpack tv
  SortADT name _
    | "RecordF_" `T.isPrefixOf` name || "VariantF_" `T.isPrefixOf` name -> "Int"
    | otherwise -> T.unpack name
  SortRecordRow _ -> "Int"
  SortVariantRow _ -> "Int"
  SortEffectRow _ -> "Int"

-- | Translate FOLFormula to SMT-LIB2 string.
folFormulaToSMTLib :: FOLFormula -> String
folFormulaToSMTLib = \case
  FTrue -> "true"
  FFalse -> "false"
  FAtom p -> liquidPredToSMTLib p
  FAnd [] -> "true"
  FAnd [f] -> folFormulaToSMTLib f
  FAnd fs -> "(and " ++ unwords (map folFormulaToSMTLib fs) ++ ")"
  FOr [] -> "false"
  FOr [f] -> folFormulaToSMTLib f
  FOr fs -> "(or " ++ unwords (map folFormulaToSMTLib fs) ++ ")"
  FImplies f1 f2 -> "(=> " ++ folFormulaToSMTLib f1 ++ " " ++ folFormulaToSMTLib f2 ++ ")"
  FNot f -> "(not " ++ folFormulaToSMTLib f ++ ")"
  FExists v s f ->
    "(exists ((" ++ T.unpack v ++ " " ++ sortToSMTLib s ++ ")) " ++ folFormulaToSMTLib f ++ ")"
  FForall v s f ->
    "(forall ((" ++ T.unpack v ++ " " ++ sortToSMTLib s ++ ")) " ++ folFormulaToSMTLib f ++ ")"

collectFreeVarsInFOL :: FOLFormula -> Set SymName
collectFreeVarsInFOL = \case
  FTrue -> Set.empty
  FFalse -> Set.empty
  FAtom p -> collectFreeVarsInPred p
  FAnd fs -> Set.unions (map collectFreeVarsInFOL fs)
  FOr fs -> Set.unions (map collectFreeVarsInFOL fs)
  FImplies f1 f2 -> collectFreeVarsInFOL f1 `Set.union` collectFreeVarsInFOL f2
  FNot f -> collectFreeVarsInFOL f
  FExists v _ f -> Set.delete v (collectFreeVarsInFOL f)
  FForall v _ f -> Set.delete v (collectFreeVarsInFOL f)

collectFreeVarsInPred :: LiquidPred -> Set SymName
collectFreeVarsInPred = \case
  PTrue -> Set.empty
  PFalse -> Set.empty
  PVar v -> Set.singleton v
  PIntLit _ -> Set.empty
  PEmptySet _ -> Set.empty
  PMeasureApp _ e -> collectFreeVarsInPred e
  PFieldProj _ e -> collectFreeVarsInPred e
  PVariantTag _ e -> collectFreeVarsInPred e
  PBinOp _ l r -> collectFreeVarsInPred l `Set.union` collectFreeVarsInPred r
  PRel _ l r -> collectFreeVarsInPred l `Set.union` collectFreeVarsInPred r
  PNot e -> collectFreeVarsInPred e
  PAnd es -> Set.unions (map collectFreeVarsInPred es)
  POr es -> Set.unions (map collectFreeVarsInPred es)
  PImplies l r -> collectFreeVarsInPred l `Set.union` collectFreeVarsInPred r
  PIff l r -> collectFreeVarsInPred l `Set.union` collectFreeVarsInPred r
  PLiquidHole _ vs -> Set.fromList vs

collectMeasureNamesInFOL :: FOLFormula -> Set SymName
collectMeasureNamesInFOL = \case
  FTrue -> Set.empty
  FFalse -> Set.empty
  FAtom p -> collectMeasureNamesInPred p
  FAnd fs -> Set.unions (map collectMeasureNamesInFOL fs)
  FOr fs -> Set.unions (map collectMeasureNamesInFOL fs)
  FImplies f1 f2 -> collectMeasureNamesInFOL f1 `Set.union` collectMeasureNamesInFOL f2
  FNot f -> collectMeasureNamesInFOL f
  FExists _ _ f -> collectMeasureNamesInFOL f
  FForall _ _ f -> collectMeasureNamesInFOL f

collectMeasureNamesInPred :: LiquidPred -> Set SymName
collectMeasureNamesInPred = \case
  PTrue -> Set.empty
  PFalse -> Set.empty
  PVar _ -> Set.empty
  PIntLit _ -> Set.empty
  PEmptySet _ -> Set.empty
  PMeasureApp m e -> Set.insert m (collectMeasureNamesInPred e)
  PFieldProj _ e -> collectMeasureNamesInPred e
  PVariantTag _ e -> collectMeasureNamesInPred e
  PBinOp _ l r -> collectMeasureNamesInPred l `Set.union` collectMeasureNamesInPred r
  PRel _ l r -> collectMeasureNamesInPred l `Set.union` collectMeasureNamesInPred r
  PNot e -> collectMeasureNamesInPred e
  PAnd es -> Set.unions (map collectMeasureNamesInPred es)
  POr es -> Set.unions (map collectMeasureNamesInPred es)
  PImplies l r -> collectMeasureNamesInPred l `Set.union` collectMeasureNamesInPred r
  PIff l r -> collectMeasureNamesInPred l `Set.union` collectMeasureNamesInPred r
  PLiquidHole _ _ -> Set.empty

instance Hyperdoctrine Z3Hyperdoctrine where
  pullback = substPredInFOL

  -- | Check Gamma |- phi => psi by asserting Context decls, measure fun decls, and (phi /\ not psi), checking UNSAT.
  entails (Context env) phi psi = do
    let vc = FAnd [phi, FNot psi]
        measures = collectMeasureNamesInFOL vc
        measDecls = unlines
          [ "(declare-fun " ++ T.unpack m ++ " (Int) Int)"
          | m <- Set.toList measures
          ]
        fvs = collectFreeVarsInFOL vc
        envVars = Map.keysSet env
        extraVars = Set.difference fvs envVars
        extraDecls = unlines
          [ "(declare-const " ++ T.unpack v ++ " Int)"
          | v <- Set.toList extraVars
          ]
        decls = unlines
          [ "(declare-const " ++ T.unpack v ++ " " ++ sortToSMTLib s ++ ")"
          | (v, s) <- Map.toList env
          ]
        smtVc = folFormulaToSMTLib vc
        query = "(set-logic ALL)\n" ++ measDecls ++ extraDecls ++ decls ++ "(assert " ++ smtVc ++ ")\n(check-sat)\n"
    res <- solveZ3Raw query
    case res of
      Unsat -> pure True
      _     -> pure False

-- | Power set helper to build conjunction combinations.
subsequencesList :: [a] -> [[a]]
subsequencesList [] = [[]]
subsequencesList (x:xs) =
  let rest = subsequencesList xs
  in rest ++ map (x:) rest

instance LiquidSubHyperdoctrine Z3Hyperdoctrine where
  instantiateBasis (Context env) (QualifierBasis quals) =
    let vars = Map.keys env
        instantiateQual qual =
          case qualParams qual of
            [] -> [qualBody qual]
            [(pName, _)] ->
              [ substLiquidPred (Map.singleton pName (PVar v)) (qualBody qual) | v <- vars ]
            _ -> [qualBody qual]
        groundPreds = Set.toList (Set.fromList (concatMap instantiateQual (Set.toList quals)))
        -- Power set of ground predicates, ordered by length so weakest (fewest conjuncts) come first
        allSubsets = subsequencesList groundPreds
    in map (QualifierConj . Set.fromList) allSubsets

  embedQualifier (QualifierConj conjuncts) =
    case Set.toList conjuncts of
      [] -> FTrue
      [p] -> FAtom p
      ps -> FAnd (map FAtom ps)
