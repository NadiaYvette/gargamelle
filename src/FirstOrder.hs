{-# LANGUAGE DataKinds, TypeFamilies, GADTs, KindSignatures, PolyKinds, TypeOperators, FlexibleInstances, MultiParamTypeClasses #-}

module FirstOrder where

import Institution
import Data.Proxy
import GHC.TypeLits (Symbol, KnownSymbol, symbolVal)
import qualified Data.Map as Map

-- | A wrapper for first-order signatures (lists of function/predicate symbols).
newtype FOLSig (syms :: [Symbol]) = FOLSig (Proxy syms)

-- | Sentences: we define a simple GADT for formulas indexed by the symbol list.
data Formula (syms :: [Symbol]) where
  TrueF  :: Formula syms
  FalseF :: Formula syms
  Pred   :: KnownSymbol sym => Proxy sym -> [Term syms] -> Formula syms
  Not    :: Formula syms -> Formula syms
  And    :: Formula syms -> Formula syms -> Formula syms
  Or     :: Formula syms -> Formula syms -> Formula syms
  Impl   :: Formula syms -> Formula syms -> Formula syms
  Forall :: KnownSymbol sym => Proxy sym -> Formula syms -> Formula syms
  Exists :: KnownSymbol sym => Proxy sym -> Formula syms -> Formula syms

-- | Terms: variables, constants, function application.
data Term (syms :: [Symbol]) where
  Var   :: KnownSymbol sym => Proxy sym -> Term syms
  Const :: KnownSymbol sym => Proxy sym -> Term syms
  FunApp :: KnownSymbol sym => Proxy sym -> [Term syms] -> Term syms

-- | Models: a mapping from predicate symbols to relations and function symbols to functions.
-- We use String keys (the symbol names) for simplicity.
data FOLModel (syms :: [Symbol]) = FOLModel
  { predicateInterpretation :: Map.Map String Bool
  , functionInterpretation  :: Map.Map String String -- very simplified: constant symbol name
  }

instance Institution (FOLSig syms) where
  type Sentence (FOLSig syms) = Formula syms
  type Model  (FOLSig syms)  = FOLModel syms
  satisfies _ m s = evalFormula m s

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
