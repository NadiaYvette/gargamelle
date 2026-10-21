# Chapter 4: Profunctor Optics & Vectorized Updates

**Volume IV:** Effectful Pipeline Architecture & Substrate Invariants  
**Production Module:** [`Gargamelle.Effect.Optics`](../../../../packages/gargamelle-effect/src/Gargamelle/Effect/Optics.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-effect/docs/Gargamelle-Effect-Optics.html))

---

## 1. Zero-Copy Profunctor Optics

Rather than depending on heavy template-haskell lens libraries that inflate compile times, [`Gargamelle.Effect.Optics`](../../../../packages/gargamelle-effect/src/Gargamelle/Effect/Optics.hs) defines lightweight profunctor lenses and prisms:

```haskell:ignore
type Lens' s a = forall p. Strong p => p a a -> p s s
type Prism' s a = forall p. Choice p => p a a -> p s s
```

---

## 2. Copy-On-Write Thaw Semantics

When updating a record field in a wide structural record, naive functional updating copies every spine cell.

Through integration with `polytropos-profunctors`, [`typedSlotLens`](../../../../packages/gargamelle-effect/src/Gargamelle/Effect/Optics.hs) delegates to `Polytropos.Core.setFieldAt`. It performs a copy-on-write clone of the underlying `SmallArray`, mutates only the specified slot, and freezes the array, achieving optimal runtime performance with 100% referential transparency.
