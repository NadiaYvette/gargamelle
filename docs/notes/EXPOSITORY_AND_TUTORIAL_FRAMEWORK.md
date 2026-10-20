<!--
SPDX-License-Identifier: EUPL-1.2
-->
# The Gargamelle Expository & Tutorial Framework

**Status:** PROPOSAL & SPECIFICATION · v1.0 · 2026-10-20  
**Authors:** Nadia Yvette Chambers & Antigravity (Google / gemini-3.8-pro)  
**Parent Strategy:** [`docs/notes/DOC_STRATEGY.md`](DOC_STRATEGY.md)  
**Corpus Inventory:** [`docs/INDEX.md`](../INDEX.md)  

---

## 1. Motivation: Why Gargamelle Demands a Textbook

`polytropos` addresses a focused compiler-performance bottleneck: the superlinear Core explosion of large records/variants, solved via a single unboxed `Rep` substrate and a TcPlugin. Its documentation, while rigorous, operates primarily within standard type-level Haskell idioms.

`gargamelle`, by contrast, operates at the intersection of five demanding mathematical and systems engineering domains:
1. **Abstract Model Theory & Higher Categories:** Goguen-Burstall Institutions, Comorphisms, Pushouts, Colimits, Proarrow equipments, and Defunctionalized 2-categories.
2. **Applied Algebraic Topology:** 1-dimensional Cell Complexes, Graded cell posets, Star co-faces, Cellular Sheaves, Coboundary operators $\delta^0$, and $H^1$ Cohomological Obstructions.
3. **Order Theory & Comonadic Dynamics:** Store Comonads, Monotonic contract meet semi-lattices (`Algebra.Lattice.Op`), and Knaster-Tarski fixed-point consensus diffusion.
4. **Epistemic Observability & Automated Theorem Proving:** Reified observable morphisms (`ObsMor`), Free verifier ASTs (`VerifierAST`, `Divisible`, `Decidable`), and streaming SMT-LIB2 pipes to Z3.
5. **Grounded Systems Sandboxing & Verified Automata:** Linux container namespace isolation via Bubblewrap (`/usr/bin/bwrap`), Beam SQLite ORM schemas, and Crem Mealy state machines.

Standard API documentation (even verbose Haddock) cannot bridge this conceptual threshold. Without **textbook-level expository material** that develops mathematical intuition from first principles alongside runnable Haskell code, users and contributors will struggle to understand *why* the abstractions exist and *how* to compose them.

---

## 2. The 3-Tier Documentation Hierarchy

To organize this material cleanly across the repository without cluttering code directories, we establish a 3-tier hierarchy:

```
┌────────────────────────────────────────────────────────────────────────┐
│ TIER A: The Gargamelle Treatise (Suite-Wide Conceptual Textbook)       │
│   Location: docs/textbook/ (Volumes I – V)                             │
│   Audience: Logicians, Architects, Synthesis Engineers, Newcomers     │
├────────────────────────────────────────────────────────────────────────┤
│ TIER B: Standardized Package Monographs                                │
│   Location: packages/gargamelle-*/README.md & docs/                    │
│   Audience: Package Consumers, Maintainers, PR Reviewers               │
├────────────────────────────────────────────────────────────────────────┤
│ TIER C: In-Code Hyperlinked Haddock                                    │
│   Location: In-source documentation (--hyperlinked-source)             │
│   Audience: Day-to-Day API Consumers, IDE Code Completion               │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Tier A: The Gargamelle Treatise (Textbook Curriculum)

The central textbook lives in `docs/textbook/`, divided into five thematic volumes:

### Volume I: Foundations of Abstract Model Theory & Institutions
*Location: `docs/textbook/vol1-institutions/`*
- **Chapter 1: The Problem of Heterogeneous Logics.** Why hard-coding syntax fails in multi-language and multi-aspect synthesis.
- **Chapter 2: Signatures, Sentences, and Models.** Formalizing the Goguen-Burstall quadruple $(\mathbf{Sign}, \mathbf{Sen}, \mathbf{Mod}, \models)$.
- **Chapter 3: The Satisfaction Invariance Condition.** Detailed proofs and categorical diagrams for $\models_{\Sigma'}$ vs. $\models_{\Sigma}$.
- **Chapter 4: Institution Comorphisms.** Stepwise refinement passes and defunctionalized signature translations.
- **Chapter 5: Pushout Feature Weaving ($B \amalg_C W$).** Non-invasive aspect integration, universal colimit factorizers, and semantic delta propagation.

### Volume II: Reified Observability & Proof Synthesis
*Location: `docs/textbook/vol2-observability/`*
- **Chapter 1: The Tyranny of the Black Box.** Why opaque function closures `(a -> b)` destroy verifiability and persistence.
- **Chapter 2: Observable Morphisms (`ObsMor`).** Constructing serializable, introspectable category arrows with `Profunctor`, `Strong`, and `Choice`.
- **Chapter 3: The Free Verifier AST.** Contravariant functors, `Divisible` (product verification), and `Decidable` (sum verification).
- **Chapter 4: Dual Assume-Guarantee Contracts.** Inverting lattices via `Algebra.Lattice.Op`; circular soundness proofs.
- **Chapter 5: The Host SMT Pipe.** Generating typed SMT-LIB2 from `ObsMor`, communicating over Linux pipes with Z3 4.16, and parsing countermodels.

### Volume III: Applied Algebraic Topology & Cellular Sheaves
*Location: `docs/textbook/vol3-sheaves/`*
- **Chapter 1: Software Architectures as Cell Complexes.** Formalizing graph complexes, 0-cells (modules), 1-cells (interfaces), boundary maps, and Euler characteristic $\chi = |V| - |E|$.
- **Chapter 2: Cellular Sheaves & Stalk Assignments.** Stalks over cells, restriction maps ($\rho_{u \trianglelefteq e}, \rho_{v \trianglelefteq e}$), and adjoint lifting.
- **Chapter 3: The Store Comonad on Cell Complexes.** Cellular space as `Store vId stalk`; evaluating local neighborhood rules simultaneously via comonadic `extend`.
- **Chapter 4: Knaster-Tarski Consensus Diffusion.** Monotonic contraction on meet semi-lattices; proving convergence to greatest lower bounds.
- **Chapter 5: The Sheaf Coboundary Operator ($\delta^0$) & Cohomological Obstructions ($H^1$).** Vanishing coboundaries as global sections; the Model Amalgamation Theorem $H^0(G; \mathbf{Mod}) \cong \mathbf{Mod}(\operatorname{colim} D)$; pinpointing failing interface boundaries with `locateObstructions`.

### Volume IV: Effectful Pipelines & Substrate Invariants
*Location: `docs/textbook/vol4-effects/`*
- **Chapter 1: The Kernmantle Arrow Rope.** Arrow composition, strands, and static config-time requirement analysis.
- **Chapter 2: The Polytropos Substrate.** One flat `Rep` (tag + `SmallArray`) unifying products and sums without pointer trees.
- **Chapter 3: Constant-Time $O(1)$ Variant Routing.** Eliminating linear case cascades via unboxed tag jump tables (`VariantRouter`).
- **Chapter 4: Profunctor Optics & Vectorized Updates.** In-place slot updates (`setFieldAt`) and copy-on-write thaw semantics.
- **Chapter 5: Coyoneda Pipeline Fusion.** Fusing intermediate transformations without allocating wrapper arrows.

### Volume V: Grounded Verification & Autonomous CEGIS
*Location: `docs/textbook/vol5-cegis/`*
- **Chapter 1: Linux Container Namespace Isolation.** How Bubblewrap (`/usr/bin/bwrap`) enforces private PID, IPC, UTS, and mount namespaces with `/usr/bin/timeout`.
- **Chapter 2: Grounded Evidence Persistence.** Beam SQLite schemas (`EvidenceRecordT`, `CounterexampleRecordT`, `RunRecordT`) and file locking.
- **Chapter 3: Formally Verified Mealy Automata.** Enforcing synthesis loop topologies at compile time using `crem` and `singletons-base`.
- **Chapter 4: The End-to-End Sheaf-Gated CEGIS Loop.** Synthesize $\to$ Sandbox Run $\to$ Collect Evidence $\to$ Similarity Check $\to$ Sheaf Coboundary Gate $\to$ Repair.

---

## 4. Tier B: Standardized Package Monograph Specification

Every package in `packages/gargamelle-*` must contain a standardized `README.md` following this 6-part anatomy:

```markdown
# gargamelle-<name>

## 1. Executive Summary & Problem Framing
[What problem does this package solve? Why does it exist independently?]

## 2. Mathematical Foundations & Theoretical Invariants
[Formal definitions, categorical diagrams, or topological theorems governing this package.]

## 3. Module Map & Repertoire Breadth
[Table of exported modules, key data types, and primary typeclasses.]

## 4. Executable Worked Examples
[Compilable, literate code blocks demonstrating core workflows.]

## 5. Integration Points & Subsystem Boundaries
[Which lower-tier packages does it consume? Which upper-tier packages consume it?]

## 6. Diagnostic & Error Resolution Guide
[Common compiler errors, type mismatch patterns, or runtime exceptions and how to resolve them.]
```

---

## 5. Programmatic & Literate Tooling Recommendations

To ensure that the textbook and package monographs never suffer from bit rot or documentation drift, we recommend adopting:

1. **Literate Haskell / Markdown Verification (`cabal-docspec` or `markdown-unlit`):**
   - Configure a dedicated Cabal test arm `test-suite docs` that runs all code blocks in `docs/textbook/` and package `README.md` files against GHC 9.14.
   - Any broken import or type mismatch in a tutorial immediately fails the CI/verification gate.
2. **`mdBook` with MathJax Rendering:**
   - Host the textbook under `docs/textbook/` formatted for `mdBook` (`book.toml`).
   - Automatically render LaTeX math ($\delta^0, \amalg, H^1, \cong, \le$) and Mermaid diagrams into a fast, searchable offline HTML book.
3. **Automated Haddock Cross-Linking:**
   - Compile all 11 packages with `haddock --hyperlinked-source --quickjump`.
   - Embed direct hyperlinks from textbook terms to Hackage/Haddock identifiers.
4. **Deterministic Precedence Enforcement:**
   - Grounded in `DOC_STRATEGY.md` §4: Code wins at runtime; when code changes invalidate a textbook proof or code snippet, the change set must update the textbook simultaneously.
