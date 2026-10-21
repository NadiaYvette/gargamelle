# Chapter 2: Signatures, Sentences, and Models

**Volume I:** Abstract Model Theory & Categorical Institutions  
**Production Typeclass:** [`Institution`](../../../../packages/gargamelle-core/src/Gargamelle/Core/Institution.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-core/docs/Gargamelle-Core-Institution.html#t:Institution))

---

## 1. The Mathematical Quadruple

An institution $\mathcal{I}$ is defined by:
1. A category $\mathbf{Sign}$ whose objects are signatures $\Sigma$ and whose morphisms $\sigma : \Sigma \to \Sigma'$ represent vocabulary expansions or renamings.
2. A functor $\mathbf{Sen} : \mathbf{Sign} \to \mathbf{Set}$ assigning to each signature $\Sigma$ the set of sentences $\mathbf{Sen}(\Sigma)$ expressible over that vocabulary, translating sentences covariantly along signature morphisms.
3. A contravariant functor $\mathbf{Mod} : \mathbf{Sign}^{\mathrm{op}} \to \mathbf{Cat}$ assigning to each signature $\Sigma$ the category of models $\mathbf{Mod}(\Sigma)$, and to each morphism $\sigma : \Sigma \to \Sigma'$ the model reduction functor $\mathbf{Mod}(\sigma) : \mathbf{Mod}(\Sigma') \to \mathbf{Mod}(\Sigma)$.
4. For each $\Sigma$, a satisfaction relation:
   $$\models_{\Sigma} \subseteq |\mathbf{Mod}(\Sigma)| \times \mathbf{Sen}(\Sigma)$$

---

## 2. Haskell Formulation in `gargamelle-core`

In Haskell, the institution pattern is expressed via the [`Institution`](../../../../packages/gargamelle-core/src/Gargamelle/Core/Institution.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-core/docs/Gargamelle-Core-Institution.html#t:Institution)) typeclass:

```haskell:ignore
class Institution i where
  type Sig i :: Type
  type Sen i :: Type
  type Mod i :: Type

  translateSen :: (Sig i -> Sig i) -> Sen i -> Sen i
  reductMod    :: (Sig i -> Sig i) -> ObsMor (Mod i) (Mod i)
  satisfactionVerifier :: Sen i -> Verifier (Mod i)
```

Crucially, note that [`reductMod`](../../../../packages/gargamelle-core/src/Gargamelle/Core/Institution.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-core/docs/Gargamelle-Core-Institution.html#v:reductMod)) returns an introspectable [`ObsMor`](../../../../packages/gargamelle-logic/src/Gargamelle/Logic/Defunctionalize.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-logic/docs/Gargamelle-Logic-Defunctionalize.html#t:ObsMor)) rather than an opaque Haskell function, and [`satisfactionVerifier`](../../../../packages/gargamelle-core/src/Gargamelle/Core/Institution.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-core/docs/Gargamelle-Core-Institution.html#v:satisfactionVerifier)) yields a free [`Verifier`](../../../../packages/gargamelle-model/src/Gargamelle/Model/Satisfaction.hs) ([Hackage](https://hackage.haskell.org/package/gargamelle-model/docs/Gargamelle-Model-Satisfaction.html#t:Verifier)) tree that can be evaluated to produce concrete evidence.
