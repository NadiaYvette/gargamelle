{-# LANGUAGE DataKinds, TypeFamilies, GADTs, KindSignatures, PolyKinds, TypeOperators, FlexibleInstances, MultiParamTypeClasses #-}

module Equational where

import Institution
import Data.Proxy
import GHC.TypeLits (Symbol, KnownSymbol, symbolVal)
import qualified Data.Map as Map
import Jukebox.Utils (usort) -- using a function from Jukebox to depend on the library

-- | A wrapper for equational signatures (lists of function symbols).
newtype EGSym (syms :: [Symbol]) = EGSym (Proxy syms)

-- | Terms: variables and function application.
data Term (syms :: [Symbol]) where
  Var   :: KnownSymbol sym => Proxy sym -> Term syms
  Const :: KnownSymbol sym => Proxy sym -> Term syms
  FunApp :: KnownSymbol sym => Proxy sym -> [Term syms] -> Term syms

-- | Equation: lhs = rhs
data Equation (syms :: [Symbol]) = Equation (Term syms) (Term syms)

-- | Model: an interpretation of function symbols as functions on a carrier set.
-- Simple toy model: carrier set is just [String] (constants as strings),
-- functions map list of strings (interpreted arguments) to string (interpreted result).
-- We use String keys for simplicity.
data EqModel (syms :: [Symbol]) = EqModel
  { carrier :: [String] -- list of constants in the signature (as strings)
  , interp  :: Map.Map String ( [String] -> String ) -- function from list of constants to constant
  }

instance Institution (EGSym syms) where
  type Sentence (EGSym syms) = Equation syms
  type Model  (EGSym syms)  = EqModel syms
  satisfies _ m (Equation lhs rhs) = evalTerm m lhs == evalTerm m rhs

evalTerm :: EqModel syms -> Term syms -> String
evalTerm m (Var x) = symbolVal x -- variable evaluates to its name (string)
evalTerm m (Const c) = symbolVal c
evalTerm m (FunApp f args) =
  let key = symbolVal f
      argVals = map (evalTerm m) args
  in case Map.lookup key (interp m) of
       Just func -> func argVals
       Nothing -> error ("undefined function: " ++ key)
