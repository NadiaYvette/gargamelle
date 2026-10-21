# Chapter 2: Grounded Evidence Persistence

**Volume V:** Grounded Verification & Autonomous CEGIS  
**GHC Note Invariant:** Note [Beam SQLite Relational Persistence and Concurrency Locking] [ref:note-beam-sqlite-persistence]  
**Production Package:** [`packages/gargamelle-persistence`](../../../../packages/gargamelle-persistence/README.md) ([Hackage](https://hackage.haskell.org/package/gargamelle-persistence))

---

## 1. Why Synthesis Demands Relational Memory

Stateless synthesis agents quickly repeat previously refuted hypotheses. When a candidate patch fails against a test suite or SMT constraint, recording that counterexample in an in-memory variable means the knowledge is lost when the agent restarts or crashes.

Gargamelle grounds synthesis evidence in persistent relational SQLite databases using the **Beam** framework.

---

## 2. Relational Schemas in `gargamelle-persistence`

As formalized in Note [Beam SQLite Relational Persistence and Concurrency Locking] [ref:note-beam-sqlite-persistence], [`Persistence.Schema`](../../../../packages/gargamelle-persistence/src/Persistence/Schema.hs) defines three primary tables:
1. [`RunRecordT`](../../../../packages/gargamelle-persistence/src/Persistence/Schema.hs): Tracks synthesis sessions, timestamps, status (`Running`, `Success`, `Failure`), and execution iterations.
2. [`EvidenceRecordT`](../../../../packages/gargamelle-persistence/src/Persistence/Schema.hs): Stores verified AST sections, fingerprints, and proof certificates.
3. [`CounterexampleRecordT`](../../../../packages/gargamelle-persistence/src/Persistence/Schema.hs): Indexes failing inputs, countermodels, and error logs.

By querying [`findCounterexamplesFor`](../../../../packages/gargamelle-persistence/src/Persistence/Queries.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-persistence/docs/Persistence-Queries.html#v:findCounterexamplesFor)) before synthesizing new patches, `sarutahiko` verifies candidate proposals against all historical failure modes, eliminating repetitive synthesis regressions.
