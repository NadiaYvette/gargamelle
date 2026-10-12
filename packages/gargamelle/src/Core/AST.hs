module Core.AST where

-- Placeholder for the abstract syntax tree of the language
-- used in autonomous programming campaigns.

data Expr
  = Var String
  | Lam String Expr
  | App Expr Expr
  | Lit Int
  | Add Expr Expr
  deriving (Show, Eq)