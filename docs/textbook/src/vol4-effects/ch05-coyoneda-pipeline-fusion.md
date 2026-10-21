# Chapter 5: Coyoneda Pipeline Fusion

**Volume IV:** Effectful Pipeline Architecture & Substrate Invariants  
**Production Module:** [`Gargamelle.Effect.Fusion`](../../../../packages/gargamelle-effect/src/Gargamelle/Effect/Fusion.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-effect/docs/Gargamelle-Effect-Fusion.html))

---

## 1. The Arrow Allocation Overhead

When composing deeply layered arrows $(f \ggg g \ggg h)$, standard arrow composition creates nested closure tuples `((a, b), c)` and intermediate wrapper allocations at every step of the pipeline.

In high-throughput symbolic evaluation, this generates millions of short-lived heap objects that trigger frequent GC pauses.

---

## 2. Fusion via Coyoneda

By embedding arrows into their Coyoneda representation, intermediate pure pre- and post-processing functions fuse into a single arrow application:

```haskell:ignore
fuseRope :: Rope core mantle a b -> Rope core mantle a b
```

As implemented in [`Gargamelle.Effect.Fusion`](../../../../packages/gargamelle-effect/src/Gargamelle/Effect/Fusion.hs), this pass normalizes arrow pipelines prior to execution, ensuring that multi-stage synthesis pipelines execute at near-C speeds without allocation bottlenecks.
