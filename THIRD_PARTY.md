<!--
SPDX-License-Identifier: BSD-3-Clause
-->
# THIRD-PARTY.md

Attribution index. Every package in this repository is EUPL v1.2; this file
records what was taken from elsewhere and under what notice.

**Empty is the correct state today.** No code has been copied into this
repository. `programming-in-the-large` is `native`, and the benchmark harness compiles
modules written for this repository. Observation and measurement are not
derivation; see `docs/notes/PROVENANCE.md`.

## Bundled code

None.

## Design provenance

Ideas and architecture were informed by prior art. None of this carries a
licence obligation, and it is recorded here only so that a later reader can
tell influence from copying.

| Project | Licence | What was taken |
| --- | --- | --- |
| [`large-records`](https://github.com/well-typed/large-records) (Well-Typed LLP, Juspay Technologies Pvt Ltd, Monadfix OÜ) | BSD-3-Clause | The framing of the problem: GHC's handling of large nominal records and row-polymorphic access is superlinear. |
| [`crem`](https://github.com/tweag/crem) (Tweag) | BSD-3-Clause | Compositional relational state machines and workflow representation ideas. |
| [`kernmantle`](https://github.com/tweag/kernmantle) (Yves Parès, Jean-Philippe Bernardy, Richard A. Eisenberg / Tweag) | BSD-3-Clause | Arrow-based effect handlers (Cayley/WriterA/ReaderA) for config-time analysis and process-time execution of workflows. |

## Sibling checkouts

`~/src/large-data`, `~/src/polytropos`, and `~/src/sarutahiko` are local co-development checkouts.
They are not dependencies, are not vendored, and nothing from them is compiled
as part of this project except where explicitly referenced in `cabal.project`.

## Adding an entry

When a port lands, add a row to **Bundled code** naming the upstream project,
its copyright holders as they appear in *its* `LICENSE`, and the files touched. Then add a `Ported from:` section to that
package's `LICENSE`.