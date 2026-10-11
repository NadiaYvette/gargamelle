{-# LANGUAGE DataKinds, TypeFamilies, GADTs, KindSignatures, PolyKinds, TypeOperators, FlexibleInstances, MultiParamTypeClasses #-}

module FirstOrder where

import Institution
import Data.Proxy
import GHC.TypeLits (Symbol, KnownSymbol, symbolVal)
import qualified Data.Map as Map
import qualified Folly.Formula as F

-- | A wrapper for first-order signatures (lists of function/predicate symbols).
-- We keep it phantom; the actual signature is not used in the formulas.
newtype FOLSig (syms :: [Symbol]) = FOLSig (Proxy syms)

-- | Terms: we use Folly's Term type.
type Term = F.Term

-- | Sentences: our own formula GADT built on top of Folly's terms.
data Formula (syms :: [Symbol]) where
  TrueF  :: Formula syms
  FalseF :: Formula syms
  Pred   :: KnownSymbol sym => Proxy sym -> [Term] -> Formula syms
  Not    :: Formula syms -> Formula syms
  And    :: Formula syms -> Formula syms -> Formula syms
  Or     :: Formula syms -> Formula syms -> Formula syms
  Impl   :: Formula syms -> Formula syms -> Formula syms
  Forall :: KnownSymbol sym => Proxy sym -> Formula syms -> Formula syms
  Exists :: KnownSymbol sym => Proxy sym -> Formula syms -> Formula syms

-- | Models: a mapping from predicate symbols to relations and function symbols to functions.
-- We use String keys (the symbol names) for simplicity.
-- For now, we only handle nullary predicates and constant functions (zero-arity).
data FOLModel (syms :: [Symbol]) = FOLModel
  { predicateInterpretation :: Map.Map String Bool
  , functionInterpretation  :: Map.Map String String -- very simplified: constant symbol name
  }

instance Institution (FOLSig syms) where
  type Sentence (FOLSig syms) = Formula syms
  type Model  (FOLSig syms)  = FOLModel syms
  satisfies _ m s = evalFormula m s

-- | Evaluate a closed formula in a simple model.
-- This only works for ground formulas (no variables) and ignores arity.
-- For predicates, we treat them as nullary and look up their interpretation.
-- For functions, we treat them as constant symbols and look up their interpretation.
-- This is a toy model; a real implementation would need to handle arity and recursion.
evalFormula :: FOLModel syms -> Formula syms -> Bool
evalFormula _ TrueF = True
evalFormula _ FalseF = False
evalFormula m (Pred p args) = 
  let key = symbolVal p
  in case Map.lookup key (predicateInterpretation m) of
       Just b -> b -- ignore args for now
       Nothing -> False
evalFormula m (Not f) = not (evalFormula m f)
evalFormula m (And f1 f2) = evalFormula m f1 && evalFormula m f2
evalFormula m (Or f1 f2)  = evalFormula m f1 || evalFormula m f2
evalFormula m (Impl f1 f2) = not (evalFormula m f1) || evalFormula m f2
evalFormula m (Forall p f) = undefined -- would need to enumerate domain
evalFormula m (Exists p f) = undefined

-- | Smart constructors for terms that take a KnownSymbol proxy.
varTerm :: KnownSymbol sym => Proxy sym -> Term
varTerm p = F.var (symbolVal p)

constTerm :: KnownSymbol sym => Proxy sym -> Term
constTerm p = F.constant (symbolVal p)

funAppTerm :: KnownSymbol sym => Proxy sym -> [Term] -> Term
funAppTerm p args = F.func (symbolVal p) args

-- | Smart constructors for formulas that take KnownSymbol proxies.
prop :: KnownSymbol sym => Proxy sym -> [Term] -> Formula syms
prop p args = Pred p args

neg :: Formula syms -> Formula syms
neg = Not

conj :: Formula syms -> Formula syms -> Formula syms
conj = And

disj :: Formula syms -> Formula syms -> Formula syms
disj = Or

impl :: Formula syms -> Formula syms -> Formula syms
impl = Impl

bicond :: Formula syms -> Formula syms -> Formula syms
bicond p q = Or (And p q) (And (Not p) (Not q))

forall :: KnownSymbol sym => Proxy sym -> Formula syms -> Formula syms
forall p f = Forall p f

exists :: KnownSymbol sym => Proxy sym -> Formula syms -> Formula syms
exists p f = Exists p f
