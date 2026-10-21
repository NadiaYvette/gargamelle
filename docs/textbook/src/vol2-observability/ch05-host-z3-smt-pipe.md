# Chapter 5: The Host SMT Pipe

**Volume II:** Reified Observability & Proof Synthesis  
**GHC Note Invariant:** Note [Streaming Z3 SMT-LIB2 Piping and Model Extraction] [ref:note-z3-smt-pipe-extraction]  
**Production Module:** [`Gargamelle.FOL.Z3`](../../../../packages/gargamelle-fol/src/Gargamelle/FOL/Z3.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-fol/docs/Gargamelle-FOL-Z3.html))

---

## 1. Zero-Dependency SMT-LIB2 Streaming

Rather than linking fragile C++ FFI bindings that destabilize GHC runtimes, [`Gargamelle.FOL.Z3`](../../../../packages/gargamelle-fol/src/Gargamelle/FOL/Z3.hs) generates strongly-typed SMT-LIB2 scripts and streams them over standard POSIX process pipes directly to host Z3 4.16:

```haskell:ignore
solveZ3WithModel :: String -> IO (Z3Result, Map String String)
```

The streaming process executes:
1. `(set-logic ALL)`
2. Declare uninterpreted functions and variables
3. `(assert (not <formula>))` (querying for refutation)
4. `(check-sat)`
5. `(get-model)` (when `sat`, extracting counterexamples)

---

## 2. From Solver Status to Verifier Evidence

When Z3 returns `unsat`, the negation is unsatisfiable, mathematically proving that the original formula is a valid tautology. This directly constructs a `VerifiedSection`.

When Z3 returns `sat`, the solver has discovered a concrete countermodel. Gargamelle parses the SMT-LIB2 S-expressions into a structured `Map String String` counterexample, feeding it into the CEGIS loop to guide patch refinement.
