{-# LANGUAGE DataKinds, TypeFamilies, GADTs, PolyKinds, FlexibleInstances, MultiParamTypeClasses, BlockArguments #-}

module FirstOrder where

import Institution
import Data.Proxy
import GHC.TypeLits (Symbol, KnownSymbol, symbolVal)
import qualified Data.Map as Map
import qualified Data.Set as Set

-- | Native First-Order Terms: variables, constants, and function applications.
data Term
  = Var String
  | Const String
  | Func String [Term]
  deriving (Eq, Ord, Show)

isVar :: Term -> Bool
isVar (Var _) = True
isVar _       = False

varName :: Term -> String
varName (Var v) = v
varName _       = error "FirstOrder.varName: not a variable"

isConst :: Term -> Bool
isConst (Const _) = True
isConst _         = False

isFunc :: Term -> Bool
isFunc (Func _ _) = True
isFunc _          = False

funcName :: Term -> String
funcName (Const c)  = c
funcName (Func f _) = f
funcName _          = error "FirstOrder.funcName: not a function or constant"

funcArgs :: Term -> [Term]
funcArgs (Func _ args) = args
funcArgs _             = []

var :: String -> Term
var = Var

constant :: String -> Term
constant = Const

func :: String -> [Term] -> Term
func = Func

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

-- | Models: a mapping from predicate symbols to relations and function symbols to functions,
-- plus a Herbrand universe of constants (as strings) for quantifier evaluation.
-- We use String keys (the symbol names) for simplicity.
-- Constants are represented as Strings.
-- For a predicate of arity n, the relation is a Set of n-tuples of Strings.
-- For a function of arity n, the function maps an n-tuple of Strings to a String.
data FOLModel (xs :: [Symbol]) = FOLModel
  { predicateInterpretation :: Map.Map String (Set.Set [String])
  , functionInterpretation  :: Map.Map String ([String] -> String)
  , constants               :: Set.Set String -- the Herbrand universe of constants
  }

-- | A wrapper for first-order signatures (lists of function/predicate symbols).
-- We keep it phantom; the actual signature is not used in the formulas.
newtype FOLSig (syms :: [Symbol]) = FOLSig (Proxy syms)

instance Institution (FOLSig syms) where
  type Sentence (FOLSig syms) = Formula syms
  type Model  (FOLSig syms)  = FOLModel syms
  satisfies _ m s = case evalFormula m Map.empty s of
                      Right b -> b
                      Left _  -> False   -- treat errors as false

-- | Evaluate a term to a constant (String) given a model and an environment (variable assignment).
-- Returns Left error if a variable is not bound in the environment or if a function symbol is missing.
evalTerm :: FOLModel syms -> Map.Map String String -> Term -> Either String String
evalTerm m rho t
  | isVar t   = case Map.lookup (varName t) rho of
                    Just v -> Right v
                    Nothing -> Left $ "Undefined variable: " ++ varName t
  | isConst t = Right $ funcName t   -- constant: funcName gives the constant name
  | isFunc t  = do
      let f = funcName t
          args = funcArgs t
      argVals <- mapM (evalTerm m rho) args
      case Map.lookup f (functionInterpretation m) of
        Just fn   -> Right $ fn argVals
        Nothing   -> Left $ "Undefined function symbol: " ++ f
  | otherwise = Left "Unknown term construct"

-- | Evaluate a formula to a Boolean given a model and an environment (variable assignment).
-- Returns Left error if the formula is not closed (contains free variables) or if a predicate is missing.
evalFormula :: FOLModel syms -> Map.Map String String -> Formula syms -> Either String Bool
evalFormula _ _ TrueF = Right True
evalFormula _ _ FalseF = Right False
evalFormula m rho (Pred p args) = do
  argVals <- mapM (evalTerm m rho) args
  case Map.lookup (symbolVal p) (predicateInterpretation m) of
    Just rel -> Right $ Set.member argVals rel
    Nothing  -> Left $ "Undefined predicate symbol: " ++ symbolVal p
evalFormula m rho (Not f) = do
  b <- evalFormula m rho f
  Right $ not b
evalFormula m rho (And f1 f2) = do
  b1 <- evalFormula m rho f1
  b2 <- evalFormula m rho f2
  Right $ b1 && b2
evalFormula m rho (Or f1 f2) = do
  b1 <- evalFormula m rho f1
  b2 <- evalFormula m rho f2
  Right $ b1 || b2
evalFormula m rho (Impl f1 f2) = do
  b1 <- evalFormula m rho f1
  b2 <- evalFormula m rho f2
  Right $ not b1 || b2
evalFormula m rho (Forall p f) = do
  let vName = symbolVal p
      results = map (\c -> evalFormula m (Map.insert vName c rho) f) (Set.toList (constants m))
  case results of
    (Left err : _) -> Left err
    (Right False : _) -> Right False
    (Right True : rs) -> if all (== Right True) rs
                           then Right True
                           else Left "Unexpected error in quantifier evaluation"
    [] -> Left "No constants in Herbrand universe for universal quantifier"
evalFormula m rho (Exists p f) = do
  let vName = symbolVal p
      results = map (\c -> evalFormula m (Map.insert vName c rho) f) (Set.toList (constants m))
  case results of
    (Left err : _) -> Left err
    (Right True : _) -> Right True
    (Right False : rs) -> if all (== Right False) rs
                            then Right False
                            else Left "Unexpected error in quantifier evaluation"
    [] -> Left "No constants in Herbrand universe for existential quantifier"

-- | Smart constructors for terms that take a KnownSymbol proxy.
varTerm :: KnownSymbol sym => Proxy sym -> Term
varTerm p = var (symbolVal p)

constTerm :: KnownSymbol sym => Proxy sym -> Term
constTerm p = constant (symbolVal p)

funAppTerm :: KnownSymbol sym => Proxy sym -> [Term] -> Term
funAppTerm p = func (symbolVal p)

-- | Smart constructors for formulas that take KnownSymbol proxies.
prop :: KnownSymbol sym => Proxy sym -> [Term] -> Formula syms
prop = Pred

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

forallFOL :: KnownSymbol sym => Proxy sym -> Formula syms -> Formula syms
forallFOL = Forall

existsFOL :: KnownSymbol sym => Proxy sym -> Formula syms -> Formula syms
existsFOL = Exists
