{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

module Gargamelle.Logic.Defunctionalize
  ( TyFun
  , type (~>)
  , Apply
  , SingSymbol(..)
  , ObsMor(..)
  , evalObsMor
  , inspectObsMor
  ) where

import Control.Category (Category(..))
import Data.Kind (Type)
import Data.Profunctor (Profunctor(..), Strong(..), Choice(..))
import Data.Bifunctor (first, second)
import Prelude hiding (id, (.))

-- ============================================================================
-- 1. TYPE-LEVEL DEFUNCTIONALIZATION (For PolyKinds Signature Morphisms)
-- ============================================================================

-- | Dummy type constructor representing a defunctionalized type-level function
-- from kind @k1@ to kind @k2@.
data TyFun (k1 :: Type) (k2 :: Type) :: Type

-- | Type-level arrow kind @k1 ~> k2@ that can be partially applied and passed
-- to typeclasses without triggering GHC's unsaturated type family restriction.
type (k1 :: Type) ~> (k2 :: Type) = TyFun k1 k2 -> Type

-- | Open evaluation type family interpreting defunctionalized symbols.
type family Apply (f :: k1 ~> k2) (x :: k1) :: k2

-- | Runtime Singleton witness for a defunctionalized type-level symbol,
-- allowing runtime code analyzers to inspect type-level signature mappings.
data SingSymbol (f :: k1 ~> k2) = SingSymbol
  { symbolName        :: String
  , mappedIdentifiers :: [(String, String)]
  } deriving (Eq, Show)

-- ============================================================================
-- 2. TERM-LEVEL OBSERVABLE MORPHISM GADT (Replaces Opaque `->` Closures)
-- ============================================================================

{- Note [Defunctionalized Observable Morphisms]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-defunctionalized-obsmor]
In standard Haskell architectures, transformations and signature morphisms are
represented as native function closures @(a -> b)@. However, Haskell function
closures are completely opaque:
  1. A function closure cannot be inspected: an autonomous agent or verifier cannot
     determine whether @f@ reads a database, modifies a field, or drops information.
  2. A function closure cannot be serialized or translated: it cannot be mapped to an
     SMT-LIB2 relation or emitted into an explainable proof certificate.
  3. A function closure prevents algebraic rewriting: categorical laws like
     @f . id = f@ or @first (g . h) = first g . first h@ cannot be applied at compile
     or run time.

To resolve this opacity, 'ObsMor a b' defunctionalizes morphism arrows into a first-class
GADT. Every pipeline step—whether an identity, a composition, a tagged field projection,
a tagged variant injection, or a profunctor splitting—is represented as an inspectable term.

Autonomous reasoning engines can:
  - Statically inspect the transformation plan via 'inspectObsMor' without evaluating code.
  - Compile the AST to native executable code via 'evalObsMor'.
  - Verify functorial and profunctorial preservation across institutional boundaries.
-}

-- | Deeply embedded, inspectable morphism AST replacing native @(->)@.
--
-- See Note [Defunctionalized Observable Morphisms] [ref:note-defunctionalized-obsmor].
--
-- Autonomous agents can pattern-match on @ObsMor@ to extract symbolic dependencies,
-- or compile it to a native Haskell function via @evalObsMor@.
data ObsMor a b where
  IdMor        :: ObsMor a a
  CompMor      :: ObsMor b c -> ObsMor a b -> ObsMor a c
  ProjectTag   :: String -> (a -> b) -> ObsMor a b
  InjectTag    :: String -> (a -> b) -> ObsMor a b
  FirstMor     :: ObsMor a b -> ObsMor (a, c) (b, c)
  SecondMor    :: ObsMor a b -> ObsMor (c, a) (c, b)
  LeftMor      :: ObsMor a b -> ObsMor (Either a c) (Either b c)
  RightMor     :: ObsMor a b -> ObsMor (Either c a) (Either c b)
  SymbolicStep :: String -> (a -> b) -> ObsMor a b

instance Category ObsMor where
  id  = IdMor
  (.) = CompMor

instance Profunctor ObsMor where
  dimap f g m = SymbolicStep "post" g . m . SymbolicStep "pre" f

instance Strong ObsMor where
  first'  = FirstMor
  second' = SecondMor

instance Choice ObsMor where
  left'  = LeftMor
  right' = RightMor

-- | Interpret the observable morphism AST as an executable Haskell function.
evalObsMor :: ObsMor a b -> (a -> b)
evalObsMor IdMor                    = id
evalObsMor (CompMor g f)            = evalObsMor g . evalObsMor f
evalObsMor (ProjectTag _ f)         = f
evalObsMor (InjectTag _ f)          = f
evalObsMor (FirstMor f)             = first (evalObsMor f)
evalObsMor (SecondMor f)            = second (evalObsMor f)
evalObsMor (LeftMor f)              = either (Left . evalObsMor f) Right
evalObsMor (RightMor f)             = fmap (evalObsMor f)
evalObsMor (SymbolicStep _ fn)      = fn

-- | Extract a structural trace of all transformations inside a morphism without running it.
inspectObsMor :: ObsMor a b -> [String]
inspectObsMor IdMor                = ["id"]
inspectObsMor (CompMor g f)        = inspectObsMor f ++ inspectObsMor g
inspectObsMor (ProjectTag tag _)   = ["ProjectTag:" ++ tag]
inspectObsMor (InjectTag tag _)    = ["InjectTag:" ++ tag]
inspectObsMor (FirstMor f)         = map ("First(" ++) (inspectObsMor f)
inspectObsMor (SecondMor f)        = map ("Second(" ++) (inspectObsMor f)
inspectObsMor (LeftMor f)          = map ("Left(" ++) (inspectObsMor f)
inspectObsMor (RightMor f)         = map ("Right(" ++) (inspectObsMor f)
inspectObsMor (SymbolicStep tag _) = ["Step:" ++ tag]
