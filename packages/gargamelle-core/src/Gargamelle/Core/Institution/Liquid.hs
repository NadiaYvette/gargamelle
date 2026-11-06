{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}

module Gargamelle.Core.Institution.Liquid
  ( -- * Sorts, Measures, and Qualifiers
    SymName
  , LiquidSort (..)
  , RowSchema (..)
  , MeasureDecl (..)
  , CtorMeasureAxiom (..)
  , Qualifier (..)
    -- * Liquid Predicates & Refinement Types
  , LiquidPred (..)
  , BinOp (..)
  , RelOp (..)
  , RBase (..)
  , RType (..)
  , RPredPost
  , RSchema (..)
    -- * Institution Components
  , LiquidSig (..)
  , LiquidSigMorphism (..)
  , LiquidSentence (..)
  , LiquidModel (..)
  , LiquidVal (..)
  ) where

import Data.Map.Strict (Map)
import Data.Set (Set)
import Data.Text (Text)
import GHC.Generics (Generic)

type SymName = Text

--------------------------------------------------------------------------------
-- 1. Decidable Sorts & Polytropos/Penelope Bridges
--------------------------------------------------------------------------------

-- | Sorts restricted to decidable SMT fragments (QF_LIA, QF_UF, QF_S)
-- plus structural bridges for Polytropos rows and Penelope effect rows.
data LiquidSort
  = SortInt
  | SortBool
  | SortSet LiquidSort
  | SortVar SymName
  | SortADT SymName [LiquidSort]
  | SortRecordRow RowSchema
  -- ^ Polytropos RecordF row schema
  | SortVariantRow RowSchema
  -- ^ Polytropos VariantF row schema
  | SortEffectRow [SymName]
  -- ^ Penelope effect row capabilities
  deriving stock (Eq, Ord, Show, Generic)

newtype RowSchema = RowSchema
  { unRowSchema :: Map SymName LiquidSort
  } deriving stock (Eq, Ord, Show, Generic)

-- | A structural measure (e.g., len :: List a -> Int, elems :: Tree a -> Set a).
-- In SMT, measures are uninterpreted functions constrained by constructor axioms.
data MeasureDecl = MeasureDecl
  { measureName        :: SymName
  , measureDomain      :: LiquidSort
  , measureRange       :: LiquidSort
  , measureWellFounded :: Bool -- ^ True if decreasing this measure proves termination
  } deriving stock (Eq, Ord, Show, Generic)

-- | Connects an ADT or Polytropos Variant/Record constructor to its measure semantics.
-- Example: len(Cons(x, xs)) == 1 + len(xs)
data CtorMeasureAxiom = CtorMeasureAxiom
  { axiomCtor    :: SymName
  , axiomParams  :: [(SymName, LiquidSort)]
  , axiomMeasure :: SymName
  , axiomBody    :: LiquidPred
  } deriving stock (Eq, Ord, Show, Generic)

-- | Synquid Qualifier template Q(v, x_1, ..., x_k) for predicate abduction
-- and Horn clause solving.
data Qualifier = Qualifier
  { qualName   :: SymName
  , qualParams :: [(SymName, LiquidSort)]
  , qualBody   :: LiquidPred
  } deriving stock (Eq, Ord, Show, Generic)

--------------------------------------------------------------------------------
-- 2. Quantifier-Free Liquid Predicates & Refinement Types
--------------------------------------------------------------------------------

data BinOp = Add | Sub | Mul | SetUnion | SetIntersect | SetDiff
  deriving stock (Eq, Ord, Show, Generic)

data RelOp = Eq | Neq | Lt | Le | Gt | Ge | SetMember | SetSubset
  deriving stock (Eq, Ord, Show, Generic)

-- | Quantifier-free formula language over linear arithmetic, sets, and measures.
data LiquidPred
  = PTrue
  | PFalse
  | PVar SymName
  | PIntLit Integer
  | PEmptySet LiquidSort
  | PMeasureApp SymName LiquidPred
  -- ^ Uninterpreted measure application m(e)
  | PFieldProj SymName LiquidPred
  -- ^ Polytropos record field projection e.l
  | PVariantTag SymName LiquidPred
  -- ^ Polytropos variant active tag test is_Tag(e)
  | PBinOp BinOp LiquidPred LiquidPred
  | PRel RelOp LiquidPred LiquidPred
  | PNot LiquidPred
  | PAnd [LiquidPred]
  | POr [LiquidPred]
  | PImplies LiquidPred LiquidPred
  | PIff LiquidPred LiquidPred
  | PLiquidHole SymName [SymName]
  -- ^ Unknown liquid predicate variable kappa(v, x...)
  deriving stock (Eq, Ord, Show, Generic)

-- | Base refinement type: { v : T | phi(v) }
data RBase = RBase
  { rValueVar :: SymName
  -- ^ Typically "v"
  , rSort     :: LiquidSort
  , rRefine   :: LiquidPred
  } deriving stock (Eq, Ord, Show, Generic)

-- | Synquid Refinement Types extended with Penelope effect rows.
data RType
  = RBScalar RBase
  | RArrow SymName RType RType
  -- ^ Dependent arrow x:T1 -> T2
  | REffect [SymName] RBase RPredPost
  -- ^ Penelope effectful computation: Eff es {v:T | pre} {v:T | post}
  deriving stock (Eq, Ord, Show, Generic)

type RPredPost = LiquidPred

-- | Polymorphic refinement schema (quantifying over type/row variables).
data RSchema = RSchema
  { schemaTypeVars :: [SymName]
  , schemaBody     :: RType
  } deriving stock (Eq, Ord, Show, Generic)

--------------------------------------------------------------------------------
-- 3. Signature, Morphisms, Sentences, and Models
--------------------------------------------------------------------------------

-- | A Liquid Signature represents the static & local synthesis context at a hole.
data LiquidSig = LiquidSig
  { sigSorts       :: Set SymName
  , sigMeasures    :: Map SymName MeasureDecl
  , sigCtorAxioms  :: [CtorMeasureAxiom]
  , sigQualifiers  :: Set Qualifier
  , sigEnv         :: Map SymName RType
  -- ^ Refinement typing environment Gamma
  , sigPathCond    :: [LiquidPred]
  -- ^ Active branch guards (path conditions)
  } deriving stock (Eq, Ord, Show, Generic)

-- | Morphism sigma : Sig1 -> Sig2.
-- Models variable renaming, context weakening (Gamma -> Gamma, x:T),
-- type/row instantiation, and sheaf stalk restriction.
data LiquidSigMorphism = LiquidSigMorphism
  { morphSource  :: LiquidSig
  , morphTarget  :: LiquidSig
  , morphSortMap :: Map SymName LiquidSort
  , morphVarMap  :: Map SymName SymName
  , morphMeasMap :: Map SymName SymName
  } deriving stock (Eq, Ord, Show, Generic)

-- | Sentences generated by Synquid's bidirectional liquid type checker.
data LiquidSentence
  -- | Subtyping VC: Gamma, PathCond |- {v : S | phi} <: {v : S | psi}
  = SenSubtype
    { subValueVar :: SymName
    , subSort     :: LiquidSort
    , subLhs      :: LiquidPred
    , subRhs      :: LiquidPred
    }
  -- | Termination VC: Gamma, PathCond |- measure(arg_rec) < measure(param_init) && >= 0
  | SenTermination
    { termMeasure      :: SymName
    , termRecursiveArg :: LiquidPred
    , termInitialParam :: LiquidPred
    }
  -- | Condition Abduction Query: Find qualifier conjunction P over abductScopeVars
  -- such that (Gamma && PathCond && P => abductGoal) and (Gamma && PathCond && P is SAT).
  | SenAbduction
    { abductHoleId    :: SymName
    , abductScopeVars :: [SymName]
    , abductGoal      :: LiquidPred
    }
  deriving stock (Eq, Ord, Show, Generic)

-- | Runtime/SMT valuation for Liquid sorts.
data LiquidVal
  = VInt Integer
  | VBool Bool
  | VSet (Set LiquidVal)
  | VADT SymName [LiquidVal]
  | VRecord (Map SymName LiquidVal)
  | VVariant SymName LiquidVal
  deriving stock (Eq, Ord, Show, Generic)

-- | A Model M in Mod(Sigma) interprets environment bindings and measures.
data LiquidModel = LiquidModel
  { modelVarEnv        :: Map SymName LiquidVal
  , modelMeasureInterp :: Map (SymName, LiquidVal) LiquidVal
  , modelAbductSol     :: Map SymName LiquidPred -- ^ Solved liquid holes / abducted conditions
  } deriving stock (Eq, Ord, Show, Generic)
