# Design Review: Workflow Orchestration, Effects, and Persistence

**Date:** October 12, 2026  
**Author:** Hermes Agent & Nadia  
**Target Project:** `programming-in-the-large` / `polytropos`  

---

## 1. Executive Summary
This design review captures our updated architectural decisions regarding workflow orchestration, effect systems, persistence, and sandbox automation, evaluated in light of Parès, Bernardy, and Eisenberg (*Composing Effects into Tasks and Workflows*, Haskell '20) and our existing infrastructure (`polytropos`, `crem`, `beam`, `hs-tree-sitter`, and `tree-diff`).

---

## 2. Architectural Components

### A. Effect Orchestration: Kernmantle
- **Motivation:** Traditional monadic effect systems (`effectful`, `polysemy`) intertwine configuration and process-time, preventing static/config-time analysis and early-failure detection.
- **Approach:** Adopt **Kernmantle** (Arrow-based core with heterogeneous effect mantle/handlers) to structure our workflow tasks.
- **Benefits:**
  - **Config-Time Analysis:** Inspect workflow structure and verify resource availability/types *before* running data processing.
  - **Interpreter Swapping:** Run the exact same workflow graph in a production environment (`Kleisli IO`) or a pure test/dry-run mock interpreter with zero code changes.
  - **Static Optimizations & Safety:** Catch missing files, misconfigured databases, or invalid sandbox limits upfront.

### B. Persistence Layer: Beam (`beam` + `polytropos-beam`)
- **Motivation:** Need type-safe, backend-agnostic database interaction for storing evidence, counterexamples, and execution history.
- **Approach:** Use `beam-core` along with `beam-sqlite` (for testing/local) and `beam-postgres` (for production), integrated via `polytropos-beam`.
- **Benefits:** Queries and table definitions remain pure values that can be lifted as Kernmantle strands, preserving static workflow analyzability.

### C. Sandbox Automation & State Machines (`crem`)
- **Motivation:** Safe execution of untrusted candidate code edits and orchestration of multi-step synthesis loops.
- **Approach:**
  - Model sandbox operations (`RunSandbox`, `WithTempDir`) as first-class Kernmantle strands with rigorous resource bracketing.
  - Use Tweag's `crem` state machine library to drive the top-level synthesis loop:
    $$\text{Propose Change} \longrightarrow \text{Sandbox Run} \longrightarrow \text{Collect Evidence} \longrightarrow \text{Tree-Diff Check} \longrightarrow \text{State Transition}$$

---

## 3. Implementation Roadmap
1. **Kernmantle Integration:** Define core arrow types, strand definitions, and handlers for logging, persistence, and sandbox execution.
2. **Beam Persistence:** Set up schema definitions for EvidenceStore and hook them into `polytropos-beam`.
3. **Sandbox & Crem Integration:** Wire the sandbox effect interpreter and compose the synthesis state machine using `crem`.
4. **Validation:** Implement end-to-end integration tests using `tasty` and `hedgehog`.
