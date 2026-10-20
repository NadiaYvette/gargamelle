<!--
SPDX-License-Identifier: EUPL-1.2
-->
# Staged Documentation Roll-Out Plan

**Status:** PLAN · v1.0 · 2026-10-20  
**Authors:** Nadia Yvette Chambers & Antigravity (Google / gemini-3.8-pro)  
**Parent Strategy:** [`notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md)  
**Reference Specification:** [`FRAMEWORK_RECOMMENDATIONS.md`](FRAMEWORK_RECOMMENDATIONS.md)  
**Detailed Proposal:** [`notes/EXPOSITORY_AND_TUTORIAL_FRAMEWORK.md`](notes/EXPOSITORY_AND_TUTORIAL_FRAMEWORK.md)  
**Corpus Inventory:** [`INDEX.md`](INDEX.md)  

---

## 1. Executive Summary & Roll-Out Philosophy

This document outlines the **Staged Documentation Roll-Out Plan** for the Gargamelle suite.

If *"roll-out"* sounds incongruously informal in an enterprise or scholarly setting, *"implementation"* sounds ontologically odder when applied to prose, pedagogical monographs, and mathematical treatises. Documentation is not simply an implementation artifact; it is an epistemic interface between mathematical theory, systems engineering, human developers, and autonomous agents.

### The Sequencing Strategy: Easiest First, Treatise Grounded in Consumers

The core thesis of this roll-out plan is **progressive disclosure and immediate forge verifiability**:

```
┌────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: Immediate Forge Surfaces & Reading Paths (Lowest Effort)      │
│   • Polish Root README.md for multi-forge rendering                    │
│   • Align NEWBIE_GUIDE, TUTORIAL, MAINTAINER_GUIDE, and INDEX.md       │
│   • Immediate visual feedback on GitHub, GitCode, Disroot, Framagit    │
├────────────────────────────────────────────────────────────────────────┤
│ PHASE 2: Standardized Package Monographs (11 Packages)                 │
│   • Uniform 6-part anatomical template in packages/gargamelle-*/README │
│   • High structure, bounded scope, immediate per-package forge landing │
│   • Ordered by architectural tier (Substrate → Logics → Sheaf/Workflow)│
├────────────────────────────────────────────────────────────────────────┤
│ PHASE 3: Programmatic Verification Harness & Tooling                   │
│   • Typecheck literate Haskell code blocks via cabal-docspec / unlit   │
│   • mdBook scaffold with MathJax and Mermaid support                   │
│   • Hyperlinked Haddock cross-reference verification                   │
├────────────────────────────────────────────────────────────────────────┤
│ PHASE 4: The 5-Volume Foundational Treatise (Highest Depth)            │
│   • Authored concurrently with consumer libraries (especially          │
│     sarutahiko) to ground abstract theory in real synthesis campaigns  │
│   • 24 chapters across Institutions, Observability, Sheaves, Effects,  │
│     and CEGIS                                                          │
└────────────────────────────────────────────────────────────────────────┘
```

1. **Easiest Parts First (Phases 1 & 2):**  
   We begin by establishing clean, high-visibility markdown documents at the root and within each of the 11 package directories. By pushing these immediately to our five public git hosting mirrors (`github`, `gitcode`, `disroot`, `framagit`, and `rad`), we can visually inspect formatting, typography, MathJax formulas, Mermaid diagrams, tables, and link resolutions across distinct web frontends without waiting for hundreds of pages of textbook prose.

2. **Heavy Pedagogical Prose Sequenced Concurrently with Consumers (Phase 4):**  
   The most voluminous and demanding component—the 5-volume foundational textbook in `docs/textbook/`—is deliberately deferred to Phase 4. Writing textbook-level pedagogical material in a vacuum leads to sterile, speculative exposition. Instead, authoring these volumes **concurrently with consumer projects (principally [`sarutahiko`](~/src/sarutahiko))** ensures that every mathematical definition, categorical diagram, sheaf coboundary computation, and CEGIS loop is grounded in real, empirical autonomous coding campaigns.

---

## 2. Multi-Forge Rendering Targets & Visual Inspection Criteria

Gargamelle mirrors across five distinct git hosting environments, each with its own markdown dialect, CSS stylesheet, MathJax/KaTeX parser, and sanitization rules. Every document released in Phases 1 and 2 must be verified against the following matrix:

| Forge Remote | URL / Identifier | Markdown Engine | Math Support | Diagram Support | Key Verification Checks |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`github`** | [`github.com/NadiaYvette/gargamelle`](https://github.com/NadiaYvette/gargamelle) | GitHub Flavored Markdown (GFM) | Native MathJax (`$...$`, `$$...$$`) | Native Mermaid (` ```mermaid `) | GFM Alerts (`> [!NOTE]`), MathJax rendering, table alignment, anchor link jumps. |
| **`gitcode`** | [`gitcode.com/NadiaYvette/gargamelle`](https://gitcode.com/NadiaYvette/gargamelle) | GitCode GFM Dialect | KaTeX / MathJax | Mermaid codeblocks | UTF-8 mathematical symbols ($\amalg, \times, \delta^0, \models$), table column wrapping. |
| **`disroot`** | [`git.disroot.org/NadiaYvette/gargamelle`](https://git.disroot.org/NadiaYvette/gargamelle) | Forgejo Markdown Engine | KaTeX syntax | Mermaid codeblocks | Monospace code styling, relative hyperlink paths to `docs/` and `packages/`. |
| **`framagit`** | [`framagit.org/NadiaYvette/gargamelle`](https://framagit.org/NadiaYvette/gargamelle) | GitLab Flavored Markdown (GLFM) | GLFM Math (`$` or `math` block) | GitLab Mermaid parser | Table borders, codeblock copy buttons, cross-repository references. |
| **`rad`** | `rad://zqykaqjnoA8a1harMdQVsigC7VwH` | Radicle Heartwood / Terminal | Pure ASCII / UTF-8 Markdown | Plain text fallback | Pure terminal markdown readability (`rad patch`, `rad show`, text browser). |

### Universal Formatting Rules for Maximum Portability
- **Fenced Math:** Avoid obscure LaTeX packages; restrict math to standard TeX macros supported universally by both MathJax and KaTeX ($B \amalg_C W$, $A \times_E B$, $\delta^0 : C^0 \to C^1$, $H^1 = \operatorname{coker} \delta^0$).
- **Relative Hyperlinks:** Always use relative links within the repository (e.g. `[DOC_STRATEGY](docs/notes/DOC_STRATEGY.md)` or `[gargamelle-sheaf](packages/gargamelle-sheaf/README.md)`), avoiding absolute paths or forge-specific URL prefixes.
- **Table Cell Padding:** Avoid embedded multiline code blocks inside table cells; use inline code backticks or bulleted sub-lists.

---

## 3. Phase Breakdown & Execution Milestones

### Phase 1: High-Visibility Forge Surfaces & Reading Paths (Immediate)

**Goal:** Ensure that any visitor landing on any mirror's main repository page immediately encounters a compelling, beautifully rendered, and navigable orientation surface.

- [x] **Milestone 1.1: Root `README.md` Forge Polish**
  - **Artifact:** [`README.md`](../README.md)
  - **Content:** Architectural tier map, 11-package register, Rabelaisian naming rationale, plain-English conceptual explanations, and deterministic verification quickstarts.
  - **Forge Verification:** Confirmed rendering of ASCII diagrams, math notation, and package table across GitHub, GitCode, Disroot, and Framagit.

- [ ] **Milestone 1.2: Core Orientation Guides Polish**
  - **Artifacts:**
    - [`docs/INDEX.md`](INDEX.md) (Corpus inventory and curated reading paths)
    - [`docs/NEWBIE_GUIDE.md`](NEWBIE_GUIDE.md) (Progressive disclosure funnel & token conservation)
    - [`docs/TUTORIAL.md`](TUTORIAL.md) (5-lesson interactive walkthrough from ObsMor to Crem CEGIS)
    - [`docs/MAINTAINER_GUIDE.md`](MAINTAINER_GUIDE.md) (Governance, 4 physical verification gates, commit attribution)
  - **Action:** Verify all intra-corpus relative links resolve cleanly on all four web forges. Ensure tables and headers follow `DOC_STRATEGY.md` status metadata conventions.

- [ ] **Milestone 1.3: Multi-Compiler & Matrix Documentation**
  - **Artifact:** [`docs/developer/BUILD_SYSTEMS_MATRIX.md`](developer/BUILD_SYSTEMS_MATRIX.md)
  - **Action:** Verify copy-pasteable build commands for Cabal, Stack, and Nix across GHC 9.6, 9.8, 9.10, 9.12, and 9.14.

---

### Phase 2: Standardized Package Monographs (11 Packages)

**Goal:** Provide an immediate landing document (`README.md`) inside each package directory under `packages/gargamelle-*`, so that navigating into any package on git hosting mirrors displays a self-contained, authoritative monograph.

Each monograph adheres strictly to the **6-Part Anatomical Template** defined in [`FRAMEWORK_RECOMMENDATIONS.md`](FRAMEWORK_RECOMMENDATIONS.md) §4:
1. Executive Summary & Problem Framing
2. Mathematical Foundations & Theoretical Invariants
3. Module Architecture & Repertoire Breadth
4. Executable Worked Examples (compilable, literate code blocks)
5. Integration Points & Subsystem Boundaries (Tier DAG)
6. Diagnostic & Troubleshooting Guide

#### Authorship Batches (Sequenced by Architectural Tier)

```
┌────────────────────────────────────────────────────────────────────────┐
│ Batch 2A: Substrate & Semantic Foundations (Tiers 2 & 3)               │
│   ├── packages/gargamelle-logic/README.md      (Syntax, Op Lattice, AG)│
│   ├── packages/gargamelle-effect/README.md     (Rope, Router, Fusion)  │
│   ├── packages/gargamelle-model/README.md      (ObsMor, VerifierAST)   │
│   └── packages/gargamelle-evidence/README.md   (hs-tree-sitter, Diff)  │
├────────────────────────────────────────────────────────────────────────┤
│ Batch 2B: Logics, Infrastructure & Environment (Tier 4)                │
│   ├── packages/gargamelle-core/README.md       (Institutions, Weaving) │
│   ├── packages/gargamelle-fol/README.md        (Z3 Pipe, Hyperdoctrine)│
│   ├── packages/gargamelle-equational/README.md (Equational, DPO Rewr)  │
│   ├── packages/gargamelle-sandbox/README.md    (Bubblewrap Containers) │
│   └── packages/gargamelle-persistence/README.md(Beam SQLite Storage)   │
├────────────────────────────────────────────────────────────────────────┤
│ Batch 2C: Topological Sheaves & Autonomous Orchestration (Tier 5)      │
│   ├── packages/gargamelle-sheaf/README.md      (Sheaves, Store, H¹)    │
│   └── packages/gargamelle-workflow/README.md   (Crem State Mach, CEGIS)│
└────────────────────────────────────────────────────────────────────────┘
```

- [ ] **Milestone 2.1: Batch 2A Monographs (Substrates & Semantics)**
  - `packages/gargamelle-logic/README.md`: Order-theoretic contracts (`Algebra.Lattice.Op`), contravariant Galois connections, and syntax ASTs.
  - `packages/gargamelle-effect/README.md`: Kernmantle Arrow Rope pipelines, $O(1)$ variant jump-table routing, profunctor optics, and Coyoneda fusion.
  - `packages/gargamelle-model/README.md`: 100% observable morphisms (`ObsMor`), Free `VerifierAST`, `Divisible`/`Decidable` trees, and inspection.
  - `packages/gargamelle-evidence/README.md`: Concrete syntax trees via `hs-tree-sitter`, semantic diffing via `tree-diff`, and similarity metrics.

- [ ] **Milestone 2.2: Batch 2B Monographs (Logics & Host Infrastructure)**
  - `packages/gargamelle-core/README.md`: Goguen-Burstall Institutions, pushout feature weaving ($B \amalg_C W$), pullback protocol discovery ($A \times_E B$), and colimits.
  - `packages/gargamelle-fol/README.md`: First-order logic, hyperdoctrines, refinement calculi, and streaming Z3 SMT-LIB2 pipe.
  - `packages/gargamelle-equational/README.md`: Equational logic institution and presheaf Double-Pushout (DPO) algebraic rewriting.
  - `packages/gargamelle-sandbox/README.md`: Linux container namespace isolation via Bubblewrap (`/usr/bin/bwrap`), resource limits, and filesystem scoping.
  - `packages/gargamelle-persistence/README.md`: Beam SQLite persistence (`EvidenceRecordT`, `CounterexampleRecordT`, `RunRecordT`), transactional locking, and indexing.

- [ ] **Milestone 2.3: Batch 2C Monographs (Topology & Autonomous Workflow)**
  - `packages/gargamelle-sheaf/README.md`: 1D Cell complexes, cellular sheaves, Store comonad cellular diffusion, Knaster-Tarski consensus, and $H^1$ homological fault localization.
  - `packages/gargamelle-workflow/README.md`: Crem Mealy state machines (`singletons-base`), sheaf-gated CEGIS loop (`runSheafGatedCEGIS`), and automated repair guidance.

---

### Phase 3: Programmatic Verification Harness & Tooling Automation

**Goal:** Mechanically eliminate documentation drift by integrating automated test suites that typecheck all markdown code snippets and validate links on CI.

- [ ] **Milestone 3.1: Literate Markdown Doc-Testing (`cabal-docspec` / `markdown-unlit`)**
  - Configure a dedicated Cabal test target or script (`./bin/gargamelle-doccheck`) that extracts all Haskell code blocks from package READMEs, tutorials, and textbook chapters.
  - Enforce that code blocks compile cleanly under GHC 9.14 with `-Wall -Werror`.
  - Enforces `DOC_STRATEGY.md` §4: *Code wins at runtime; notes corrected regardless.* Stale documentation becomes a hard compilation failure.

- [ ] **Milestone 3.2: Deterministic Intra-Corpus Link & Anchor Verification**
  - Implement a lightweight link verification check validating that every markdown hyperlink (`[text](path.md#anchor)`) resolves to a physical file and header.

- [ ] **Milestone 3.3: `mdBook` Local Site Scaffold**
  - Initialize `docs/textbook/book.toml` with `mdbook-mermaid` and MathJax support for offline reading and local HTML book rendering.

- [ ] **Milestone 3.4: Automated Haddock Hyperlinking & Cross-Linking**
  - Maintain `./bin/gargamelle-haddock` generating hyperlinked source Haddock trees (`--hyperlinked-source --quickjump`) across all 11 packages.

---

### Phase 4: The 5-Volume Foundational Treatise (Concurrent with `sarutahiko`)

**Goal:** Author the comprehensive 24-chapter textbook curriculum (`docs/textbook/`) providing the rigorous mathematical, philosophical, and architectural background required to understand and extend Gargamelle.

#### Why Co-Development with `sarutahiko` Is Mandatory
Writing textbook-level exposition on higher categories, cellular sheaves, and autonomous CEGIS requires grounded, real-world case studies. [`sarutahiko`](~/src/sarutahiko) serves as the primary real-world consumer of `gargamelle`, utilizing its institutions, verifiers, and sandboxed execution to synthesize patches for production systems. 

Authoring the textbook concurrently with `sarutahiko` ensures that:
- Every theorem has an empirical benchmark in `sarutahiko`.
- Every SMT example reflects real automated bug-repair queries.
- Every sheaf coboundary diagram reflects real multi-service architectural boundaries.
- The prose remains vital, concrete, and battle-tested.

```
┌────────────────────────────────────────────────────────────────────────┐
│ VOLUME I: Abstract Model Theory & Categorical Institutions             │
│   • Grounded in: sarutahiko's multi-language AST translation & syntax  │
│   • Chapters: Heterogeneous Logics, Signatures/Sentences/Models,       │
│               Satisfaction Invariance, Comorphisms, Pushout Weaving    │
├────────────────────────────────────────────────────────────────────────┤
│ VOLUME II: Reified Observability & Proof Synthesis                     │
│   • Grounded in: sarutahiko's verifier synthesis & Z3 SMT pipes        │
│   • Chapters: Tyranny of Closures, ObsMor Category, Free VerifierAST,  │
│               Dual AG Contracts (Op Lattice), Host Z3 SMT Pipe         │
├────────────────────────────────────────────────────────────────────────┤
│ VOLUME III: Applied Algebraic Topology & Cellular Sheaves              │
│   • Grounded in: sarutahiko's multi-module architectures & boundaries  │
│   • Chapters: Cell Complexes, Sheaves & Stalks, Store Comonad,         │
│               Knaster-Tarski Diffusion, Coboundary δ⁰ & H¹ Obstructions│
├────────────────────────────────────────────────────────────────────────┤
│ VOLUME IV: Effectful Pipeline Architecture & Substrate Invariants      │
│   • Grounded in: sarutahiko's pipeline engine & high-throughput loops  │
│   • Chapters: Kernmantle Arrow Rope, Polytropos Flat Rep, O(1) Router, │
│               Profunctor Optics, Coyoneda Pipeline Fusion              │
├────────────────────────────────────────────────────────────────────────┤
│ VOLUME V: Grounded Verification & Autonomous CEGIS                     │
│   • Grounded in: sarutahiko's autonomous programming campaigns         │
│   • Chapters: Bubblewrap Sandboxing, Beam SQLite Evidence Persistence, │
│               Crem Mealy Automata, The End-to-End Sheaf CEGIS Loop     │
└────────────────────────────────────────────────────────────────────────┘
```

#### Curriculum Delivery Schedule

- [ ] **Milestone 4.1: Volume I — Foundations of Abstract Model Theory & Categorical Institutions**  
  *Path: `docs/textbook/vol1-institutions/`*  
  Co-developed with `sarutahiko`'s cross-language interface specifications. Explains why hard-coded syntax fails, formalizes the Goguen-Burstall satisfaction condition, and proves pushout feature amalgamation ($B \amalg_C W$).

- [ ] **Milestone 4.2: Volume II — Reified Observability & Proof Synthesis**  
  *Path: `docs/textbook/vol2-observability/`*  
  Co-developed with `sarutahiko`'s verifier generation engine. Eliminates black-box functions, constructs `ObsMor` and `VerifierAST`, develops dual assume-guarantee contracts via `Algebra.Lattice.Op`, and streams typed SMT-LIB2 to Z3.

- [ ] **Milestone 4.3: Volume III — Applied Algebraic Topology & Cellular Sheaves**  
  *Path: `docs/textbook/vol3-sheaves/`*  
  Co-developed with `sarutahiko`'s architectural boundary analysis. Introduces 1D cell complexes, restriction maps, the Store comonad on graph complexes, Knaster-Tarski diffusion, and $H^1$ homological obstruction localization.

- [ ] **Milestone 4.4: Volume IV — Effectful Pipeline Architecture & Substrate Invariants**  
  *Path: `docs/textbook/vol4-effects/`*  
  Co-developed with `sarutahiko`'s runtime execution pipeline. Demonstrates Kernmantle arrow composition, Polytropos flat `Rep` memory layouts, $O(1)$ variant jump-table routing, and copy-on-write profunctor optics.

- [ ] **Milestone 4.5: Volume V — Grounded Verification & Autonomous CEGIS**  
  *Path: `docs/textbook/vol5-cegis/`*  
  Co-developed with `sarutahiko`'s full autonomous patch-synthesis campaigns. Covers Linux container isolation via Bubblewrap, Beam SQLite run tracking, verified Mealy state machines, and the complete sheaf-gated CEGIS synthesis loop.

---

## 4. Documentation Roll-Out Ledger & Status Matrix

This living register tracks the status of every planned documentation artifact across all roll-out phases:

| Artifact Path | Phase | Status | Primary Mirror Focus | Co-Development Anchor |
| :--- | :---: | :---: | :--- | :--- |
| `README.md` | Phase 1 | **implemented** | All Mirrors (`github`, `gitcode`, `disroot`, `framagit`, `rad`) | Gargamelle Suite Architecture |
| `docs/INDEX.md` | Phase 1 | **live** | GitHub & Forgejo navigation | Corpus Inventory |
| `docs/NEWBIE_GUIDE.md` | Phase 1 | **live** | Reading paths & token conservation | Newcomer Orientation |
| `docs/TUTORIAL.md` | Phase 1 | **live** | GFM Code formatting & walkthrough | 5-Lesson Tutorial |
| `docs/MAINTAINER_GUIDE.md` | Phase 1 | **live** | Quality gates & commit conventions | Governance |
| `docs/developer/BUILD_SYSTEMS_MATRIX.md` | Phase 1 | **live** | Matrix command copy-paste | Cabal, Stack, Nix Tooling |
| `packages/gargamelle-logic/README.md` | Phase 2 | **draft** | In-directory monograph rendering | `gargamelle-logic` |
| `packages/gargamelle-effect/README.md` | Phase 2 | **draft** | In-directory monograph rendering | `gargamelle-effect`, `polytropos`, `kernmantle` |
| `packages/gargamelle-model/README.md` | Phase 2 | **draft** | In-directory monograph rendering | `gargamelle-model` |
| `packages/gargamelle-evidence/README.md`| Phase 2 | **draft** | In-directory monograph rendering | `gargamelle-evidence` |
| `packages/gargamelle-core/README.md` | Phase 2 | **draft** | In-directory monograph rendering | `gargamelle-core`, `proarrow` |
| `packages/gargamelle-fol/README.md` | Phase 2 | **draft** | In-directory monograph rendering | `gargamelle-fol`, Z3 |
| `packages/gargamelle-equational/README.md`| Phase 2 | **draft** | In-directory monograph rendering | `gargamelle-equational` |
| `packages/gargamelle-sandbox/README.md` | Phase 2 | **draft** | In-directory monograph rendering | `gargamelle-sandbox`, Bubblewrap |
| `packages/gargamelle-persistence/README.md`| Phase 2 | **draft** | In-directory monograph rendering | `gargamelle-persistence`, Beam SQLite |
| `packages/gargamelle-sheaf/README.md` | Phase 2 | **draft** | In-directory monograph rendering | `gargamelle-sheaf` |
| `packages/gargamelle-workflow/README.md`| Phase 2 | **draft** | In-directory monograph rendering | `gargamelle-workflow`, Crem |
| `./bin/gargamelle-doccheck` | Phase 3 | **planned** | Deterministic CI Gate | Literate code verification |
| `docs/textbook/book.toml` | Phase 3 | **planned** | mdBook offline site | Local HTML rendering |
| `docs/textbook/vol1-institutions/` | Phase 4 | **planned** | Academic / Scholarly readers | `sarutahiko` Interface Synthesis |
| `docs/textbook/vol2-observability/` | Phase 4 | **planned** | Academic / Scholarly readers | `sarutahiko` Verifier Synthesis |
| `docs/textbook/vol3-sheaves/` | Phase 4 | **planned** | Academic / Scholarly readers | `sarutahiko` Architecture Synthesis |
| `docs/textbook/vol4-effects/` | Phase 4 | **planned** | Academic / Scholarly readers | `sarutahiko` Engine Infrastructure |
| `docs/textbook/vol5-cegis/` | Phase 4 | **planned** | Academic / Scholarly readers | `sarutahiko` CEGIS Campaigns |

---

## 5. Review & Git Push Synchronization Workflow

To ensure rapid human feedback and maintain zero-defect standards across all git mirrors:

1. **Local Authoring & Deterministic Gate:**
   - Draft document artifacts in small, cohesive batches.
   - Run `./bin/gargamelle-verify` to ensure zero compiler warnings, zero HLint hints, and 100% test pass.
   - Ensure all relative links resolve within the local tree.

2. **Commit Conventions & Attribution:**
   - Follow standard HEREDOC commit format with imperative subject.
   - Include RFC 2822 trailer: `Assisted-by: Antigravity (Google / gemini-3.8-pro)`.

3. **Synchronized Push to All 5 Mirrors:**
   - Push updated commits across `github`, `gitcode`, `framagit`, `disroot`, and `rad`:
     ```bash
     git push github master
     git push gitcode master
     git push framagit master
     git push disroot master
     rad sync
     ```

4. **Visual Web Inspection & Human Feedback:**
   - Human maintainer inspects the rendered Markdown on GitHub, GitCode, Disroot, and Framagit web interfaces.
   - Any typography, MathJax, or styling anomalies are flagged and addressed before advancing to the next batch.
