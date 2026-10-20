{-# LANGUAGE GADTs #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE LambdaCase #-}

module Gargamelle.FOL.Z3
  ( SMTResult(..)
  , solveZ3Raw
  , formulaToSMTLib
  , checkFormulaZ3
  , verifyValidityZ3
  , parseZ3Model
  ) where

import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import System.Process (readProcessWithExitCode)
import GHC.TypeLits (symbolVal)

import FirstOrder (Formula(..), Term(..))
import Gargamelle.Model.Satisfaction (Evidence(..))

-- | Result of an SMT query.
data SMTResult
  = Sat (Map.Map String String)
  | Unsat
  | Unknown String
  deriving (Eq, Show)

-- | Collect all atomic predicate/constant names in a Formula to declare them in SMT-LIB2.
collectSymbols :: Formula syms -> Set.Set String
collectSymbols = \case
  TrueF          -> Set.empty
  FalseF         -> Set.empty
  Pred p args    -> Set.insert (symbolVal p) (Set.unions (map collectTermSymbols args))
  Not f          -> collectSymbols f
  And f1 f2      -> collectSymbols f1 `Set.union` collectSymbols f2
  Or f1 f2       -> collectSymbols f1 `Set.union` collectSymbols f2
  Impl f1 f2     -> collectSymbols f1 `Set.union` collectSymbols f2
  Forall _ f     -> collectSymbols f
  Exists _ f     -> collectSymbols f

collectTermSymbols :: Term -> Set.Set String
collectTermSymbols = \case
  Var v     -> Set.singleton v
  Const c   -> Set.singleton c
  Func f ts -> Set.insert f (Set.unions (map collectTermSymbols ts))

-- | Translate a Term to SMT-LIB2.
termToSMT :: Term -> String
termToSMT = \case
  Var v     -> v
  Const c   -> c
  Func f [] -> f
  Func f ts -> "(" ++ f ++ " " ++ unwords (map termToSMT ts) ++ ")"

-- | Translate a Formula to an SMT-LIB2 boolean expression.
exprToSMT :: Formula syms -> String
exprToSMT = \case
  TrueF       -> "true"
  FalseF      -> "false"
  Pred p []   -> symbolVal p
  Pred p args -> "(" ++ symbolVal p ++ " " ++ unwords (map termToSMT args) ++ ")"
  Not f       -> "(not " ++ exprToSMT f ++ ")"
  And f1 f2   -> "(and " ++ exprToSMT f1 ++ " " ++ exprToSMT f2 ++ ")"
  Or f1 f2    -> "(or " ++ exprToSMT f1 ++ " " ++ exprToSMT f2 ++ ")"
  Impl f1 f2  -> "(=> " ++ exprToSMT f1 ++ " " ++ exprToSMT f2 ++ ")"
  Forall p f  -> "(forall ((" ++ symbolVal p ++ " Bool)) " ++ exprToSMT f ++ ")"
  Exists p f  -> "(exists ((" ++ symbolVal p ++ " Bool)) " ++ exprToSMT f ++ ")"

-- | Format a formula into a complete self-contained SMT-LIB2 query script.
formulaToSMTLib :: Formula syms -> String
formulaToSMTLib f =
  let syms = collectSymbols f
      decls = unlines [ "(declare-const " ++ s ++ " Bool)" | s <- Set.toList syms ]
      assertion = "(assert " ++ exprToSMT f ++ ")\n"
  in "(set-logic ALL)\n" ++ decls ++ assertion ++ "(check-sat)\n(get-model)\n"

-- | Parse the output model from Z3 into a map of variable assignments.
parseZ3Model :: String -> Map.Map String String
parseZ3Model out =
  let extract ("(define-fun" : name : "()" : _type : val : rest) =
        let cleanVal = filter (`notElem` "()") val
        in (name, cleanVal) : extract rest
      extract (_ : rest) = extract rest
      extract [] = []
      tokens = words out
  in Map.fromList (extract tokens)

-- | Execute a raw SMT-LIB2 query script by piping directly into host Z3.
solveZ3Raw :: String -> IO SMTResult
solveZ3Raw script = do
  (_code, stdoutStr, stderrStr) <- readProcessWithExitCode "z3" ["-in", "-smt2"] script
  let cleanOut = filter (not . null) (lines stdoutStr)
  case cleanOut of
    ("sat" : _)     -> pure $ Sat (parseZ3Model stdoutStr)
    ("unsat" : _)   -> pure Unsat
    ("unknown" : _) -> pure $ Unknown "Z3 returned unknown"
    _               -> pure $ Unknown ("Z3 error: " ++ stderrStr ++ " | out: " ++ stdoutStr)

-- | Check satisfiability of a First-Order formula using host Z3.
checkFormulaZ3 :: Formula syms -> IO SMTResult
checkFormulaZ3 f = solveZ3Raw (formulaToSMTLib f)

-- | Formally verify validity of a formula:
-- Checks whether (not f) is unsatisfiable. If unsat, returns VerifiedSection.
-- If sat, the countermodel is returned as Evidence.
verifyValidityZ3 :: Formula syms -> IO Evidence
verifyValidityZ3 f = do
  let negated = Not f
  checkFormulaZ3 negated >>= \case
    Unsat -> pure VerifiedSection
    Sat model -> pure $ Counterexample "Z3-Countermodel" (show model)
    Unknown err -> pure $ Counterexample "Z3-Unknown" err
