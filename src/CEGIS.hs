{-# LANGUAGE DataKinds, TypeFamilies, GADTs, KindSignatures, PolyKinds #-}

module CEGIS where

-- | A simple assume-guarantee contract for modular synthesis.
-- In practice, these would be logical formulas over input/output variables.
data Contract input output = Contract
  { assume :: input -> Bool   -- ^ assumptions on the environment/inputs
  , guarantee :: input -> output -> Bool  -- ^ guarantee: if assumptions hold, then output satisfies property
  }

-- | Compose two contracts: (A1 ∧ G2) ⇒ G1 and (A2 ∧ G1) ⇒ G2, with global property Φ = G1 ∧ G2.
compose :: Contract i1 o1 -> Contract i2 o2 -> Contract (Either i1 i2) (Either o1 o2)
compose c1 c2 = Contract
  { assume = either (assume c1) (assume c2)
  , guarantee = \inp out ->
      case (inp, out) of
        (Left i1, Left o1) -> guarantee c1 i1 o1 && assume c2 i1  -- A2 must hold under A1? Actually need to check both ways
        (Right i2, Right o2) -> guarantee c2 i2 o2 && assume c1 i2
        _ -> False  -- mismatched sides
  }

-- | Circular CEGIS: when refining component M1, verifier only checks against contract G1 under assumption A1.
-- This is a placeholder for the actual verification condition.
checkCircular :: Contract i o -> i -> o -> Bool
checkCircular c inp out = assume c inp && guarantee c inp out
