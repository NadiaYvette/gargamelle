<!--
SPDX-License-Identifier: EUPL-1.2
-->
Status: POLICY · v1.0 · 2026-10-05 — blessed; see `DOC_STRATEGY.md` §3 for what
blessing certifies and §8 for the authority it transfers.

# Provenance and licensing

What `programming-in-the-large` may legitimately take from elsewhere, what it must not, and
where the line falls for the libraries and packages we integrate or draw inspiration from.

## The short version

`programming-in-the-large` builds against `base`, `primitive`, and our institution/effect stack. It is not
a fork of anything. Where a *design idea* or architectural pattern came from
is recorded here and in `docs/registers/PACKAGES.md`. Per-file licence obligations arise only when code
is **copied**, and the obligation is narrow: EUPL v1.2.

## What is actually a derivative work

Copyright protects expression, not method. Three cases, in increasing order of
obligation:

| What we do | Obligation |
| --- | --- |
| Measure a library, benchmark it, read its Core | **None.** Observation is not derivation. |
| Adopt an idea, a representation, an architecture | **None.** Ideas are not copyrightable. |
| Copy source — even a few lines — | Retain the copyright/license notice. |

The relationship to external sibling repositories (`large-records`, `polytropos`, etc.) today is entirely in the first two rows. The
benchmark or components in this repository compile modules written for this repository; it
reads nothing from sibling checkouts unless explicitly integrated.

## Attribution when code is ported

If code is ported, the per-package `LICENSE` file carries a
`Ported from:` section, and `THIRD_PARTY.md` at the repository root is the
index. A file that is a clean-room reimplementation gets neither, and says so
in `docs/registers/PACKAGES.md`.

## Reviewing a port

Before a port lands, three questions:

1. Does any file contain copied upstream code? If yes, does it carry the
   notice?
2. Is the divergence large enough that upstream merges are dead? If yes, it is
   a port, not a fork.
3. Is the package listed in `cabal.project`, `docs/registers/PACKAGES.md`, and
   `THIRD_PARTY.md` as applicable?

## Cross-references

- `docs/registers/PACKAGES.md` — the per-package register.
- `THIRD_PARTY.md` — the attribution index.
- `LICENSE` — this repository's EUPL v1.2 license.