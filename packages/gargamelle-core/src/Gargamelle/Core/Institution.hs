{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableSuperClasses #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE AllowAmbiguousTypes #-}

module Gargamelle.Core.Institution
  ( Sig
  , LogicalSyntax(..)
  , ModelTheory(..)
  , CategoricalInstitution(..)
  , InstitutionComorphism(..)
  , checkSatisfactionInvariance
  ) where

import Data.Kind (Type)
import Proarrow.Core (CategoryOf(..), type (~>))
import Gargamelle.Model.Satisfaction (Verifier, Evidence, evalVerifier)
import Gargamelle.Logic.Defunctionalize (TyFun, Apply, ObsMor, evalObsMor)

-- | Signature category of an institution.
type family Sig (i :: Type) :: Type

-- | 1. Logical Syntax (Proof Theory)
-- Signatures form a category. Sentences translate covariantly along morphisms.
class (CategoryOf (Sig i)) => LogicalSyntax (i :: Type) where
  type Sen i :: Sig i -> Type
  translateSen :: forall (s1 :: Sig i) (s2 :: Sig i). (s1 ~> s2) -> Sen i s1 -> Sen i s2
  (|-) :: forall (s :: Sig i). [Sen i s] -> Sen i s -> Bool

-- | 2. Model Theory (Semantics)
-- Models reduce contravariantly along signature morphisms using observable ObsMor.
class (CategoryOf (Sig i)) => ModelTheory (i :: Type) where
  type Mod i :: Sig i -> Type
  reductMod :: forall (s1 :: Sig i) (s2 :: Sig i). (s1 ~> s2) -> ObsMor (Mod i s2) (Mod i s1)

{- Note [Goguen-Burstall Categorical Institution Satisfaction Invariance]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[tag:note-institution-satisfaction-invariance]
In formal specification theory (Goguen & Burstall, 1984), an Institution formalizes
the essential ingredients of any mathematical or computer science logic:
  1. A category of signatures 'Sig i' whose arrows are signature morphisms (s1 ~> s2).
  2. A functor 'Sen i' translating sentences covariantly along signature morphisms:
       translateSen :: (s1 ~> s2) -> Sen i s1 -> Sen i s2
  3. A contravariant functor 'Mod i' reducing models contravariantly along morphisms:
       reductMod :: (s1 ~> s2) -> ObsMor (Mod i s2) (Mod i s1)
  4. A satisfaction relation family (⊨_s) satisfying the fundamental Satisfaction Condition:
       Mod(σ)(M') ⊨_s1 φ   ⟺   M' ⊨_s2 Sen(σ)(φ)

In Gargamelle, this meta-theoretic axiom is reified as an executable computational invariant:
  - 'satisfactionVerifier' returns an observable, free 'Verifier' AST producing structured
    'Evidence' rather than an opaque boolean.
  - 'checkSatisfactionInvariance' executes both sides of the condition:
      evLHS = evalVerifier (satisfactionVerifier (translateSen σ φ)) M'
      evRHS = evalVerifier (satisfactionVerifier φ) (reductMod σ M')
  - Invariance asserts: evLHS == evRHS.
    If M' satisfies the translated sentence, the reduct model satisfies the original sentence
    with identical 'VerifiedSection' evidence. Conversely, if M' fails, the exact same
    'Counterexample' witness is preserved across the institutional boundary.
-}

-- | 3. The Goguen-Burstall Categorical Institution
--
-- See Note [Goguen-Burstall Categorical Institution Satisfaction Invariance] [ref:note-institution-satisfaction-invariance].
--
-- Binds Syntax and Semantics via observable Free Verifier ASTs.
class (LogicalSyntax i, ModelTheory i) => CategoricalInstitution (i :: Type) where
  -- | Returns an inspectable Verifier AST for a sentence under signature @s@.
  satisfactionVerifier :: forall (s :: Sig i). Sen i s -> Verifier (Mod i s)

-- | Verification of the satisfaction condition for a concrete candidate:
-- M' |= translateSen σ φ  <===>  reductMod σ M' |= φ
--
-- See Note [Goguen-Burstall Categorical Institution Satisfaction Invariance] [ref:note-institution-satisfaction-invariance].
checkSatisfactionInvariance
  :: forall i (s1 :: Sig i) (s2 :: Sig i). CategoricalInstitution i
  => (s1 ~> s2)
  -> Sen i s1
  -> Mod i s2
  -> (Evidence, Evidence, Bool)
checkSatisfactionInvariance morph phi mPrime =
  let vTranslated = satisfactionVerifier @i (translateSen @i morph phi)
      vOriginal   = satisfactionVerifier @i phi
      mReduct     = evalObsMor (reductMod @i morph) mPrime
      evLHS       = evalVerifier vTranslated mPrime
      evRHS       = evalVerifier vOriginal mReduct
      isPreserved = evLHS == evRHS
  in (evLHS, evRHS, isPreserved)

-- | 4. Institution Comorphisms (Stepwise Refinement & Compiler Translation Passes)
-- Parameterized by a defunctionalized type-level signature translation @mapSig@.
data InstitutionComorphism src tgt (mapSig :: TyFun (Sig src) (Sig tgt) -> Type) = InstitutionComorphism
  { comorphismName :: String
  , transSen       :: forall (s :: Sig src). Sen src s -> Sen tgt (Apply mapSig s)
  , reductM        :: forall (s :: Sig src). ObsMor (Mod tgt (Apply mapSig s)) (Mod src s)
  }
