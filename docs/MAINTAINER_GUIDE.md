<!--
SPDX-License-Identifier: EUPL-1.2
-->
# Gargamelle Maintainer Guide & Architectural Governance

**Status:** LIVING DOCUMENT · v2.0 · 2026-10-20  
**Audience:** Maintainers, Subsystem Leads, Ecosystem Contributors, AI Assistant Drivers  
**Canonical Strategy:** [`docs/notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md) · [`docs/notes/GARGAMELLE_ARCHITECTURAL_REDESIGN.md`](notes/GARGAMELLE_ARCHITECTURAL_REDESIGN.md)  
**Corpus Inventory:** [`docs/INDEX.md`](INDEX.md) · **Package Register:** [`docs/registers/PACKAGES.md`](registers/PACKAGES.md)  
**Newbie Guide:** [`docs/NEWBIE_GUIDE.md`](NEWBIE_GUIDE.md) · **Tutorial:** [`docs/TUTORIAL.md`](TUTORIAL.md)  
**Build Systems Matrix:** [`docs/developer/BUILD_SYSTEMS_MATRIX.md`](developer/BUILD_SYSTEMS_MATRIX.md)  

---

## 1. Architectural Foundations & Invariants

### 1.1 The Precedence Rule (`DOC_STRATEGY.md` §4)
- **Code wins at runtime:** When a note disagrees with code, the code defines the runtime reality.
- **Notes are corrected regardless:** A stale note must be updated in the same change set. Technical debt in documentation is treated with equal severity to bugs in code.

### 1.2 The 100% Observability Doctrine
- **Zero Opaque Closures:** In `gargamelle-model`, `gargamelle-logic`, `gargamelle-core`, and `gargamelle-sheaf`, semantic morphisms and predicates must **never** be defined as opaque Haskell functions `(a -> b)`.
- **First-Order Reification:** All morphisms must be expressed as introspectable ASTs (`ObsMor`), and all verification conditions as Free `VerifierAST` trees. This guarantees that plans can be statically inspected, translated to SMT-LIB2 for Z3, and serialized into Beam SQLite tables.

### 1.3 Subsystem Separation & Package Tiers
- **Tier 2 (Logic & Effect):** `gargamelle-logic`, `gargamelle-effect`
- **Tier 3 (Model & Evidence):** `gargamelle-model`, `gargamelle-evidence`
- **Tier 4 (Macro-Logics & Execution):** `gargamelle-core`, `gargamelle-fol`, `gargamelle-equational`, `gargamelle-sandbox`, `gargamelle-persistence`
- **Tier 5 (Topological Orchestration):** `gargamelle-sheaf`, `gargamelle-workflow`
- **No Circular Imports:** Upper tiers may depend on lower tiers, never the reverse.

---

## 2. Verification Gates & Quality Control

Before any change is committed to master, it must pass four strict gates:

### Gate 1: The Deterministic Physical Verification Harness
```bash
./bin/gargamelle-verify
```
Checks:
1. Bubblewrap Linux namespace container sandbox isolation (`/usr/bin/bwrap`).
2. Beam SQLite on-disk database creation, schema migrations, and file locking.
3. Clean HLint static analysis run across all package sources (0 hints).
4. All test suite assertions passed with 0 failures.

### Gate 2: Full Multi-Package Test Suite
```bash
cabal test gargamelle-logic gargamelle-model gargamelle-core gargamelle-fol \
           gargamelle-equational gargamelle-sheaf gargamelle-effect gargamelle-workflow
```
All 79 examples across all 8 active test suites must pass cleanly without regressions.

### Gate 3: Zero Compiler Warnings under GHC 9.14 (`-Wall -Werror`)
Every package in `packages/` must build with zero warnings:
```bash
cabal build all --ghc-options="-Wall -Werror"
```

### Gate 4: Zero HLint Hints
```bash
hlint packages/gargamelle-*/src
```
Enforces zero hints across default HLint rules.

---

## 3. Commit Attribution & DCO Boundaries

All commits in this repository must follow the Linux kernel RFC 2822 trailer standard (see [`docs/notes/COMMIT_ATTRIBUTION.md`](notes/COMMIT_ATTRIBUTION.md)):

```
<type>(<scope>): <short imperative subject>

<detailed body explaining why the change was made>

Assisted-by: Antigravity (Google / gemini-3.8-pro)
```

- **Allowed Trailers for AI Tools:** `Assisted-by:` and optional `Orchestrated-by:`.
- **Forbidden Trailers for AI Tools:** `Co-authored-by:` and `Signed-off-by:`. Only human maintainers may certify the Developer Certificate of Origin (DCO).
- Enforced automatically by `.githooks/commit-msg`.
