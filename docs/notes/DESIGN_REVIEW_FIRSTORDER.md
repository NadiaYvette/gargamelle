# Design Review: FirstOrder Model

## Overview
This document reviews the FirstOrder module implementation in the programming-in-the-large project. The module provides an Institution instance for first-order logic with equality, using the Folly library for term representation and a custom GADT for formulas to ensure proper handling of variables, arity, and quantifiers.

## Key Components

### Term Representation
- Terms are represented using Folly's `Term` type, which includes variables, constants, and function applications.
- Smart constructors (`varTerm`, `constTerm`, `funAppTerm`) are provided for building terms from `KnownSymbol` proxies.
- Terms are evaluated to constants (Strings) given a model and variable environment.

### Formula Representation
- Formulas are represented by a custom GADT `Formula` with constructors for:
  - Truth values (`TrueF`, `FalseF`)
  - Predicate application (`Pred`)
  - Negation (`Not`)
  - Conjunction (`And`)
  - Disjunction (`Or`)
  - Implication (`Impl`)
  - Universal quantification (`Forall`)
  - Existential quantification (`Exists`)
- This GADT ensures that formulas are well-typed and avoids the pitfalls of using Folly's formula type directly (which lacks proper variable binding).

### Model Structure
- Models (`FOLModel`) consist of:
  - `predicateInterpretation`: Mapping from predicate names (String) to relations (sets of tuples of constants)
  - `functionInterpretation`: Mapping from function names (String) to functions on constants ([String] -> String)
  - `constants`: Herbrand universe of constants (as strings) - the set of all constants in the signature
- The model uses String keys for simplicity, assuming predicate and function symbols are represented as Strings.

### Satisfaction Relation
- The `satisfies` method evaluates a closed formula in a model by:
  - Evaluating terms to constants (with variable lookup from an environment)
  - Evaluating formulas to Booleans, with quantifiers interpreted over the Herbrand universe
  - Returns `Left error` for undefined symbols or free variables, `Right Bool` for closed formulas
- The environment maps variable names (Strings) to constant values (Strings) during evaluation.

### Smart Constructors for Formulas
- Propositional connectives and quantifiers are provided as smart constructors that build the GADT formulas.
- Quantifier constructors (`forall`, `exists`) take a `KnownSymbol` proxy for the variable and a formula body.
- Note: The identifier `forall` produces a GHC warning about future keyword usage; consider renaming to `forAll` in future versions.

## Dependencies
- Folly library for term representation (`Folly.Formula`)
- Standard library containers (`Data.Map`, `Data.Set`)
- GHC extensions: DataKinds, TypeFamilies, GADTs, KindSignatures, PolyKinds, TypeOperators, FlexibleInstances, MultiParamTypeClasses

## Strengths
- Clear separation of terms and formulas
- Proper handling of variable binding and quantification via environments
- Use of GADTs ensures that only well-formed formulas can be constructed
- Correct handling of arity for predicates and functions
- Modular design that isolates first-order logic specifics
- Integration with existing Folly library for term operations

## Limitations
- The Herbrand universe approach may be inefficient for large domains
- No built-in support for equality as a special predicate with axioms (could be added as a distinguished predicate)
- The model is simple and not optimized for performance
- Quantifier evaluation may be slow for large Herbrand universes

## Future Work
- Incorporate equality as a special predicate with reflexivity and substitution axioms
- Optimize model representation for finite domains (e.g., using arrays or finite maps)
- Add more comprehensive test cases covering quantifiers, equality, and complex terms
- Consider integrating with Jukebox for automated reasoning tools (unification, resolution)
- Explore categorical models of first-order logic (hyperdoctrines) to align with Institution origins

## Conclusion
The FirstOrder module provides a solid foundation for first-order logic reasoning within the Institution framework. It correctly handles arity, variables, and quantification, and integrates with the Folly library for term representation. The design is extensible and can serve as a basis for further logical frameworks, including the implementation of equational logic (already done in Equational.hs) and potential extension to other frameworks mentioned in the transcript (sheaf-theoretic, session types, refinement calculus, hyperdoctrines).
