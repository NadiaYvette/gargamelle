# Gargamelle

A Haskell library and toolkit for orchestrating autonomous programming campaigns at scale, inspired by Sarutahiko (effect‑based workflow orchestration) and Polytropos (extensible records/variants via GHC plugins).

## Directory layout

- `packages/gargamelle/src/` – Haskell source code (core language, plugins, libraries)
- `packages/` – Optional separate Cabal packages (currently only gargamelle)
- `bin/` – Executables (orchestrator, REPL, code‑generation tools)
- `docs/transcripts/` – Tutorial‑style write‑ups
- `docs/notes/` – Design reviews, meeting minutes
- `test/` – Test suites
- `.agents/` – Hermes agent configuration (skills, plugins, cron, memories)
- `cabal.project` – Multi‑package build configuration

## Getting started

```bash
# Clone dependencies if needed
git clone https://github.com/yourname/sarutahiko.git
git clone https://github.com/yourname/polytropos.git

# Build with Cabal
cabal update
cabal build
```