# Chapter 1: The Problem of Heterogeneous Logics

**Volume I:** Abstract Model Theory & Categorical Institutions  
**Consumer Perspective:** How `sarutahiko` manages polyglot microservice contracts.

---

## 1. The Monolithic Trap

In conventional automated verification, tools tightly couple their internal intermediate representation to a single syntax (e.g. SMT-LIB2, Dafny, Boogie, or LLVM bitcode). While this simplifies monomorphic solvers, it catastrophically fractures when verifying real-world distributed architectures:
- Module $A$ is written in Rust, requiring memory safety and linear type tracking.
- Module $B$ is written in Haskell, specifying purely algebraic business contracts over monads.
- Module $C$ is an SMT constraint set solved via host Z3.

When an autonomous agent like `sarutahiko` attempts to synthesize an end-to-end patch across these boundaries, translating every constraint into a monolithic global AST results in semantic dilution, exponential formula explosion, and loss of domain invariants.

---

## 2. The Abstract Model-Theoretic Remedy

Rather than forcing all languages into a universal grammar, Joseph Goguen and Rod Burstall (1992) pioneered the thesis that **a logic is not defined by its grammar, but by how truth behaves under translation**. 

By treating signatures, sentences, and models as categories and functors, we can reason about system invariants, prove pushout feature weaving, and discover shared interfaces without ever inspecting the internal syntax of individual components.

This foundation is implemented in [`gargamelle-core`](../../../../packages/gargamelle-core/README.md) ([Hackage](https://hackage.haskell.org/package/gargamelle-core)) and formalizes the [`Institution`](../../../../packages/gargamelle-core/src/Gargamelle/Core/Institution.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-core/docs/Gargamelle-Core-Institution.html#t:Institution)) typeclass developed in Chapter 2.
