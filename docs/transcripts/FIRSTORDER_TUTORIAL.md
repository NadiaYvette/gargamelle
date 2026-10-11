# Tutorial: Using the FirstOrder Module for First-Order Logic

## Overview
This tutorial walks through the basics of using the `FirstOrder` module in the `programming-in-the-large` project to define and reason about first-order logic theories.

## Setting Up
First, ensure you have the project dependencies installed. You can build the project with:

```bash
cd /home/nyc/src/programming-in-the-large
cabal build
```

## Defining a Signature
In first-order logic, a signature consists of function and predicate symbols with their arities.
In our implementation, we use type-level strings to represent symbols, but the actual arity is handled in the term and formula structure.

We'll define a simple signature for arithmetic with one constant (`0`), one unary function (`s` for successor), and one binary predicate (`<` for less-than).

Note: The `FirstOrder` module does not require you to list the signature in the type; instead, we use `KnownSymbol` to work with individual symbols.

## Building Terms
Terms are built using the smart constructors `varTerm`, `constTerm`, and `funAppTerm`.

Example: The term `s(s(0))` (i.e., the number 2) can be built as follows:

```haskell
import FirstOrder
import Data.Proxy
import GHC.TypeLits (KnownSymbol)

-- Assume we have KnownSymbol instances for "s" and "0"
-- In practice, you would need to define these or use existing ones.
-- For simplicity, we'll use string literals with KnownSymbol via the `DataKinds` extension.

zeroTerm :: Term '[]
zeroTerm = constTerm (Proxy :: Proxy "0")

succTerm :: Term '[] -> Term '[]
succTerm t = funAppTerm (Proxy :: Proxy "s") [t]

twoTerm :: Term '[]
twoTerm = succTerm (succTerm zeroTerm)
```

## Building Formulas
Formulas are built using the smart constructors for the `Formula` GADT.

Example: The formula `∀x. s(x) > x` (using `>` as a predicate, but we have `<` so we'll adjust) can be expressed as:
`∀x. ¬(s(x) < x)` (i.e., it is not the case that the successor of x is less than x).

We'll define the less-than predicate and then the formula.

```haskell
import FirstOrder
import Data.Proxy

-- Less-than predicate applied to two terms
lt :: Term syms -> Term syms -> Formula syms
lt t1 t2 = predTerm (Proxy :: Proxy "<") [t1, t2]

-- Negation
notF :: Formula syms -> Formula syms
notF = neg

-- Universal quantification
forallTerm :: KnownSymbol sym => Proxy sym -> Formula syms -> Formula syms
forallTerm = forall

-- Example formula: ∀x. ¬(s(x) < x)
exampleFormula :: Formula '[]
exampleFormula =
  forallTerm (Proxy :: Proxy "x") $
    notF $
      lt (funAppTerm (Proxy :: Proxy "s") [varTerm (Proxy :: Proxy "x")])
         (varTerm (Proxy :: Proxy "x"))
```

## Defining a Model
To evaluate formulas, we need a model that interprets the function and predicate symbols.

We'll define a model over the natural numbers (as strings) where:
- The constant "0" is interpreted as the string "0".
- The function "s" is interpreted as `\\ [n] -> show (read n + 1)`.
- The predicate "<" is interpreted as the set of pairs (as strings) where the first number is less than the second.

```haskell
import FirstOrder
import qualified Data.Map as Map
import qualified Data.Set as Set

-- Herbrand universe: we'll use a finite set for example: {"0","1","2"}
universe :: Set.Set String
universe = Set.fromList ["0","1","2"]

-- Interpretation of functions
funcInterp :: Map.Map String ([String] -> String)
funcInterp = Map.fromList
  [ ("0", \\[] -> "0") -- constant
  , ("s", \\[n] -> show (read n + 1))
  ]

-- Interpretation of predicates
predInterp :: Map.Map String (Set.Set [String])
predInterp = Map.fromList
  [ ("<", Set.fromList [ [x,y] | x <- ["0","1","2"], y <- ["0","1","2"], read x < read y ])
  ]

-- The model
exampleModel :: FOLModel '[]  -- Note: the signature is empty because we are not using it in the model (phantom)
exampleModel = FOLModel
  { predicateInterpretation = predInterp
  , functionInterpretation  = funcInterp
  , constants               = universe
  }
```

## Evaluating a Formula
Now we can evaluate the formula in the model.

```haskell
import FirstOrder

-- Evaluate the closed formula (no free variables) in the model.
-- The `satisfies` method of the Institution class expects a proxy for the signature.
-- Since our signature is empty, we use `Proxy :: Proxy (FOLSig '[])`.

result :: Bool
result = satisfies (Proxy :: Proxy (FOLSig '[])) exampleModel exampleFormula
-- This should return True because for every n in {0,1,2}, s(n) is not less than n.
```

## Running a Test
You can also write a test in the test suite. The existing test suite (`test/Main.hs`) already tests propositional logic.
You can add a test for first-order logic by importing the `FirstOrder` module and checking a few formulas.

## Conclusion
This tutorial showed how to:
1. Build terms and formulas using smart constructors.
2. Define a model with interpretations for functions and predicates.
3. Evaluate a closed formula in the model using the `satisfies` method.

You can extend this approach to more complex theories by adding more symbols and defining appropriate interpretations.

## Next Steps
- Try defining a model for arithmetic with addition and multiplication.
- Experiment with quantifiers over different domains.
- Consider how to integrate with automated theorem provers (e.g., using the Jukebox library for resolution).