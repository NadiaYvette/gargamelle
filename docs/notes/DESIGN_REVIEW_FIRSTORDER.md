# Design Review: FirstOrder Module

## Overview
The FirstOrder module provides an Institution instance for first-order logic using the Folly library for term and formula representation. It integrates with the existing Institution framework to enable reasoning about first-order theories within the programming-in-the-large project.

## Key Components

### Signature
- `FOLSig syms`: A phantom type wrapping a type-level list of symbols (of kind `Symbol`). The signature is not directly used in the current implementation but serves as a placeholder for future extensions.

### Terms
- `Term`: Alias for `Folly.Formula.Term`, representing first-order terms (variables, constants, and function applications).

### Formulas (Sentences)
- `Formula syms`: A GADT representing first-order formulas constructed from Folly's terms:
  - `TrueF`, `FalseF`: Boolean constants.
  - `Pred sym [Term]`: Predicate application.
  - `Not`, `And`, `Or`, `Impl`: Propositional connectives.
  - `Forall sym`, `Exists sym`: Quantifiers (note: `forall` identifier warning due to future GHC keyword).

### Models
- `FOLModel syms`: A simple model consisting of:
  - `predicateInterpretation :: Map.Map String Bool`: Interpretation of predicate symbols as Boolean values (nullary predicates only).
  - `functionInterpretation :: Map.Map String String`: Interpretation of function symbols as constant strings (zero-arity functions only).

### Institution Instance
- The `satisfies` method delegates to `evalFormula`, which evaluates a closed formula in a given model:
  - Boolean constants are evaluated directly.
  - Predicates are looked up in the model (ignoring arguments for now).
  - Propositional connectives are evaluated recursively.
  - Quantifiers are currently undefined (would require domain enumeration).

### Smart Constructors
- Term constructors: `varTerm`, `constTerm`, `funAppTerm` (using Folly's `var`, `constant`, `func`).
- Formula constructors: `prop`, `neg`, `conj`, `disj`, `impl`, `bicond`, `forall`, `exists`.

## Dependencies
- **Folly**: Vendored as `external/Folly/` for first-order term and formula operations.
- **Institution**: The core typeclass from `Institution.hs`.

## Limitations and Future Work
1. **Model Simplification**: The current model only handles nullary predicates and zero-arity functions. A proper term algebra should account for arity and recursive evaluation.
2. **Quantifiers**: `Forall` and `Exists` are undefined; they require a domain of discourse and variable binding.
3. **Equality**: Equality is not treated specially; it is modeled as a regular predicate. In first-order logic, equality has specific axioms (reflexivity, substitution) that should be considered.
4. **Integration with Jukebox**: The Jukebox library (now vendored as `external/Jukebox/`) provides advanced first-order tools (clausification, unification, etc.). Future versions should leverage these for automated reasoning.
5. **Test Coverage**: Add test cases for FirstOrder logic (e.g., using the Folly test suite or custom properties).

## References
- Folly library: https://hackage.haskell.org/package/Folly
- Institution framework: See `Institution.hs` in this project.
- Jukebox logic toolbox: https://hackage.haskell.org/package/jukebox

## Decisions
- **Language Extensions**: Used `DataKinds`, `TypeFamilies`, `GADTs`, `KindSignatures`, `PolyKinds`, `TypeOperators`, `FlexibleInstances`, `MultiParamTypeClasses` to support phantom signatures and GADTs for formulas.
- **Model Representation**: Chose a simple map-based model for ease of interpretation and debugging; future work may replace this with a more algebraic or categorical model.
- **Formula Structure**: Built formulas on top of Folly's terms to reuse its parsing and pretty-printing capabilities (though not currently used).

## Open Questions
- How should variable binding and substitution be handled in the presence of quantifiers?
- Should we adopt a more categorical model of first-order logic (e.g., using hyperdoctrines) to align with the Institution framework's origins?
- How can we integrate Jukebox's automated reasoning tools (e.g., resolution, unify) into the satisfies method or as derived operations?
