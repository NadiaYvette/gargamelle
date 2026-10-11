# Design Review: Equational Module

## Overview
The Equational module provides an Institution instance for equational logic (first-order logic with equality) using a simple term model. It builds upon the Jukebox library (for a utility function) and the Institution framework to enable reasoning about equational theories within the programming-in-the-large project.

## Key Components

### Signature
- `EGSym syms`: A phantom type wrapping a type-level list of symbols (of kind `Symbol`). The signature is not directly used in the current implementation but serves as a placeholder for future extensions.

### Terms
- `Term syms`: A GADT representing first-order terms:
  - `Var sym`: A variable.
  - `Const sym`: A constant (nullary function).
  - `FunApp sym [Term]`: Function application.

### Equations (Sentences)
- `Equation syms`: A pair of terms (lhs = rhs).

### Models
- `EqModel syms`: A simple model consisting of:
  - `carrier :: [String]`: List of constants in the signature (as strings). (Currently unused in evaluation but present for completeness.)
  - `interp :: Map.Map String ([String] -> String)`: Interpretation of function symbols as functions from a list of interpreted arguments (each a String) to an interpreted result (a String). Constants are nullary functions, so they take an empty list and return a String.

### Institution Instance
- The `satisfies` method evaluates both sides of the equation using `evalTerm` and checks for string equality.
- `evalTerm` recursively evaluates a term:
  - Variables and constants evaluate to their symbol names (via `symbolVal`).
  - Function applications look up the function in the model and apply it to the evaluated arguments.
  - If a symbol is not found in the model, an error is thrown.

### Dependencies
- **Jukebox**: Used for the `usort` function (from `Jukebox.Utils`) to depend on the library; currently not used in the logic but ensures the package is pulled in.
- **Institution**: The core typeclass from `Institution.hs`.

## Limitations and Future Work
1. **Model Simplification**: The current model treats function symbols as arbitrary functions on strings, which is not a true term algebra. A proper initial algebra or Herbrand universe should be used for sound equational reasoning.
2. **No Equation-Specific Logic**: The instance does not treat equality specially (e.g., congruence, substitution, reflexivity). It reduces equality to syntactic equality after interpretation.
3. **Error on Undefined Symbols**: The `evalTerm` function throws an error on undefined symbols; a more robust approach might return a default value or use a `Maybe` or `Either` type.
4. **Integration with Jukebox**: The Jukebox library provides tools for unification, congruence closure, and equational reasoning (e.g., in `Jukebox.Sat.Equality`). Future versions should leverage these for automated equational reasoning.
5. **Test Coverage**: Add test cases for equational logic (e.g., using the Jukebox test suite or custom properties).

## Smart Constructors
- Term constructors: `varTerm`, `constTerm`, `funAppTerm`.
- Equation constructor: `eq`.

## Decisions
- **Language Extensions**: Used `DataKinds`, `TypeFamilies`, `GADTs`, `KindSignatures`, `PolyKinds`, `TypeOperators`, `FlexibleInstances`, `MultiParamTypeClasses` to support phantom signatures and GADTs for terms and equations.
- **Model Representation**: Chose a simple map-based model for ease of interpretation and debugging; future work may replace this with a more algebraic or categorical model (e.g., using monads or adjunctions).
- **Equation Evaluation**: Reduced to string equality after interpretation; this is decidable but not logically complete for equational theories.
- **Dependency on Jukebox**: Imported `usort` from `Jukebox.Utils` to ensure the Jukebox package is a dependency, even if the function is not currently used. This facilitates future integration.

## Open Questions
- How should we extend the model to support a genuine term algebra (e.g., using the initial algebra construction)?
- Can we integrate Jukebox's equality solver (`Jukebox.Sat.Equality`) to provide a decision procedure for ground equational theories?
- Should we consider a parametric model over a carrier set (e.g., using `Type` families) to allow different interpretations (e.g., Booleans, integers)?
- How does this equational instance relate to the FirstOrder instance? Should equality be a distinguished predicate in FirstOrder rather than a separate module?
