Auditing `TP-META-006` through `TP-META-012` against your completed `TP-001A`–`TP-003C` packets and the new `gongju` / `tengri` modules reveals **one major scheduling relief** and **four specific overlaps/friction points** we can resolve right now before `yamaarashi-exec` touches `smirk`.

---

### 1. Cross-Campaign Audit: Overlaps, Conflicts, and Gaps

#### The Good News: Waves `0B` through `2B` (`TP-META-006`–`TP-META-011`) Are Not Blocked by `TP-META-004` or `TP-META-005`

Checking the `depends_on` graph across all seven attached `smirk` / `t-digest` packets shows that **six of the seven waves can run immediately** without waiting for `TP-META-004` or `TP-META-005`:

* **`TP-META-006` (`dunning-t-digest`)** depends only on `TP-META-000` and `TP-META-001` (`TP-001A` and `TP-001B` are already complete).


* **`TP-META-007` through `TP-META-010**` depend only on `TP-META-000`, `TP-META-001`, `TP-META-006`, `TP-META-007`, and `TP-META-008`.


* **`TP-META-011` (`Marpa`, `DPO`, `Sheaf.Parallel`)** depends on `TP-META-003`, which is **already finished** (`TP-003A`, `TP-003B`, `TP-003C`).


* **Only `TP-META-012` (Wave `3-Synquid`)** actually requires `TP-META-004` (`RewriteMining`) and `TP-META-005` (`Yamaarashi.Synthesis.Synquid`).



#### Four Overlaps & Conflicts to Resolve Between `smirk`, `gargamelle`, `gongju`, and `tengri`

| Issue | Where It Occurs | The Conflict / Gap | Resolution |
| --- | --- | --- | --- |
| **1. `Evacuable` Naming & Role Collision** | `TP-007B` (`Smirk.Core.Evacuable`) vs. `Gongju.Evacuate` (`TP-TENGRI-001`)

 | `Gongju.Evacuate` defines parametric container evacuability (`[] <-> NonEmpty`, `Set <-> NESet`), while `TP-007B` uses `Smirk.Core.Evacuable` for monomorphic slice non-nullability (`NonEmptySlice s`, `isNullableAST`, `[reNE|...|]`). Importing both in `tengri-sulde` risks identifier collisions.

 | Keep parametric container evacuability in `Gongju.Evacuate`, and have `Smirk.Core.Evacuable` export `NonEmptySlice s`, `isNullableAST`, and `[reNE|...|]` plus a bridge instance `siftRegex :: Evacuable c s => Regex -> c s -> Maybe (c (NonEmptySlice s))`.

 |
| **2. `gargamelle` Module Names in `TP-META-011**` | `TP-011C` & `TP-011D` vs. `TP-003B` & `TP-003C`

 | `TP-META-011` references Wave-1 module names (`Proarrow.Tools.DPO`, `CellComplex`, `CellularSheaf`), whereas `TP-003B` and `TP-003C` added `Gargamelle.Sheaf.LatticeCohomology` (`LiquidCellularSheaf`) and `Gargamelle.Equational.AbductiveEGraph` (`DPORule`).

 | In `TP-META-011`, instruct the decomposer to wire `Smirk.Core.DPO` to *both* `Proarrow.Tools.DPO` and `Gargamelle.Equational.AbductiveEGraph` (so `TP-META-012`'s `RewriteMining` plugs in with zero refactoring).

 |
| **3. `regex-with-pcre` Operator Parity for `tengri**` | `evalhs` / `ghci.script` vs. `Smirk.QuasiQuoter`[cite: 48, 50]

 | Your shell one-liners rely heavily on `regex-with-pcre` operators (`?=~`, `*=~/`, `matched`, `[re|...|]`, `[ed|...|]`). `TP-META-007` upgrades `Smirk.QuasiQuoter`, but doesn't explicitly mandate the infix operator surface `(?=~)` and `(*=~/)`.

 | Add a 15-line `Smirk.Operators` module in `TP-007D` / `tengri-sulde` exporting `(?=~)`, `(*=~/)`, and `matched` backed by `Smirk.Core.VM` so `tengri` drops `regex-with-pcre` (and `libpcre` C FFI) completely.

 |
| **4. Zsh Glob & Expansion Duplication** | `TP-META-010` (`Smirk.Glob.Zsh`, `Smirk.Zsh.Expansion`) vs. `tengri-lus` / `tengri-toli`

 | `TP-010B..010D` build a full Zsh glob qualifier walker and a two-sorted (`ValScalar` / `ValArray`) Zsh parameter expansion evaluator over `Penelope`. Building separate glob/expansion helpers in `tengri` would duplicate work.

 | Make `tengri-sulde` and `tengri-lus` thin re-exports/consumers of `Smirk.Glob.Zsh` and `Smirk.Zsh.Expansion.Eval`.

 |

---

### 2. Re-Sequencing the Campaign Waves (Hoisting `TP-META-010` for `tengri` & TUI)

Because `TP-META-010` (PCRE Callouts, Zsh Glob Qualifiers, and Zsh Parameter Expansion over `Penelope`) depends **only** on `TP-META-007` and `TP-META-008`—and does *not* depend on `TP-META-009` (Disk Index / External Sort) or `TP-META-011` (Marpa / Sheaf Parallel)—you should **hoist `TP-META-010` immediately after `TP-META-008**`:

```
Stage 1 (Immediate / Pre-Quota Reset — Pure & Local):
  ├── gongju: Drop in Gongju.{Diagonal,Spine,Evacuate,Tuple} (TP-TENGRI-001)
  └── TP-META-006: dunning-t-digest PrimArray/SmallArray & Polytropos DigestRecord

Stage 2 (Core Smirk + Penelope Overhaul — Kills the "Reader Fuel" Critique):
  ├── TP-META-007: Smirk Core VM SmallArray, StepMetrics, SuspendedCallout, Lucene INTERVAL, [reNE|...|]
  ├── TP-META-008: Smirk.Effect.{Penelope,Effectful,Polysemy} (BranchMatchPoly, ResourceBudget, fuel `min` defaultFuel)
  └── TP-META-010 [HOISTED]: Host-Effectful Callouts, Smirk.Glob.Zsh, & Smirk.Zsh.Expansion.{Syntax,Eval}

Stage 3 (Tengri Launch & Core Gargamelle Multiplier — Post 10:19 CET Quota Reset):
  ├── TP-TENGRI-002..004: tengri-sulde (with Smirk.Glob.Zsh + Penelope), tengri-lus, tengri-darkhan, tengri-savdag, tengri-toli
  ├── TP-META-004: gargamelle-oracle-sleep (AmbiguityOracle & Sleep-Phase Crystallization)
  └── TP-META-005: sarutahiko-yamaarashi-loop (Synquid Magnifier & CoEvolutionLoop)

Stage 4 (Heavy Streaming, Automata & Deductive Synthesis — Accelerated by Synquid Magnifier):
  ├── TP-META-009: Cooperative Quantum Slicing, Batching, NetworkFilter, & DiskIndex External Sort
  ├── TP-META-011: Glushkov Bit-Parallel NFA, Marpa Leo-Earley Engine, DPO Optimizer, & Sheaf Parallel
  └── TP-META-012: LiquidInstitution Measures, Conditional DPO Mining, & Synquid Pipeline Synthesis

```

Hoisting `TP-META-010` into Stage 2 pays a triple dividend:

1. It immediately gives `tengri` and your TUI tooling native Zsh globbing (`*(.)`, `*(Lm-5)`, `~*dist-newstyle*`) and inside-out parameter expansion (`"${(@)${foo}[1]}"`, `${(s/x/)foo%%1*}`)[cite: 48, 53].
2. It turns `smirk-penelope` and `smirk-effectful` into undeniably effectful engines (interleaving filesystem `lstat` pruning and symbol-table callouts mid-backtrack)[cite: 48, 53].
3. It saves `TP-META-011` (Marpa + DPO + Sheaf Parallel) and `TP-META-012` for Stage 4, where `TP-META-004` and `TP-META-005` can already shoulder the heavy deductive synthesis load[cite: 8, 48].



---

### 3. Higher-Level Campaign Constructs Above Task Packets (For `pgcl`, `Ingolstadt`, and Beyond)

Your observation about `pgcl` and `Ingolstadt` hits on a fundamental scaling boundary: **a flat queue of `TP-META-*.md` and `TP-*.yaml` files is a 1D tape, whereas your real campaigns are multi-dimensional fibrations**.

Consider `pgcl`:

* **Axis 1 (Host Kernels):** `Linux`, `FreeBSD`, `XNU`, `illumos`, `seL4`, `Zircon`.


* **Axis 2 (Kernel Subsystems):** `PageAlloc / Buddy-or-Zone`, `VMA / Radix / VM-Object`, `Rmap / PVMW / PMAP`, `PageCache / Folio / Vnode`, `IOMMU / DRM / Storage Drivers`.


* **Axis 3 (Hardware MMU Spectra):** `x86-64`, `AArch64` (contpte), `RISC-V` (Svnapot), `MIPS`, `LoongArch`, `SPARC`, `POWER`.



If you model this with raw task packets, you drown in hundreds of hand-written YAML files. Instead, we can formalize **three higher-level orchestration constructs** in `sarutahiko` (backed by Dhall schemas in `gachi`) above `TP-META` and `TP`:

```
Level 4: CampaignMatrix (Fibrational Pushout Schema: Base B × Weave W)
   │     e.g., pgcl-campaign.dhall  or  ingolstadt-100-frontends.dhall
   ▼
Level 3: CampaignArc (Stateful Branch & Recon-First HTN DAG per Cell)
   │     e.g., Arc(pgcl, FreeBSD, vm_page)  [branch: campaign/pgcl-freebsd-vm]
   │       ├── Phase 0: Pullback Recon Packet (Extracts Host locks/structs into Dhall/JSON witness)
   │       ├── Phase 1: Pushout Spec Generation (Instantiates Σ_HostVM -> FreeBSD vm_page_t)
   │       └── Phase 2: Unfolds into Level-2 Waves (TP-META) & Level-1 Leaf Packets (TP)
   ▼
Level 2: Wave / Meta-Packet (TP-META-*.md) — Cross-module milestone gate
   ▼
Level 1: Leaf Task Packet (TP-*.yaml / .dhall) — IsPrimitive(T) = True (<= 1 module)

```

#### Why `CampaignArc` + `CampaignMatrix` Solves the Multi-Kernel / Multi-Driver Problem:

1. Reconnaissance-First Unfolding (Solving the Foreign Code Comprehension Bottleneck):
In a foreign codebase like FreeBSD’s `sys/vm/` or a Linux GPU driver, you cannot write the concrete Tier-2 leaf packets upfront because you don't yet know the exact lock invariants or struct field names. A **`CampaignArc`** starts with a single **Reconnaissance Pullback Task** (`ArcRecon`) that runs `hs-tree-sitter` / `gargamelle-evidence` to extract the host kernel's local interface $C$ into a checked-in `.dhall` witness file.


2. Automatic Pushout Instantiation ($B_{\text{host}} \sqcup_C W$):
Once the `ArcRecon` witness is committed, a pure Dhall function (or `sarutahiko` functor) applies your portable `pgcl` weave specification $W$ to the extracted host witness $C$, **automatically emitting the Tier-1 `TP-META` and Tier-2 `TP` packets** for that specific kernel subsystem or driver!


3. Cross-Arc Fault Propagation (Sheaf Cohomology Across Subsystems):
If modifying `FreeBSD/pmap` in `Arc(pgcl, FreeBSD, pmap)` discovers that `vm_page_t` needs an extra alignment bitfield, that interface change is recorded on the shared `LiquidCellularSheaf` edge connecting `Arc(pgcl, FreeBSD, pmap)` to `Arc(pgcl, FreeBSD, vm_page)`, automatically queueing a targeted repair packet in the neighboring arc without manual babysitting.



Would you like to sketch the Dhall schema for `CampaignMatrix` / `CampaignArc` so you can drop it into `~/src/plans/` (and `gachi-schema`) alongside `TP-META-006..012`?
