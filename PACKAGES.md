# PACKAGES.md

This file tracks the provenance of each package in the programming-in-the-large repository.
Each entry records the upstream source (if any), the license, and a brief description of what was taken.

## Packages in this repository

| Package | Upstream (if any) | License | Notes |
|---------|-------------------|---------|-------|
| programming-in-the-large | none | EUPL v1.2 | Main cabal package of the project. |
| (none currently) | | | |

## Design provenance

Ideas and architecture were informed by prior art. None of this carries a
license obligation, and it is recorded here only so that a later reader can
tell influence from copying.

| Project | License | What was taken |
|---------|---------|----------------|
| [`polytropos`](https://github.com/NYU-ProgLang/polytropos) | BSD-3-Clause | Institution framework, effect system design, and evidence tracking concepts. |
| [`large-records`](https://github.com/well-typed/large-records) | BSD-3-Clause | The problem framing: superlinear typechecking of large nominal records, and the use of plugins to mitigate. |
| [`kernmantle`](https://github.com/tweag/kernmantle) | BSD-3-Clause | Effect handler and Arrow-based workflow orchestration patterns. |
| [`beam`](https://github.com/haskell-beam/beam) | MIT | Type-safe, backend-agnostic persistence layer. |
| [`crem`](https://github.com/tweag/crem) | BSD-3-Clause | State machine library for workflow orchestration. |

## Adding an entry

When a port lands, add a row to the table above naming the upstream project,
its copyright holders as they appear in its `LICENSE`, the package name, and the files touched. Then add a `Ported from:` section to that
package's `LICENSE`, and record the entry in `THIRD_PARTY.md`.

The holder line differs per upstream package — copy it from the source, do not
reconstruct it from memory.
