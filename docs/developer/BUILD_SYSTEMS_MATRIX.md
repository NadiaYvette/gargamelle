<!--
SPDX-License-Identifier: EUPL-1.2
-->
# Build Systems Matrix: Cabal, Stack & Nix

**Status:** LIVING DEVELOPER GUIDE · Operational Tooling Specification  
**Canonicity:** Secondary to Cabal / GHC runtime reality (`DOC_STRATEGY.md` §4)  
**Applicability:** All 11 `gargamelle-*` packages and ecosystem integrations  

---

## 1. Overview

`gargamelle` supports reproducible compilation and test execution across three major Haskell build systems:
1. **Cabal (`cabal-install >= 3.10`):** The primary multi-package build driver and reference solver.
2. **Stack (`stack >= 2.13`):** Curated Stackage LTS snapshots and custom compiler overlays.
3. **Nix (`nix >= 2.18`, Flakes & Classic):** Hermetic, sandboxed package sets and reproducible developer shells.

All three build systems are deterministically verified across the entire compiler target matrix:
- **GHC 9.6.7:** LTS Baseline (`base-4.18.3.0`, `resolver: lts-22.44`)
- **GHC 9.8.4:** Hackage Baseline (`base-4.19.2.0`, `resolver: lts-23.12`)
- **GHC 9.10.3:** `ghc-internal` Split Baseline (`base-4.20.1.0`)
- **GHC 9.12.4:** Constructor Details & `FieldOcc` AST Baseline (`base-4.21.2.0`)
- **GHC 9.14.1:** Primary Development Toolchain (`base-4.22.0.0`)

---

## 2. Quick Command Reference

### A. Cabal

Cabal relies on multi-compiler project overlays in the root directory:

| Compiler Target | Build Command | Test Command |
| :--- | :--- | :--- |
| **GHC 9.14.1 (Default)** | `cabal build all` | `cabal test gargamelle-workflow:test:tests` |
| **GHC 9.12.4** | `cabal --project-file=cabal.project.ghc-9.12 build all` | `cabal --project-file=cabal.project.ghc-9.12 test gargamelle-workflow` |
| **GHC 9.10.3** | `cabal --project-file=cabal.project.ghc-9.10 build all` | `cabal --project-file=cabal.project.ghc-9.10 test gargamelle-workflow` |
| **GHC 9.8.4** | `cabal --project-file=cabal.project.ghc-9.8 build all` | `cabal --project-file=cabal.project.ghc-9.8 test gargamelle-workflow` |
| **GHC 9.6.7** | `cabal --project-file=cabal.project.ghc-9.6 build all` | `cabal --project-file=cabal.project.ghc-9.6 test gargamelle-workflow` |

### B. Stack

Stack relies on dedicated `stack-ghc-*.yaml` project files:

| Compiler Target | Resolver / Strategy | Test Command |
| :--- | :--- | :--- |
| **GHC 9.14.1 (Default)** | `stack.yaml` (`ghc-9.14.1` + extra-deps) | `stack test` |
| **GHC 9.12.4** | `stack-ghc-9.12.yaml` (`ghc-9.12.4` + extra-deps) | `stack test --stack-yaml stack-ghc-9.12.yaml` |
| **GHC 9.10.3** | `stack-ghc-9.10.yaml` (`ghc-9.10.3` + extra-deps) | `stack test --stack-yaml stack-ghc-9.10.yaml` |
| **GHC 9.8.4** | `stack-ghc-9.8.yaml` (`lts-23.12`) | `stack test --stack-yaml stack-ghc-9.8.yaml` |
| **GHC 9.6.7** | `stack-ghc-9.6.yaml` (`lts-22.44`) | `stack test --stack-yaml stack-ghc-9.6.yaml` |

### C. Nix (Flakes & Classic)

Nix provides native package outputs for supported Nixpkgs compilers and reproducible developer shells:

| Target / Workflow | Flake Command | Classic / Flake-less Command |
| :--- | :--- | :--- |
| **Build Workflow (GHC 9.10)** | `nix build .#ghc910-workflow` | `nix-build default.nix -A gargamelle-workflow --argstr compiler ghc910` |
| **Build Core (GHC 9.10)** | `nix build .#ghc910-core` | `nix-build default.nix -A gargamelle-core --argstr compiler ghc910` |
| **Build Sheaf (GHC 9.10)** | `nix build .#ghc910-sheaf` | `nix-build default.nix -A gargamelle-sheaf --argstr compiler ghc910` |
| **Dev Shell (GHC 9.10)** | `nix develop .#ghc910` | `nix-shell shell.nix --argstr compiler ghc910` |
| **Dev Shell (GHC 9.6)** | `nix develop .#ghc96` | `nix-shell shell.nix --argstr compiler ghc96` |
| **Default Shell (9.10)** | `nix develop` | `nix-shell` |

---

## 3. Host Dependencies & Architectural Invariants

### A. Subsystem Dependencies
Gargamelle integrates physical runtime capabilities that require host binary availability:
1. **Bubblewrap (`/usr/bin/bwrap`):** Enforces physical Linux namespace sandboxing (PID, IPC, network, UTS, mount) and resource limits (`limitTimeoutSeconds`) in `gargamelle-sandbox`.
2. **SMT Solver Z3 (`/usr/bin/z3`):** Drives automated theorem proving, satisfiability checks, and countermodel extraction in `gargamelle-fol`.
3. **SQLite3 Engine (`libsqlite3`):** Underpins persistent Beam ORM schemas for evidence, counterexamples, and run records in `gargamelle-persistence`.

### B. Inter-Workspace Package Topology
The project references peer repositories configured in `cabal.project`:
- `../hs-tree-sitter/hs-tree-sitter` (AST parsing)
- `../tree-diff` (AST structural diffing)
- `../crem` (verified Mealy state machine execution)
- `../beam/beam-*` (type-safe SQLite persistence)
- `../polytropos/packages/*` (flat `Rep` substrate, profunctor optics, TcPlugin)
- `../kernmantle/kernmantle` (Arrow `Rope` effect pipelines, variant jump routing)
- `../proarrow/proarrow*` (profunctor equipment, categorical institutions, DPO rewriting)

---

## 4. Verification Gates

All changes must pass the deterministic verification gates before release:

```bash
# 1. Deterministic Physical Verification Suite (6 Gates: Sandbox, Beam, HLint, Tests, Tagref, CLOC density)
./bin/gargamelle-verify

# 2. Multi-Package Full Test Matrix (79 total examples across all 8 active packages)
cabal test gargamelle-logic gargamelle-model gargamelle-core gargamelle-fol \
           gargamelle-equational gargamelle-sheaf gargamelle-effect gargamelle-workflow

# 3. Multi-Compiler Cabal Verification
cabal --project-file=cabal.project.ghc-9.10 test gargamelle-workflow
cabal --project-file=cabal.project.ghc-9.14 test gargamelle-workflow

# 4. HLint Static Analysis (0 hints enforced)
hlint packages/gargamelle-*/src
```
