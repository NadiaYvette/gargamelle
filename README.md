# Gargamelle

A Haskell library and toolkit for orchestrating autonomous programming campaigns at scale, inspired by Sarutahiko (effect‑based workflow orchestration) and Polytropos (extensible records/variants via GHC plugins).

The name “Gargamelle” comes from François Rabelais’ 1534 novel *Gargantua* (part 2 of the pentalogy *Gargantua and Pantagruel*). Gargamelle is the mother of the giant Gargantua, evoking the idea of a “mother of giants” – a fitting metaphor for a system that orchestrates large‑scale, autonomous programming campaigns.

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