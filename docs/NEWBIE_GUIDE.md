# Gargamelle Newbie Quickstart & Token-Conservation Guide

**Audience:** New human contributors and AI coding assistant drivers (Antigravity, Claude Code, Cursor, Aider).  
**Parent Strategy:** [`docs/notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md)  
**Corpus Inventory:** [`docs/INDEX.md`](INDEX.md) · **Roll-Out Plan:** [`docs/DOCUMENTATION_ROLLOUT_PLAN.md`](DOCUMENTATION_ROLLOUT_PLAN.md)  
**Interactive Tutorial:** [`docs/TUTORIAL.md`](TUTORIAL.md) · **Framework Spec:** [`docs/FRAMEWORK_RECOMMENDATIONS.md`](FRAMEWORK_RECOMMENDATIONS.md)  
**Maintainer Guide:** [`docs/MAINTAINER_GUIDE.md`](MAINTAINER_GUIDE.md)  

---

## 0. Learning the Concepts First: Start with `TUTORIAL.md`

If you are new to `gargamelle` and want to understand how categorical institutions, cellular sheaves, and sheaf-gated CEGIS work, read the **5-Lesson Interactive Tutorial** in [`docs/TUTORIAL.md`](TUTORIAL.md):

- **Lesson 1:** Observable Morphisms & Free Verifier ASTs (`ObsMor`, `VerifierAST`, `Divisible`, `Decidable`)
- **Lesson 2:** Categorical Institutions & Pushout Feature Weaving (`Institution`, `weaveAspect`, `reductMod`)
- **Lesson 3:** Streaming SMT Pipes & First-Order Verification (`verifyZ3Formula`, Herbrand structures)
- **Lesson 4:** Cellular Sheaves & Homological Fault Localization (`CellComplex`, `CellularSheaf`, `coboundary`, `locateObstructions`)
- **Lesson 5:** Store Comonad Diffusion & Sheaf-Gated CEGIS (`diffuseUntilHarmonic`, `runSheafGatedCEGIS`)

Once you are comfortable with the concepts, use this guide for repository navigation, test execution, and token conservation.

---

## 1. The Core Invariant: Never Dump Whole Modules

In a multi-package Haskell codebase with category-theoretic equipment, type-level singletons, and large ASTs, dumping full source modules into the conversation context wastes 2,500–4,000 tokens per turn and causes attention degradation.

Always follow the **Progressive Disclosure Funnel**:

```
Level 0: Global Navigation  (docs/INDEX.md, packages/ overview)   →   ~10–50 tokens
Level 1: Structural Outline (module export lists, type headers)   →   ~100–250 tokens
Level 2: Targeted Slice     (view_file StartLine / EndLine)       →   ~200–500 tokens
```

---

## 2. Fast Package & Symbol Navigation (Level 0 — <20 tokens)

Before opening any file, identify which package owns the concept across the 11 packages:

| If you are looking for... | Look in package | Main Source Files |
| :--- | :--- | :--- |
| `ObsMor`, `VerifierAST`, `Evidence` | `packages/gargamelle-model` | `src/Gargamelle/Model/Observable.hs`, `Verifier.hs` |
| `AGContract`, `LogicAST`, Galois | `packages/gargamelle-logic` | `src/Gargamelle/Logic/Contract.hs`, `AST.hs` |
| TreeDiff, AST similarity, Evidence | `packages/gargamelle-evidence` | `src/Evidence.hs` |
| `Institution`, `PushoutWeaving` | `packages/gargamelle-core` | `src/Gargamelle/Core/Institution.hs`, `Weaving.hs` |
| First-Order logic, Z3 SMT pipe | `packages/gargamelle-fol` | `src/Gargamelle/FOL/Z3.hs`, `FirstOrder.hs` |
| Equational logic, DPO rewriting | `packages/gargamelle-equational` | `src/Gargamelle/Equational/DPO.hs` |
| Rope arrows, $O(1)$ router, optics | `packages/gargamelle-effect` | `src/Gargamelle/Effect/Router.hs`, `Optics.hs` |
| Bubblewrap sandboxing | `packages/gargamelle-sandbox` | `src/Sandbox/Handler.hs`, `Effect.hs` |
| Beam SQLite persistence | `packages/gargamelle-persistence` | `src/Persistence/Beam.hs`, `Schema.hs` |
| Cell complexes, sheaves, $H^1$ obs | `packages/gargamelle-sheaf` | `src/Gargamelle/Sheaf/Diffusion.hs`, `Cohomology.hs` |
| Crem Mealy machine, CEGIS pipeline | `packages/gargamelle-workflow` | `src/Workflow/Synthesis.hs` |

Next, view **only** the relevant lines using `view_file` (e.g. 50–100 lines around the function or type definition).

---

## 3. Fast Build & Verification Commands

All packages are configured under `cabal.project`.

```bash
# 1. Quick compile check of a single package
cabal build gargamelle-workflow

# 2. Run the deterministic physical verification gate (6 gates: Sandbox, Beam, HLint, Tests, Tagref, CLOC density)
./bin/gargamelle-verify

# 3. Run all test suites across all 8 active packages
cabal test gargamelle-logic gargamelle-model gargamelle-core gargamelle-fol \
           gargamelle-equational gargamelle-sheaf gargamelle-effect gargamelle-workflow

# 4. Check HLint static analysis (0 hints enforced)
hlint packages/gargamelle-*/src
```

---

## 4. Commit Attribution Guidelines

Commits must follow the Linux kernel RFC 2822 trailer format:
- Descriptive-imperative subject line (e.g., `feat(sheaf): add comonadic diffusion runner`).
- Explanatory body explaining *why* the change was made.
- AI attribution trailer:
  ```
  Assisted-by: Antigravity (Google / gemini-3.8-pro)
  ```
- **Never** use `Co-authored-by:` or `Signed-off-by:` for AI assistants (reserved for human DCO certifiers).
