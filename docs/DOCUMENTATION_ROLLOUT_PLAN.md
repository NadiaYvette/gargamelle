<!--
SPDX-License-Identifier: EUPL-1.2
-->
# Staged Documentation Roll-Out Plan

**Status:** PLAN · v1.2 · 2026-10-21  
**Authors:** Nadia Yvette Chambers & Antigravity (Google / gemini-3.8-pro)  
**Parent Strategy:** [`notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md)  
**Reference Specification:** [`FRAMEWORK_RECOMMENDATIONS.md`](FRAMEWORK_RECOMMENDATIONS.md)  
**Detailed Proposal:** [`notes/EXPOSITORY_AND_TUTORIAL_FRAMEWORK.md`](notes/EXPOSITORY_AND_TUTORIAL_FRAMEWORK.md)  
**Corpus Inventory:** [`INDEX.md`](INDEX.md)  

---

## 1. Executive Summary & Roll-Out Philosophy

This document defines the **Staged Documentation Roll-Out Plan** for the Gargamelle suite.

If *"roll-out"* sounds incongruously informal in an enterprise or scholarly setting, *"implementation"* sounds ontologically odder when applied to prose, pedagogical monographs, and mathematical treatises. Documentation is not simply an implementation artifact; it is an epistemic interface connecting mathematical theory, systems engineering, human developers, and autonomous agents.

### The Sequencing Strategy: Easiest First, Progressive Depth, Treatise Grounded in Consumers

The core thesis of this roll-out plan is **progressive disclosure, immediate forge verifiability, and mechanical cross-reference integrity**:

```
┌────────────────────────────────────────────────────────────────────────┐
│ PHASE 1: Immediate Forge Surfaces & Reading Paths (Lowest Effort)      │
│   • Polish Root README.md for multi-forge rendering                    │
│   • Align NEWBIE_GUIDE, TUTORIAL, MAINTAINER_GUIDE, and INDEX.md       │
│   • Immediate visual feedback on GitHub, GitCode, Disroot, Framagit    │
├────────────────────────────────────────────────────────────────────────┤
│ PHASE 2: Standardized Package Monographs & In-Code Architecture        │
│   • Per-package landing monographs ordered by architectural tier       │
│   • Uniform 6-part anatomical template in packages/gargamelle-*/README │
│   • GHC Notes architecture with mechanical tagref validation           │
│   • High comment density target (50%+) via cloc across packages/*/src  │
│   • Haddock standards: Unicode math, law citations, worked examples    │
│   • Tripartite dual-linking: Source Code ↔ Hackage/Haddock ↔ mdBook    │
├────────────────────────────────────────────────────────────────────────┤
│ PHASE 3: Programmatic Verification Harness & Multi-GHC Tooling         │
│   • Multi-GHC literate doc-testing (GHC 9.6–9.14 via docspec/unlit)   │
│   • Mechanical tagref zero-dangling-reference verification             │
│   • Deterministic intra-corpus Markdown relative link & anchor check   │
│   • Hyperlinked Haddock cross-reference verification across 11 packages│
│   • cloc comment density tracking in physical verification harness     │
│   • mdBook scaffold with MathJax, Mermaid, and dual-link support       │
├────────────────────────────────────────────────────────────────────────┤
│ PHASE 4: The 5-Volume Foundational Treatise (Package Clusters)         │
│   • Comprehensive exposition of Gargamelle package clusters & theory   │
│   • Co-developed with sarutahiko as the primary reference consumer     │
│   • Designed for modular extensibility by third-party consumers        │
│   • Bidirectional interlinking: in-code GHC Notes ↔ mdBook chapters    │
└────────────────────────────────────────────────────────────────────────┘
```

1. **Easiest Parts First (Phases 1 & 2):**  
   We begin by establishing clean, high-visibility markdown documents at the repository root and within each of the 11 package directories. Pushing these immediately to our five public git hosting mirrors (`github`, `gitcode`, `disroot`, `framagit`, and `rad`) allows us to visually inspect formatting, typography, MathJax formulas, Mermaid diagrams, tables, and link resolutions across distinct web frontends without waiting for hundreds of pages of textbook prose.

2. **Per-Package Forge Landing & In-Code Architecture (Phase 2):**  
   Each package directory in `packages/gargamelle-*/` receives an authoritative landing `README.md` ordered by architectural tier (Substrates $\to$ Logics $\to$ Sheaves/Workflow). In tandem with these monographs, we establish deep in-code GHC Notes (`{- Note [...] ~~~~ [tag:<slug>] -}`), `tagref` cross-referencing, and a **50%+ comment density target** (measured via `cloc packages/`).

3. **Multi-GHC Verification & Dual Link Integrity (Phase 3):**  
   Literate code snippets in documentation and package monographs are validated across our complete compiler matrix (GHC 9.6, 9.8, 9.10, 9.12, and 9.14). Cross-references are protected by a two-layer net: mechanical `tagref` validation for code/monograph tags, and deterministic link checks for Markdown paths. Hyperlinked Haddock cross-references are mechanically verified.

4. **Treatise Grounded in Package Clusters and Consumer Perspectives (Phase 4):**  
   The 5-volume foundational textbook in `docs/textbook/` is organized directly around Gargamelle's package clusters and theoretical pillars. It is developed concurrently with real consumer integrations—principally [`sarutahiko`](~/src/sarutahiko)—which provides concrete, empirical case studies of an autonomous coding orchestrator invoking Gargamelle, while preserving uncoupled generality for other current and future consumers.

---

## 2. Multi-Forge Rendering Targets & Visual Inspection Criteria

Gargamelle mirrors across five distinct git hosting environments, each with its own markdown dialect, CSS stylesheet, MathJax/KaTeX parser, and sanitization rules. Every document released in Phases 1 and 2 must be verified against the following matrix:

| Forge Remote | URL / Identifier | Markdown Engine | Math Support | Diagram Support | Key Verification Checks |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`github`** | [`github.com/NadiaYvette/gargamelle`](https://github.com/NadiaYvette/gargamelle) | GitHub Flavored Markdown (GFM) | Native MathJax (`$...$`, `$$...$$`) | Native Mermaid (` ```mermaid `) | GFM Alerts (`> [!NOTE]`), MathJax rendering, table alignment, anchor link jumps. |
| **`gitcode`** | [`gitcode.com/NadiaYvette/gargamelle`](https://gitcode.com/NadiaYvette/gargamelle) | GitCode GFM Dialect | KaTeX / MathJax | Mermaid codeblocks | UTF-8 mathematical symbols ($\amalg, \times, \delta^0, \models$), table column wrapping. |
| **`disroot`** | [`git.disroot.org/NadiaYvette/gargamelle`](https://git.disroot.org/NadiaYvette/gargamelle) | Forgejo Markdown Engine | KaTeX syntax | Mermaid codeblocks | Monospace code styling, relative hyperlink paths to `docs/` and `packages/`. |
| **`framagit`** | [`framagit.org/NadiaYvette/gargamelle`](https://framagit.org/NadiaYvette/gargamelle) | GitLab Flavored Markdown (GLFM) | GLFM Math (`$` or `math` block) | GitLab Mermaid parser | Table borders, codeblock copy buttons, cross-repository references. |
| **`rad`** | `rad://zqykaqjnoA8a1harMdQVsigC7VwH` | Radicle Heartwood / Web Gateway | Pure ASCII / UTF-8 Markdown | Plain text fallback | Pure terminal markdown (`rad show`), plus HTTP seed node web explorers (see below). |

### Remark on Viewing Radicle in a Web Browser
While Radicle is fundamentally a peer-to-peer git gossip protocol over Heartwood (navigated locally via terminal commands such as `rad show`, `rad patch`, and `git-remote-rad`), repositories pushed to Radicle seed nodes **can be viewed in a web browser** via public or private seed web gateways:
1. **Public Seed Node Web Explorers:** Public seed nodes provide HTTP web gateways that render the repository tree, commit history, and Markdown files in a browser:
   - Web URL for Gargamelle: [`https://radicle.network/nodes/iris.radicle.network/rad:zqykaqjnoA8a1harMdQVsigC7VwH`](https://radicle.network/nodes/iris.radicle.network/rad:zqykaqjnoA8a1harMdQVsigC7VwH)
   - Alternative seed web gateway: `https://app.radicle.xyz/nodes/<seed-domain>/rad:zqykaqjnoA8a1harMdQVsigC7VwH`
2. **Local Browser Viewing via `radicle-httpd`:** Developers can launch a local Radicle HTTP gateway daemon (`radicle-httpd` or `rad-web`) on `http://127.0.0.1:8080` to browse local Radicle repositories in any desktop browser completely offline.

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
  - **Forge Verification:** Confirmed rendering of ASCII diagrams, math notation, and package table across GitHub, GitCode, Disroot, Framagit, and Radicle.

- [x] **Milestone 1.2: Core Orientation Guides Polish**
  - **Artifacts:**
    - [`docs/INDEX.md`](INDEX.md) (Corpus inventory and curated reading paths)
    - [`docs/NEWBIE_GUIDE.md`](NEWBIE_GUIDE.md) (Progressive disclosure funnel & token conservation)
    - [`docs/TUTORIAL.md`](TUTORIAL.md) (5-lesson interactive walkthrough from ObsMor to Crem CEGIS)
    - [`docs/MAINTAINER_GUIDE.md`](MAINTAINER_GUIDE.md) (Governance, 6 physical verification gates, commit attribution, multi-mirror protocol)
  - **Forge Verification:** All intra-corpus relative links verified; tables and metadata updated to `2026-10-21` following `DOC_STRATEGY.md` status metadata conventions.

- [x] **Milestone 1.3: Multi-Compiler & Matrix Documentation**
  - **Artifact:** [`docs/developer/BUILD_SYSTEMS_MATRIX.md`](developer/BUILD_SYSTEMS_MATRIX.md)
  - **Action:** Verified copy-pasteable build commands for Cabal, Stack, and Nix across GHC 9.6, 9.8, 9.10, 9.12, and 9.14; updated verification gates section.

---

### Phase 2: Standardized Package Monographs & In-Code Architecture (11 Packages)

**Goal:** Provide an immediate landing document (`README.md`) inside each package directory under `packages/gargamelle-*`, accompanied by deep in-code GHC Notes, `tagref` cross-referencing, an elevated comment density target, and tripartite dual-linking.

#### 1. Per-Package Forge Landing Ordered by Architectural Tier
When a developer or researcher clicks into any package directory on GitHub, GitCode, Disroot, Framagit, or Radicle web, they must immediately see a clean, comprehensive package monograph rendered by the forge's markdown engine. Authorship is sequenced by architectural tier to build conceptual dependencies monotonically:

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

#### 2. Uniform 6-Part Anatomical Monograph Template
Every package in `packages/gargamelle-*` contains a standardized `README.md` adhering to the template from [`FRAMEWORK_RECOMMENDATIONS.md`](FRAMEWORK_RECOMMENDATIONS.md) §4:
1. **Executive Summary & Problem Framing:** Mathematical/systems problem addressed, domain necessity.
2. **Mathematical Foundations & Theoretical Invariants:** Categorical diagrams, sheaf restrictions, lattice orders, formal laws.
3. **Module Architecture & Repertoire Breadth:** Exported modules, primary typeclasses, key data types.
4. **Executable Worked Examples:** Compilable literate Haskell code snippets with explicit imports.
5. **Integration Points & Subsystem Boundaries:** Tier DAG position, upstream dependencies, downstream consumers.
6. **Diagnostic & Troubleshooting Guide:** Type mismatch patterns, SMT timeouts, boundary failures, fix recipes.

#### 3. In-Code GHC Notes Architecture (`tagref`-Validated)
Adopt the battle-tested GHC Notes pattern formalized in `polytropos`:
- Major architectural decisions, categorical proofs, and memory physics are preserved in top-level non-Haddock block comments:
  ```haskell
  {- Note [Knaster-Tarski Harmonic Consensus Diffusion]
  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  [tag:<note-harmonic-consensus>]
  Iterating cellular diffusion over the Store comonad evaluates local meet
  semi-lattice operations...
  -}
  ```
- Any function, data constructor, or test asserting this invariant includes a directional tagref pointer:
  ```haskell
  -- See Note [Knaster-Tarski Harmonic Consensus Diffusion] [ref:<note-harmonic-consensus>]
  ```
- **Tripartite Interlinking Mesh:** Notes defined in code can be referenced directly within package monographs and `docs/textbook/` chapters via `[ref:<note-slug>]`, and code comments cite specific treatise chapters.

#### 4. Dual Reference Linking: Source Code ↔ Hackage/Haddock ↔ mdBook
To provide seamless navigation without UI clutter, documentation and textbook chapters adopt a side-by-side **dual-link convention**:
- **Dual Links (Source + Hackage):** For exposed types, primary typeclasses, and exported combinators, provide both a link to the exact source definition in the repository and a side-by-side link to published Hackage/Haddock documentation:
  - Example: ``[`ObsMor`](packages/gargamelle-model/src/Gargamelle/Model/ObsMor.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-model/docs/Gargamelle-Model-ObsMor.html#t:ObsMor))``
  - Format: ``[`<Identifier>`](<relative-source-path>) ([Hackage](<hackage-url>))``
- **Single Link (Source Only):** For unexposed internal algorithms, private helpers, transient hardware layouts, and implementation details not exported to Hackage, link directly to the source file line.
- **Single Link (Hackage / External Only):** For external dependencies or base types, link directly to Hackage or external papers.
- **In-Haddock Back-References:** In Haddock module headers and typeclass documentation, include direct back-references to the treatise:
  - Example: `-- * Theoretical Foundations: See Treatise Vol. II, Ch. 2 (Observability).`

#### 5. Comment Density Target (50%+) via `cloc`
- The sheer density of higher categories, proarrow equipments, algebraic sheaves, and container isolation requires deep explanatory prose to prevent code from becoming opaque.
- We establish an explicit guideline of **50%+ comment density** across `packages/*/src/` (measured via `cloc packages/`).
- Comment density expands organically through:
  - Theoretical GHC Notes and rationale blocks.
  - Formal typeclass law statements (e.g. Galois connection bounds, functoriality of sentences, coboundary linearity).
  - Module header roadmaps and ASCII commutative diagrams.
  - Dual reference links connecting code back to the `mdBook`.

#### 6. Polytropos Haddock Conventions
- Full explanatory paragraphs with zero filler: invariants, failure conditions, time/space complexity, worked snippets.
- Inline Unicode math ($\amalg, \times, \delta^0, \models, \ker, \operatorname{coker}, \trianglelefteq$).
- Module introductions required for all exposed modules.
- Haddock flags: `--hyperlinked-source --quickjump` enabled everywhere.

#### Delivery Milestones for Phase 2

- [x] **Milestone 2.1: Batch 2A Monographs & In-Code Architecture (Substrates & Semantics)**
  - `packages/gargamelle-logic/README.md`: Order-theoretic contracts (`Algebra.Lattice.Op`), contravariant Galois connections, and syntax ASTs. Initial GHC Notes for lattice inversions.
  - `packages/gargamelle-effect/README.md`: Kernmantle Arrow Rope pipelines, $O(1)$ variant jump-table routing, profunctor optics, and Coyoneda fusion. GHC Notes for jump-table routing physics.
  - `packages/gargamelle-model/README.md`: 100% observable morphisms (`ObsMor`), Free `VerifierAST`, `Divisible`/`Decidable` trees, and inspection. GHC Notes for closure elimination.
  - `packages/gargamelle-evidence/README.md`: Concrete syntax trees via `hs-tree-sitter`, semantic diffing via `tree-diff`, and similarity metrics.

- [x] **Milestone 2.2: Batch 2B Monographs & In-Code Architecture (Logics & Host Infrastructure)**
  - `packages/gargamelle-core/README.md`: Goguen-Burstall Institutions, pushout feature weaving ($B \amalg_C W$), pullback protocol discovery ($A \times_E B$), and colimits. GHC Notes for satisfaction invariance, pushout weaving, pullback discovery, and colimit semantic deltas.
  - `packages/gargamelle-fol/README.md`: First-order logic, hyperdoctrines, refinement calculi, and streaming Z3 SMT-LIB2 pipe. GHC Notes for SMT piping and hyperdoctrine quantifier adjunctions.
  - `packages/gargamelle-equational/README.md`: Equational logic institution and presheaf Double-Pushout (DPO) algebraic rewriting. GHC Notes for DPO gluing conditions.
  - `packages/gargamelle-sandbox/README.md`: Linux container namespace isolation via Bubblewrap (`/usr/bin/bwrap`), resource limits, and filesystem scoping. GHC Notes for namespace isolation boundaries. Dedicated test suite added.
  - `packages/gargamelle-persistence/README.md`: Beam SQLite persistence (`EvidenceRecordT`, `CounterexampleRecordT`, `RunRecordT`), transactional locking, and indexing. Dedicated test suite added.

- [ ] **Milestone 2.3: Batch 2C Monographs & In-Code Architecture (Topology & Autonomous Workflow)**
  - `packages/gargamelle-sheaf/README.md`: 1D Cell complexes, cellular sheaves, Store comonad cellular diffusion, Knaster-Tarski consensus, and $H^1$ homological fault localization. GHC Notes for sheaf coboundary $\delta^0$ and $H^1$ localization.
  - `packages/gargamelle-workflow/README.md`: Crem Mealy state machines (`singletons-base`), sheaf-gated CEGIS loop (`runSheafGatedCEGIS`), and automated repair guidance. GHC Notes for Mealy state machine transitions.

---

### Phase 3: Programmatic Verification Harness & Multi-GHC Tooling Automation

**Goal:** Mechanically eliminate documentation drift, link rot, and cross-reference breakage by integrating automated verification suites into CI and `./bin/gargamelle-verify`.

- [ ] **Milestone 3.1: Multi-GHC Literate Markdown Verification (`cabal-docspec` / `markdown-unlit`)**
  - Configure `./bin/gargamelle-doccheck` to extract and typecheck all Haskell code blocks in package READMEs, tutorials, and textbook chapters.
  - Enforce compatibility across the entire supported GHC matrix (GHC 9.6, 9.8, 9.10, 9.12, 9.14) under `-Wall -Werror`, ensuring code examples do not rely on version-brittle language features.
  - Enforces `DOC_STRATEGY.md` §4: *Code wins at runtime; notes corrected regardless.* Stale documentation fails the build.

- [ ] **Milestone 3.2: Mechanical `tagref` Integrity Check**
  - Integrate `tagref` into `./bin/gargamelle-verify` and CI.
  - Validate that all `[tag:<slug>]` definitions and `[ref:<slug>]` references across Haskell code, package monographs, and textbook chapters resolve with **0 dangling references** and **0 duplicate tags**.

- [ ] **Milestone 3.3: Deterministic Intra-Corpus Markdown Link & Anchor Verification**
  - Implement an automated check validating that every relative markdown hyperlink (`[text](path.md#anchor)`) resolves to a physical file and exact header anchor in the repository.
  - Protects against file renames, moved sections, and dead cross-references across `docs/` and `packages/`.

- [ ] **Milestone 3.4: Automated Hyperlinked Haddock Cross-Reference Verification**
  - Maintain `./bin/gargamelle-haddock` generating hyperlinked source Haddock trees (`--hyperlinked-source --quickjump`) cross-linking all 11 packages.
  - Mechanically verify that cross-package Haddock references resolve without warnings or dangling symbols.

- [ ] **Milestone 3.5: `cloc` Comment Density Audit**
  - Automated check in `./bin/gargamelle-verify` evaluating comment density via `cloc packages/`.
  - Track progress toward and maintain the **50%+ comment density target** across all 11 packages.

- [ ] **Milestone 3.6: `mdBook` Local Site Scaffold & Dual-Link Integration**
  - Initialize `docs/textbook/book.toml` with `mdbook-mermaid` and MathJax support for offline reading and local HTML book rendering.
  - Support the dual-link convention linking textbook terms to both source definitions and Hackage documentation.

---

### Phase 4: The 5-Volume Foundational Treatise (Package Clusters & Consumer Perspectives)

**Goal:** Author the comprehensive 24-chapter textbook curriculum (`docs/textbook/`) providing the rigorous mathematical, philosophical, and architectural background required to understand and extend Gargamelle.

#### Why Co-Development with `sarutahiko` Is Mandatory
Writing textbook-level exposition on higher categories, cellular sheaves, and autonomous CEGIS requires grounded, real-world case studies rather than toy examples. [`sarutahiko`](~/src/sarutahiko) serves as the primary real-world consumer of `gargamelle`, utilizing its institutions, verifiers, and sandboxed execution to synthesize patches for production systems. 

Authoring the textbook concurrently with `sarutahiko` ensures that:
- Every theorem has an empirical benchmark in `sarutahiko`.
- Every SMT example reflects real automated bug-repair queries.
- Every sheaf coboundary diagram reflects real multi-service architectural boundaries.
- Every pipeline optimization reflects real high-throughput execution bottlenecks.
- The prose remains vital, concrete, and battle-tested.

#### Architecture: Gargamelle Package Clusters + Consumer Perspectives
The 5 volumes correspond directly to functional clusters of Gargamelle packages and their governing mathematical disciplines. Each volume thoroughly develops its subsystem in its own right, while presenting [`sarutahiko`](~/src/sarutahiko) as the **primary reference consumer and motivating exemplar**—demonstrating how an autonomous programming orchestrator concretely instantiates these modules—while maintaining clean modular uncoupling so that **other current and future consumers** (e.g. theorem provers, compiler frontends, distributed contract engines, multi-agent systems) find clear integration boundaries.

```
┌────────────────────────────────────────────────────────────────────────┐
│ VOLUME I: Abstract Model Theory & Categorical Institutions             │
│   • Component: gargamelle-core                                         │
│   • Consumer View: sarutahiko's multi-language syntax & aspect weaving │
│   • General Consumers: Heterogeneous verification engines, translators │
│   • Chapters: Heterogeneous Logics, Signatures/Sentences/Models,       │
│               Satisfaction Invariance, Comorphisms, Pushout Weaving    │
├────────────────────────────────────────────────────────────────────────┤
│ VOLUME II: Reified Observability & Proof Synthesis                     │
│   • Components: gargamelle-model, gargamelle-logic, gargamelle-fol     │
│   • Consumer View: sarutahiko's verifier synthesis & Z3 SMT pipes      │
│   • General Consumers: Symbolic verifiers, SMT translation pipelines   │
│   • Chapters: Tyranny of Closures, ObsMor Category, Free VerifierAST,  │
│               Dual AG Contracts (Op Lattice), Host Z3 SMT Pipe         │
├────────────────────────────────────────────────────────────────────────┤
│ VOLUME III: Applied Algebraic Topology & Cellular Sheaves              │
│   • Component: gargamelle-sheaf                                        │
│   • Consumer View: sarutahiko's multi-module architectures & boundaries│
│   • General Consumers: Distributed consensus, network fault analyzers │
│   • Chapters: Cell Complexes, Sheaves & Stalks, Store Comonad,         │
│               Knaster-Tarski Diffusion, Coboundary δ⁰ & H¹ Obstructions│
├────────────────────────────────────────────────────────────────────────┤
│ VOLUME IV: Effectful Pipeline Architecture & Substrate Invariants      │
│   • Components: gargamelle-effect, polytropos, kernmantle              │
│   • Consumer View: sarutahiko's high-throughput orchestration engine   │
│   • General Consumers: High-performance data pipelines, extensible ADTs│
│   • Chapters: Kernmantle Arrow Rope, Polytropos Flat Rep, O(1) Router, │
│               Profunctor Optics, Coyoneda Pipeline Fusion              │
├────────────────────────────────────────────────────────────────────────┤
│ VOLUME V: Grounded Verification & Autonomous CEGIS                     │
│   • Components: gargamelle-sandbox, gargamelle-persistence, workflow   │
│   • Consumer View: sarutahiko's autonomous patch synthesis campaigns   │
│   • General Consumers: Automated repair bots, sandboxed code executors │
│   • Chapters: Bubblewrap Sandboxing, Beam SQLite Evidence Persistence, │
│               Crem Mealy Automata, The End-to-End Sheaf CEGIS Loop     │
└────────────────────────────────────────────────────────────────────────┘
```

#### Curriculum Delivery Schedule

- [ ] **Milestone 4.1: Volume I — Foundations of Abstract Model Theory & Categorical Institutions**  
  *Path: `docs/textbook/vol1-institutions/`*  
  *Core Package:* `gargamelle-core`.  
  *Exemplar Perspective:* How `sarutahiko` weaves cross-language module contracts.  
  *General Consumers:* Multi-language verification testbeds, AST translators.  
  *Content:* Explains why hard-coded syntax fails, formalizes the Goguen-Burstall satisfaction condition, and proves pushout feature amalgamation ($B \amalg_C W$) and colimit delta factorization.

- [ ] **Milestone 4.2: Volume II — Reified Observability & Proof Synthesis**  
  *Path: `docs/textbook/vol2-observability/`*  
  *Core Packages:* `gargamelle-model`, `gargamelle-logic`, `gargamelle-fol`.  
  *Exemplar Perspective:* How `sarutahiko` synthesizes verifiable specifications and queries host Z3.  
  *General Consumers:* SMT translation pipelines, contract synthesizers.  
  *Content:* Eliminates black-box functions, constructs `ObsMor` and `VerifierAST`, develops dual assume-guarantee contracts via `Algebra.Lattice.Op`, and streams typed SMT-LIB2 over Linux pipes.

- [ ] **Milestone 4.3: Volume III — Applied Algebraic Topology & Cellular Sheaves**  
  *Path: `docs/textbook/vol3-sheaves/`*  
  *Core Package:* `gargamelle-sheaf`.  
  *Exemplar Perspective:* How `sarutahiko` analyzes cross-module architectural boundaries and localizes faults.  
  *General Consumers:* Distributed consensus networks, topology-aware fault analyzers.  
  *Content:* Introduces 1D cell complexes, restriction maps, the Store comonad on graph complexes, Knaster-Tarski diffusion, and $H^1$ homological obstruction localization (`locateObstructions`).

- [ ] **Milestone 4.4: Volume IV — Effectful Pipeline Architecture & Substrate Invariants**  
  *Path: `docs/textbook/vol4-effects/`*  
  *Core Packages:* `gargamelle-effect`, with `polytropos` and `kernmantle`.  
  *Exemplar Perspective:* How `sarutahiko` executes high-throughput effectful Arrow Rope pipelines.  
  *General Consumers:* Extensible ADT engines, zero-copy pipeline orchestrators.  
  *Content:* Demonstrates Kernmantle arrow composition, Polytropos flat `Rep` memory layouts, $O(1)$ variant jump-table routing, copy-on-write profunctor optics, and Coyoneda pipeline fusion.

- [ ] **Milestone 4.5: Volume V — Grounded Verification & Autonomous CEGIS**  
  *Path: `docs/textbook/vol5-cegis/`*  
  *Core Packages:* `gargamelle-sandbox`, `gargamelle-persistence`, `gargamelle-workflow`.  
  *Exemplar Perspective:* How `sarutahiko` runs full autonomous repair campaigns.  
  *General Consumers:* Automated repair bots, sandboxed code executors.  
  *Content:* Covers Linux container isolation via Bubblewrap, Beam SQLite run tracking, verified Mealy state machines, and the complete sheaf-gated CEGIS synthesis loop (`runSheafGatedCEGIS`).

---

## 4. Documentation Roll-Out Ledger & Status Matrix

This living register tracks the status of every planned documentation artifact across all roll-out phases:

| Artifact Path | Phase | Status | Primary Mirror Focus | Subsystem / Consumer Anchor |
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
| In-Code GHC Notes (`tagref`-validated) | Phase 2 | **draft** | Codebase navigation & IDEs | In-code invariants across all 11 packages |
| Dual Reference Linking (Source + Hackage)| Phase 2 | **draft** | Monographs & Treatise | Tripartite epistemic navigation |
| Comment Density Target (50%+) | Phase 2 | **draft** | `cloc packages/` audit | Mathematical & architectural explanatory depth |
| `./bin/gargamelle-doccheck` | Phase 3 | **planned** | Deterministic CI Gate | Multi-GHC literate code verification (9.6–9.14) |
| Mechanical `tagref` Verification | Phase 3 | **implemented**| Deterministic CI Gate | Zero dangling references / duplicate tags |
| Deterministic Markdown Link Check | Phase 3 | **planned** | Deterministic CI Gate | Zero broken intra-corpus markdown hyperlinks |
| Hyperlinked Haddock Verification | Phase 3 | **planned** | Deterministic CI Gate | Cross-package Haddock symbol resolution |
| `cloc` Density Audit Gate | Phase 3 | **implemented**| `./bin/gargamelle-verify` | Comment density tracking (target 50%+) |
| `docs/textbook/book.toml` | Phase 3 | **planned** | mdBook offline site | Local HTML rendering |
| `docs/textbook/vol1-institutions/` | Phase 4 | **planned** | Academic / Scholarly readers | `gargamelle-core` / `sarutahiko` Interface Synthesis |
| `docs/textbook/vol2-observability/` | Phase 4 | **planned** | Academic / Scholarly readers | `model`+`fol` / `sarutahiko` Verifier Synthesis |
| `docs/textbook/vol3-sheaves/` | Phase 4 | **planned** | Academic / Scholarly readers | `gargamelle-sheaf` / `sarutahiko` Arch Synthesis |
| `docs/textbook/vol4-effects/` | Phase 4 | **planned** | Academic / Scholarly readers | `effect`+`polytropos` / `sarutahiko` Engine Infrastructure |
| `docs/textbook/vol5-cegis/` | Phase 4 | **planned** | Academic / Scholarly readers | `workflow`+`sandbox` / `sarutahiko` CEGIS Campaigns |

---

## 5. Review & Git Push Synchronization Workflow

To ensure rapid human feedback and maintain zero-defect standards across all git mirrors:

1. **Local Authoring & Deterministic Gates:**
   - Draft document artifacts in small, cohesive batches.
   - Run `./bin/gargamelle-verify` to ensure zero compiler warnings, zero HLint hints, and 100% test pass across all 6 gates.
   - Run `tagref` to ensure no broken cross-references.
   - Monitor comment density via `cloc packages/`.
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
     git push rad master && rad sync
     ```

4. **Visual Web Inspection & Human Feedback:**
   - Human maintainer inspects the rendered Markdown on GitHub, GitCode, Disroot, Framagit, and Radicle web explorer interfaces.
   - Any typography, MathJax, or styling anomalies are flagged and addressed before advancing to the next batch.
