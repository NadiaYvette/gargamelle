# Chapter 3: Formally Verified Mealy Automata

**Volume V:** Grounded Verification & Autonomous CEGIS  
**GHC Note Invariant:** Note [Formally Verified Mealy Automata State Topology] [ref:note-crem-mealy-topology]  
**Production Package:** [`packages/gargamelle-workflow`](../../../../packages/gargamelle-workflow/README.md) ([Hackage](https://hackage.haskell.org/package/gargamelle-workflow))

---

## 1. Type-Level Topology Enforcement

In ad-hoc synthesis scripts, state loops are managed via mutable booleans or unindexed state monads. It is trivially easy to introduce bugs where an unverified candidate bypasses testing and marks itself complete, or an error state transitions directly to production deployment.

Gargamelle models the CEGIS loop as a formally verified **Mealy State Machine** using `crem` and `singletons-base`:

```haskell:ignore
data SynthesisState
  = StatePropose
  | StateSandboxRun
  | StateCollectEvidence
  | StateSimilarityCheck
  | StateSheafCheck
  | StateComplete
  | StateRetry
```

---

## 2. Compile-Time Transition Guarantees

As detailed in Note [Formally Verified Mealy Automata State Topology] [ref:note-crem-mealy-topology], valid transitions are restricted at the type level:
- `StatePropose` can only transition to `StateSandboxRun` via `CmdRunCandidate`.
- `StateSandboxRun` transitions to `StateCollectEvidence` upon success, or `StateRetry` upon timeout/crash.
- `StateSimilarityCheck` must transition through `StateSheafCheck` via `CmdTransitionToSheafCheck` before reaching `StateComplete`.

Any code path attempting to jump directly from `StatePropose` to `StateComplete` is rejected by GHC at compile time, guaranteeing that no unverified patch can ever escape the CEGIS harness.
