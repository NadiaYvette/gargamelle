{-# LANGUAGE DataKinds, TypeFamilies, GADTs, FlexibleInstances, MultiParamTypeClasses, PolyKinds, RankNTypes #-}

module Propositional where

import Institution
import GHC.TypeLits
import Data.Kind (Type)
import Data.Proxy

-- | A wrapper for propositional signatures (lists of atoms).
newtype PropSig (atoms :: [Symbol]) = PropSig (Proxy atoms)

-- | Sentences over a given set of atoms (signature is the atom list).
data SentProp (atoms :: [Symbol]) where
  Top   :: SentProp atoms
  Bot   :: SentProp atoms
  Atom  :: KnownSymbol sym => Proxy sym -> SentProp atoms
  Neg   :: SentProp atoms -> SentProp atoms
  Conj  :: SentProp atoms -> SentProp atoms -> SentProp atoms
  Disj  :: SentProp atoms -> SentProp atoms -> SentProp atoms
  Impl  :: SentProp atoms -> SentProp atoms -> SentProp atoms

-- | Models are truth assignments for the atoms.
-- We represent them as a function from atom to Bool.
newtype ModProp (atoms :: [Symbol]) = ModProp { getVal :: forall sym. KnownSymbol sym => Proxy sym -> Bool }

instance Show (ModProp atoms) where
  show _ = "<model>"

-- | Satisfaction: evaluate the formula under the truth assignment.
satProp :: ModProp atoms -> SentProp atoms -> Bool
satProp m Top = True
satProp m Bot = False
satProp m (Atom p) = getVal m p
satProp m (Neg f) = not (satProp m f)
satProp m (Conj f g) = satProp m f && satProp m g
satProp m (Disj f g) = satProp m f || satProp m g
satProp m (Impl f g) = not (satProp m f) || satProp m g

-- | Show instance for SentProp (handles the existential in Atom).
instance Show (SentProp atoms) where
  show Top = "⊤"
  show Bot = "⊥"
  show (Atom p) = "atom " ++ showSym p
  show (Neg f) = "¬" ++ show f
  show (Conj f g) = "(" ++ show f ++ " ∧ " ++ show g ++ ")"
  show (Disj f g) = "(" ++ show f ++ " ∨ " ++ show g ++ ")"
  show (Impl f g) = "(" ++ show f ++ " → " ++ show g ++ ")"

showSym :: KnownSymbol sym => Proxy sym -> String
showSym = symbolVal

-- | Institution instance for propositional logic.
-- The signature is the list of atoms.
instance Institution (PropSig xs) where
  type Sentence (PropSig xs) = SentProp xs
  type Model  (PropSig xs)  = ModProp xs
  satisfies _ = satProp