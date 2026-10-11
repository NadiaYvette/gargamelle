# Design Review: Hyperdoctrine Module

## Overview
This document reviews the Hyperdoctrine module implementation in the programming-in-the-large project. The module provides a basic placeholder for hyperdoctrine logic, which is a categorical formulation of first-order logic where the fiber over each context is a poset of propositions.

## Key Components

### Signature
- `HDCSig syms`: A phantom type wrapping a type-level list of symbols (of kind `Symbol`). Currently unused but reserved for future extensions.

### Context
- We introduced a `Context` GADT to represent lists of symbols (variables) as a type-level list.
  - `Nil` for the empty context.
  - `Cons` to add a symbol to the context.

### Fiber
- In a hyperdoctrine, the fiber over a context is a poset of propositions.
- We reused the `Formula` GADT from FirstOrder as the fiber, but we need to account for the variables in context.
- We attempted to use a type family `ContextToList` to convert a context to a type-level list of symbols, and then use that as the signature for the fiber formulas.
- However, due to time constraints, the institution instance currently ignores the context and uses the phantom signature directly.

### Model
- `HDModel ctx`: A model for a context, containing a FirstOrder model for the variables in that context.
  - `foModel :: FOLModel (ContextToList ctx)`

### Institution Instance
- The instance is currently a simplified version that uses the FirstOrder institution directly on the phantom signature.
- This is not a proper hyperdoctrine instance but a starting point.

### Smart Constructors
- `nil`: empty context.
- `cons`: add a symbol to a context.

## Dependencies
- FirstOrder module (for terms, formulas, and models)
- Institution framework (`Institution.hs`)
- GHC extensions: DataKinds, TypeFamilies, GADTs, KindSignatures, PolyKinds, TypeOperators, FlexibleInstances, MultiParamTypeClasses

## Strengths
- Introduces the notion of context as a type-level list.
- Separates the model per context.
- Reuses the existing FirstOrder infrastructure for propositions.

## Limitations
- The institution instance does not properly vary with the context; it uses a fixed phantom signature.
- The fiber is not actually a poset; we reuse FirstOrder's Formula which has logical structure but not necessarily the hyperdoctrine structure (like substitution, weakening, etc.).
- No actual hyperdoctrine axioms (like Beck-Chevalley) are implemented.
- The context is not used in the satisfaction relation.

## Future Work
1. **Proper Institution Instance**:
   - Make the institution instance depend on the context (perhaps by using the Context type as the signature).
   - Define satisfaction relative to a context model.

2. **Enrich the Fiber**:
   - Instead of reusing FirstOrder's Formula directly, consider what propositions are allowed in the fiber (maybe a subset).
   - Implement the fiber as a Heyting algebra (if we want intuitionistic logic) or a Boolean algebra (for classical).

3. **Implement Substitution and Weakening**:
   - Provide functoriality: for a context morphism (substitution), we should have a map between fibers.
   - This is the essence of a hyperdoctrine: a functor from the category of contexts to the category of posets.

4. **Add Quantifiers as Adjoints**:
   - In a hyperdoctrine, quantifiers are adjoints to the weakening map.
   - Implement existential and universal quantifiers as left and right adjoints.

5. **Connection to Existing Work**:
   - Relate hyperdoctrines to the sheaf-theoretic framework (sheaves over a site of contexts).
   - Connect to session types (contexts as communication histories).
   - Relate to refinement calculus (specifications as fibers over program variables).

6. **Automated Reasoning**:
   - Use the hyperdoctrine structure to guide proof search (e.g., using the adjoint properties).

## Conclusion
The Hyperdoctrine module is a preliminary sketch that introduces the basic notions of contexts and fibers. While it does not yet implement a proper hyperdoctrine institution, it sets the stage for further development. The design can be extended to a full hyperdoctrine interpretation of first-order logic, which would provide a rich categorical foundation for connecting to the other frameworks mentioned in the transcript.
