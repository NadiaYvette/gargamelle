<!--
SPDX-License-Identifier: EUPL-1.2
-->
# Recommendations for the Expository & Tutorial Framework & Programmatic Tooling

**Status:** REFERENCE SPECIFICATION · v1.0 · 2026-10-20  
**Authors:** Nadia Yvette Chambers & Antigravity (Google / gemini-3.8-pro)  
**Parent Strategy:** [`notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md)  
**Detailed Proposal:** [`notes/EXPOSITORY_AND_TUTORIAL_FRAMEWORK.md`](notes/EXPOSITORY_AND_TUTORIAL_FRAMEWORK.md)  
**Corpus Inventory:** [`INDEX.md`](INDEX.md)  

---

## 1. Executive Summary & Purpose

This document preserves the concrete recommendations established for the **Gargamelle Expository & Tutorial Framework** and its accompanying **Programmatic Tooling**. It serves as the authoritative reference for upcoming work authoring textbook-level pedagogical materials, per-package monographs, and literate test harnesses with human feedback.

Whereas `polytropos` addresses a focused compiler-performance problem within familiar type-level Haskell idioms, `gargamelle` operates at the confluence of five demanding disciplines:
1. **Abstract Model Theory & Higher Categories:** Goguen-Burstall Institutions, Comorphisms, Pushouts, Colimits, Proarrow equipments, and Defunctionalized 2-categories.
2. **Applied Algebraic Topology & Cellular Sheaves:** 1-dimensional Cell Complexes, Star co-faces, Cellular Sheaves, Coboundary operators $\delta^0$, and $H^1$ Cohomological Obstructions.
3. **Order Theory & Comonadic Dynamics:** Store Comonads, Monotonic contract meet semi-lattices (`Algebra.Lattice.Op`), and Knaster-Tarski fixed-point consensus diffusion.
4. **Epistemic Observability & Automated Theorem Proving:** Reified observable morphisms (`ObsMor`), Free verifier ASTs (`VerifierAST`, `Divisible`, `Decidable`), and streaming SMT-LIB2 pipes to Z3.
5. **Grounded Systems Sandboxing & Verified Automata:** Linux container namespace isolation via Bubblewrap (`/usr/bin/bwrap`), Beam SQLite ORM schemas, and Crem Mealy state machines.

Standard API documentation and brief Haddocks cannot bridge this conceptual threshold. The recommendations below specify where to place documentation across the suite, what documents to write, the curriculum for a 5-volume foundational textbook, the structure for per-package monographs, and the programmatic automation required to prevent documentation drift.

---

## 2. Directory Structure & Document Hierarchy

Documentation is partitioned into a **3-tier hierarchy** that separates suite-wide conceptual theory, package-level reference specifications, and day-to-day API docstrings:

```
docs/
├── FRAMEWORK_RECOMMENDATIONS.md          <-- This reference document
├── INDEX.md                              <-- Corpus inventory & reading paths
├── NEWBIE_GUIDE.md                       <-- Orientation & token conservation funnel
├── TUTORIAL.md                           <-- 5-lesson interactive tutorial
├── MAINTAINER_GUIDE.md                   <-- Governance, quality gates & commit conventions
├── developer/
│   └── BUILD_SYSTEMS_MATRIX.md           <-- Multi-compiler matrix (GHC 9.6–9.14; Cabal, Stack, Nix)
├── notes/
│   ├── EXPOSITORY_AND_TUTORIAL_FRAMEWORK.md <-- Detailed framework specification & rationale
│   ├── GARGAMELLE_ARCHITECTURAL_REDESIGN.md <-- Canonical v2.0 architectural blueprint
│   ├── CATEGORICAL_FOUNDATIONS_SURVEY.md    <-- Higher category theory & proarrow survey
│   ├── HASK2_UNSATURATED_TYPE_FAMILIES.md   <-- Proarrow equipment resolution of Hask2
│   └── DOC_STRATEGY.md                   <-- Documentation lifecycle & precedence rule (§4)
├── registers/
│   ├── PACKAGES.md                       <-- Exhaustive register of all 11 packages & exports
│   └── THIRD_PARTY.md                    <-- Upstream licenses & attributions
└── textbook/                             <-- TIER A: The Gargamelle Treatise (Textbook)
    ├── book.toml                         (mdBook configuration)
    ├── vol1-institutions/                (Abstract Model Theory & Institutions)
    ├── vol2-observability/               (Reified Morphisms & Proof Synthesis)
    ├── vol3-sheaves/                     (Applied Topology & Cellular Sheaves)
    ├── vol4-effects/                     (Rope Pipelines & Substrate Invariants)
    └── vol5-cegis/                       (Grounded Sandboxing & Autonomous CEGIS)

packages/gargamelle-<name>/
├── README.md                             <-- TIER B: Standardized Package Monograph
└── src/                                  <-- TIER C: In-Code Hyperlinked Haddock
```

### The Three Tiers

| Tier | Scope | Location | Primary Audience |
| :--- | :--- | :--- | :--- |
| **Tier A** | The Gargamelle Treatise (Textbook) | `docs/textbook/` (Volumes I – V) | Logicians, Architects, Synthesis Engineers, Newcomers |
| **Tier B** | Standardized Package Monographs | `packages/gargamelle-*/README.md` | Package Consumers, Maintainers, PR Reviewers |
| **Tier C** | In-Code Hyperlinked Haddock | `packages/gargamelle-*/src/` | Day-to-Day API Consumers, IDE Code Completion |

---

## 3. The 5-Volume Treatise Curriculum (`docs/textbook/`)

To provide the textbook-level background knowledge necessary for engineers and researchers to understand the concepts behind Gargamelle, the treatise is organized into five thematic volumes:

### Volume I: Foundations of Abstract Model Theory & Categorical Institutions
*Location: `docs/textbook/vol1-institutions/`*
- **Objective:** Develop universal abstract logic from first principles without committing prematurely to any single concrete syntax.
- **Chapter 1: The Problem of Heterogeneous Logics.** Why hard-coding syntax fails in multi-language, multi-aspect verification and autonomous program synthesis.
- **Chapter 2: Signatures, Sentences, and Models.** Formalizing the Goguen-Burstall quadruple $(\mathbf{Sign}, \mathbf{Sen}, \mathbf{Mod}, \models)$ where $\mathbf{Sen} : \mathbf{Sign} \to \mathbf{Set}$ and $\mathbf{Mod} : \mathbf{Sign}^{\mathrm{op}} \to \mathbf{Cat}$.
- **Chapter 3: The Satisfaction Invariance Condition.** Detailed proofs, categorical commutative diagrams, and intuition for $m' \models_{\Sigma'} \mathbf{Sen}(\sigma)(e) \iff \mathbf{Mod}(\sigma)(m') \models_{\Sigma} e$.
- **Chapter 4: Institution Comorphisms.** Stepwise refinement passes and defunctionalized type-level signature translations mapping complex specification logics into simpler target representations.
- **Chapter 5: Pushout Feature Weaving ($B \amalg_C W$).** Non-invasive aspect integration, universal colimit factorizers, pullback protocol discovery ($A \times_E B$), and mediating semantic delta factorizers (`factorSemanticDelta`).

### Volume II: Reified Observability & Proof Synthesis
*Location: `docs/textbook/vol2-observability/`*
- **Objective:** Demystify epistemic transparency and show how replacing opaque closures with inspectable arrows enables SMT translation, persistence, and automated verification.
- **Chapter 1: The Tyranny of the Black Box.** Why opaque function closures `(a -> b)` undermine AI synthesis, serialization, SMT translation, and formal verification.
- **Chapter 2: Observable Morphisms (`ObsMor`).** Constructing serializable, introspectable category arrows with `Profunctor`, `Strong`, and `Choice` instances; inspecting AST structures without executing side-effects (`inspectObsMor`).
- **Chapter 3: The Free Verifier AST.** Contravariant functors, `Divisible` (product verification), and `Decidable` (sum verification); evaluating candidate models to produce `VerifiedSection` or accumulated `Counterexample`.
- **Chapter 4: Dual Assume-Guarantee Contracts.** Inverting lattices via `Algebra.Lattice.Op`; proving why refinement meet ($\wedge$) weakens assumptions while strengthening guarantees; verifying circular soundness (`verifyCircularAG`).
- **Chapter 5: The Host SMT Pipe.** Generating typed SMT-LIB2 from `ObsMor`, streaming over Linux pipes to host Z3 4.16, parsing SAT models into symbol maps, and mapping validity proofs directly to verifier evidence.

### Volume III: Applied Algebraic Topology & Cellular Sheaves
*Location: `docs/textbook/vol3-sheaves/`*
- **Objective:** Introduce algebraic topology as an operational engineering tool for fault localization and global consistency in distributed systems.
- **Chapter 1: Software Architectures as Cell Complexes.** Formalizing graph complexes, 0-cells (modules/vertices), 1-cells (interfaces/edges), boundary maps, star co-faces, homological incidence signs ($[e:u] = -1$, $[e:v] = +1$), and Euler characteristic $\chi = |V| - |E|$.
- **Chapter 2: Cellular Sheaves & Stalk Assignments.** Assigning contract stalks over cells, directional and symmetric restriction maps ($\rho_{u \trianglelefteq e}, \rho_{v \trianglelefteq e}$), and adjoint lifting maps.
- **Chapter 3: The Store Comonad on Cell Complexes.** Cellular space as `Store vId stalk`; evaluating local neighborhood inspection rules across all vertices simultaneously via comonadic `extend`.
- **Chapter 4: Knaster-Tarski Consensus Diffusion.** Monotonic contraction on meet semi-lattices; proving termination and convergence to greatest lower bounds (`diffuseUntilHarmonic`).
- **Chapter 5: The Sheaf Coboundary Operator ($\delta^0$) & Cohomological Obstructions ($H^1$).** Vanishing coboundaries as global sections; the Model Amalgamation Theorem $H^0(G; \mathbf{Mod}) \cong \mathbf{Mod}(\operatorname{colim} D)$; pinpointing failing interface boundaries with `locateObstructions` to guide automated program repair.

### Volume IV: Effectful Pipeline Architecture & Substrate Invariants
*Location: `docs/textbook/vol4-effects/`*
- **Objective:** Explain high-performance, predictable effect management and data representation for large-scale symbolic manipulation.
- **Chapter 1: The Kernmantle Arrow Rope.** Arrow composition, `Strand` separation, and static config-time requirement analysis (`Requirements` mantle inspection) prior to resource allocation.
- **Chapter 2: The Polytropos Substrate.** One flat `Rep` (tag plus a flat `SmallArray` of payload slots) unifying products and sums without pointer trees or Core explosion.
- **Chapter 3: Constant-Time $O(1)$ Variant Routing.** Eliminating linear case cascades via unboxed tag jump tables (`VariantRouter`, `routeVariantWith`).
- **Chapter 4: Profunctor Optics & Vectorized Updates.** Pure `Strong` lenses, `Choice` prisms, in-place slot updates (`setFieldAt`), and copy-on-write thaw semantics.
- **Chapter 5: Coyoneda Pipeline Fusion.** Fusing intermediate transformations without allocating intermediate wrapper arrows (`Rope.Fusion`).

### Volume V: Grounded Verification & Autonomous CEGIS
*Location: `docs/textbook/vol5-cegis/`*
- **Objective:** Ground abstract logic and topology in physically isolated Linux execution environments and database-backed learning loops.
- **Chapter 1: Linux Container Namespace Isolation.** How Bubblewrap (`/usr/bin/bwrap`) enforces private PID, IPC, UTS, and mount namespaces with `/usr/bin/timeout` and temp directory scoping.
- **Chapter 2: Grounded Evidence Persistence.** Beam SQLite schemas (`EvidenceRecordT`, `CounterexampleRecordT`, `RunRecordT`), transactional locking, and indexing prior failures to prevent synthesis regressions.
- **Chapter 3: Formally Verified Mealy Automata.** Enforcing synthesis loop topologies at compile time using `crem` and `singletons-base`.
- **Chapter 4: The End-to-End Sheaf-Gated CEGIS Loop.** Synthesize $\to$ Sandbox Run $\to$ Collect Evidence $\to$ Structural Similarity $\to$ Sheaf Coboundary Gate $\to$ Homological Obstruction Feedback $\to$ Repair.

---

## 4. Standardized Package Monographs (`packages/gargamelle-*/README.md`)

Every package in `packages/gargamelle-*` must contain a standardized `README.md` following this uniform 6-part anatomical template:

```markdown
# gargamelle-<name>

## 1. Executive Summary & Problem Framing
[What systems or mathematical problem does this package solve? Why does it exist independently?]

## 2. Mathematical Foundations & Theoretical Invariants
[Formal definitions, categorical diagrams, or topological theorems governing this package.]

## 3. Module Architecture & Repertoire Breadth
[Table of exported modules, key data types, and primary typeclasses.]

## 4. Executable Worked Examples
[Compilable, literate code blocks demonstrating core workflows.]

## 5. Integration Points & Subsystem Boundaries
[Which lower-tier packages does it consume? Which upper-tier packages consume it?]

## 6. Diagnostic & Troubleshooting Guide
[Common compiler errors, type mismatch patterns, or runtime exceptions and how to resolve them.]
```

### Guidelines for Monograph Content
1. **Self-Contained Examples:** Code blocks in Section 4 must be fully compilable with explicit imports.
2. **Clear Boundaries:** Section 5 must explicitly trace upstream inputs and downstream outputs within the tier DAG.
3. **Troubleshooting Depth:** Section 6 must address real diagnostic failure modes (e.g. SMT timeout, missing sandbox binary, unsatisfiable coboundary constraint).

---

## 5. Programmatic Recommendations & Tooling Automation

To prevent documentation drift and ensure that tutorials and textbook chapters remain 100% verified against code changes:

### 1. Multi-GHC Literate Markdown Verification (`cabal-docspec` or `markdown-unlit`)
- **Multi-Compiler Matrix:** Configure a dedicated check (`./bin/gargamelle-doccheck` or Cabal test-suite) that extracts and typechecks all code blocks across the full supported GHC matrix (GHC 9.6, 9.8, 9.10, 9.12, 9.14) under `-Wall -Werror`.
- **Zero Drift:** Any breaking API change, renamed identifier, or altered type signature immediately fails the build, preventing stale code snippets from entering master.

### 2. GHC Notes Architecture & Mechanical `tagref` Validation
- **In-Code Invariants:** Large architectural invariants, categorical diagrams, and memory physics are preserved in top-level block comments formatted as GHC Notes (`{- Note [Title] ~~~~ [tag:<slug>] -}`).
- **Call-Site Cross-References:** Internal code locations reference notes via `-- See Note [Title] [ref:<slug>]`.
- **Mechanical Integrity:** Integrate `tagref` into `./bin/gargamelle-verify` to validate that tags are unique and references are never dangling across code, monographs, and treatise volumes.
- **Bidirectional mdBook Interlinking:** In-code GHC Notes cite `docs/textbook/` chapters, and textbook chapters link directly back to `[ref:<slug>]` code definitions.

### 3. Elevated Comment Density Target (50%+)
- **Mathematical Opacity Prevention:** The intrinsic conceptual depth of categorical institutions, cellular sheaves, coboundary operators, and namespace isolation demands extensive explanatory prose.
- **Density Target:** Maintain an in-code comment density of **50%+** across `packages/*/src/` (measured via `cloc packages/`), grown constructively through formal GHC Notes, law specifications, ASCII commutative diagrams, and mdBook interlinking.

### 4. `mdBook` with MathJax & Mermaid Rendering
- **Tooling:** Host the textbook under `docs/textbook/` configured via `book.toml`.
- **Mathematical Typesetting:** MathJax rendering for rich mathematical notation:
  $$\delta^0 : C^0(G; \mathcal{F}) \to C^1(G; \mathcal{F})$$
  $$H^0(G; \mathbf{Mod}) \cong \mathbf{Mod}(\operatorname{colim} D)$$
  $$B \amalg_C W, \quad A \times_E B, \quad m' \models_{\Sigma'} \mathbf{Sen}(\sigma)(e)$$
- **Diagrams:** Native Mermaid flowcharts and state diagrams for state machines and categorical pushouts.
- **Output:** Searchable, zero-dependency offline HTML book suitable for local reference and documentation hosting.

### 5. Automated Haddock Cross-Linking
- **Build Flag:** Compile all 11 packages with `cabal haddock --haddock-options="--hyperlinked-source --quickjump"`.
- **Deep Linking:** Embed direct hyperlinks from textbook terms and monograph sections to exact source code definitions and Haddock entities.

### 6. Deterministic Precedence Enforcement
- Grounded in `docs/notes/DOC_STRATEGY.md` §4:
  > **Code wins at runtime; notes corrected regardless.**  
  > When a code refactor invalidates a claim, proof, or code example in the treatise or package monograph, the authoring change set must update the documentation simultaneously. Stale documentation is treated as a build failure.

---

## Related Documents

- [`docs/notes/EXPOSITORY_AND_TUTORIAL_FRAMEWORK.md`](notes/EXPOSITORY_AND_TUTORIAL_FRAMEWORK.md) — Comprehensive design note and proposal.
- [`docs/notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md) — Documentation policy, genres, and authority.
- [`docs/INDEX.md`](INDEX.md) — Complete repository inventory and reading paths.
- [`docs/TUTORIAL.md`](TUTORIAL.md) — Current 5-lesson hands-on walkthrough.
- [`docs/MAINTAINER_GUIDE.md`](MAINTAINER_GUIDE.md) — Maintainer standards and quality gates.
