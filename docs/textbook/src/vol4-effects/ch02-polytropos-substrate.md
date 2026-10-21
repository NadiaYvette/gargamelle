# Chapter 2: The Polytropos Substrate

**Volume IV:** Effectful Pipeline Architecture & Substrate Invariants  
**Substrate Engine:** [`polytropos`](https://github.com/nadia-chambers/polytropos)

---

## 1. Unifying Products and Sums

In standard Haskell, extensible records and variants are implemented as balanced binary trees of pairs and eithers, or nested dictionary lists. At compile time, GHC's Core language explodes into thousands of dictionary casts ($O(n^2)$ compile times); at runtime, accessing field 50 requires traversing 50 pointer indirections.

`polytropos` collapses the four quadrants of the nominal/structural design space into a single primitive representation:

```haskell:ignore
data Rep = Rep
  { repTag  :: {-# UNPACK #-} !Word
  , repVals :: {-# UNPACK #-} !(SmallArray Any)
  }
```

---

## 2. Compile-Time Literal Indices

By coupling `Rep` with a GHC Typechecker Plugin (`polytropos-plugin`), field lookups and variant injections compute literal slot offsets directly at compile time ($O(1)$).

When Gargamelle executes thousands of AST transformations, state transitions, and proof queries, intermediate data structures live in flat `SmallArray` payload slots with zero pointer chasing and predictable CPU L1/L2 cache locality.
