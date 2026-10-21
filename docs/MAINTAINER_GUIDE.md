<!--
SPDX-License-Identifier: EUPL-1.2
-->
# Gargamelle Maintainer Guide & Architectural Governance

**Status:** LIVING DOCUMENT · v2.1 · 2026-10-21  
**Audience:** Maintainers, Subsystem Leads, Ecosystem Contributors, AI Assistant Drivers  
**Canonical Strategy:** [`docs/notes/DOC_STRATEGY.md`](notes/DOC_STRATEGY.md) · [`docs/notes/GARGAMELLE_ARCHITECTURAL_REDESIGN.md`](notes/GARGAMELLE_ARCHITECTURAL_REDESIGN.md)  
**Roll-Out Plan:** [`docs/DOCUMENTATION_ROLLOUT_PLAN.md`](DOCUMENTATION_ROLLOUT_PLAN.md) · **Framework Spec:** [`docs/FRAMEWORK_RECOMMENDATIONS.md`](FRAMEWORK_RECOMMENDATIONS.md)  
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

Before any change is committed to master, it must pass all seven physical verification gates:

### Gate 1: The Deterministic Physical Verification Harness (7 Gates)
```bash
./bin/gargamelle-verify
```
Checks executed in sequence:
1. **Bubblewrap Container Sandboxing:** Enforces physical namespace isolation (`/usr/bin/bwrap`) with `/usr/bin/timeout` and temp mount scoping.
2. **On-Disk Beam Persistence:** Validates real SQLite file locking, schema creation, and transaction integrity.
3. **HLint Static Analysis:** Zero hints enforced across `packages/gargamelle-*/src`.
4. **Full Test Suite Assertions:** All 59 unit, integration, and milestone assertions pass with 0 failures across 7 test suites.
5. **Literate Markdown Doccheck:** All 28 literate code blocks across monographs and tutorials compile under `-Wall -Werror`.
6. **Tagref Cross-Reference Gate:** Zero dangling references and zero duplicate tags across code, monographs, and docs.
7. **CLOC Comment Density Gate:** Tracks progress toward and maintains the **50%+ comment density target** across packages.

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

---

## 4. Multi-Mirror Git Hosting & Synchronization Protocol

All changes landing on `master` must be synchronized across all five git hosting mirrors under the account `NadiaYvette` (SourceHut excluded per anti-AI TOS):

| Remote Name | Platform | Remote Push Command | Web View / Explorer |
| :--- | :--- | :--- | :--- |
| **`github`** | GitHub | `git push github master` | [github.com/NadiaYvette/gargamelle](https://github.com/NadiaYvette/gargamelle) |
| **`gitcode`** | GitCode | `git push gitcode master` | [gitcode.com/NadiaYvette/gargamelle](https://gitcode.com/NadiaYvette/gargamelle) |
| **`framagit`** | GitLab | `git push framagit master` | [framagit.org/NadiaYvette/gargamelle](https://framagit.org/NadiaYvette/gargamelle) |
| **`disroot`** | Forgejo | `git push disroot master` | [git.disroot.org/NadiaYvette/gargamelle](https://git.disroot.org/NadiaYvette/gargamelle) |
| **`rad`** | Radicle | `git push rad master && rad sync` | [Radicle Web View](https://radicle.network/nodes/iris.radicle.network/rad:zqykaqjnoA8a1harMdQVsigC7VwH) |

### Synchronized Multi-Push One-Liner:
```bash
git push github master && git push gitcode master && git push framagit master && git push disroot master && git push rad master && rad sync
```

---

## 5. Documentation Roll-Out Governance

Follow the staged strategy defined in [`docs/DOCUMENTATION_ROLLOUT_PLAN.md`](DOCUMENTATION_ROLLOUT_PLAN.md):
- **Phase 1 (Immediate):** Polish root README, orientation guides, and multi-compiler matrices for multi-forge rendering.
- **Phase 2 (Monographs):** Author standardized 6-part `README.md` monographs for all 11 packages in `packages/gargamelle-*/`, paired with in-code GHC Notes, `tagref` labels, and the 50%+ comment density target.
- **Phase 3 (Verification Tooling):** Implement `./bin/gargamelle-doccheck` (multi-GHC literate testing across GHC 9.6–9.14), deterministic Markdown link checks, and hyperlinked Haddock cross-reference verification.
- **Phase 4 (Foundational Treatise):** Author the 5-volume textbook curriculum in `docs/textbook/` concurrently with real consumer libraries (particularly [`sarutahiko`](~/src/sarutahiko)).
