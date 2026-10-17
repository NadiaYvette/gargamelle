# Design Review: Gargamelle Institution Framework

## Overview

This document outlines the design and usage of the Gargamelle.Institution module, which provides the core Institution typeclass for the Gargamelle framework.

## Motivation

Institutions provide a uniform way to handle different logical systems. By abstracting over the signature, sentences, models, and satisfaction relation, we can write generic code that works across various logics (propositional, first-order, equational, etc.).

## Implementation

The Institution typeclass is defined as follows:

```haskell
class Institution (sig :: k) where
  type Sentence sig :: Type
  type Model  sig :: Type
  satisfies :: Proxy sig -> Model sig -> Sentence sig -> Bool
```

### Notes on Usage

See Note [Institution overview] in the source for a detailed explanation.

## Example

To be filled in as we implement specific institutions (e.g., FirstOrderInstitution).

## Related Modules

- Gargamelle.FirstOrder: First-order logic institution (using Folly)
- Gargamelle.Equational: Equational logic institution (using Jukebox)
- Gargamelle.SessionTypes: Session types institution
- etc.

## Future Work

- Implement institution morphisms and comorphisms.
- Define colimits and limits of institution diagrams.
- Integrate with Kernmantle for effectful institution construction.
- Use Beam for persistence of institution instances.
