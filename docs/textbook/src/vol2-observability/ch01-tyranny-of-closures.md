# Chapter 1: The Tyranny of the Black Box

**Volume II:** Reified Observability & Proof Synthesis  
**GHC Note Invariant:** Note [Defunctionalized Observable Morphisms] [ref:note-defunctionalized-obsmor]

---

## 1. Why Closures Defeat AI Synthesis

A standard Haskell function `f :: a -> b` is an opaque heap closure. To an autonomous coding agent or theorem prover, `f` is an inscrutable black box:
- It cannot be serialized to disk or written to a database table.
- It cannot be inspected without executing its instructions (which may trigger side-effects or loop indefinitely).
- It cannot be converted into an SMT formula for automated solver verification.
- Two functions `f, g :: a -> b` cannot be checked for structural or semantic equality.

When automated synthesis tools rely on higher-order function closures, they cannot explain *why* a synthesized candidate failed, nor can they store failure models in persistence databases to prevent future synthesis regressions.

---

## 2. The 100% Observability Doctrine

Gargamelle enforces the **100% Observability Doctrine**:
> *Within `gargamelle-logic`, `gargamelle-model`, `gargamelle-core`, and `gargamelle-sheaf`, no semantic morphism or verification condition may be represented as an opaque Haskell `(->)` closure.*

Every morphism must be reified into an introspectable AST ([`ObsMor`](../../../../packages/gargamelle-logic/src/Gargamelle/Logic/Defunctionalize.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-logic/docs/Gargamelle-Logic-Defunctionalize.html#t:ObsMor))) that can be serialized, inspected via [`inspectObsMor`](../../../../packages/gargamelle-logic/src/Gargamelle/Logic/Defunctionalize.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-logic/docs/Gargamelle-Logic-Defunctionalize.html#v:inspectObsMor)), translated to Z3 SMT-LIB2, and stored in Beam SQLite tables.
