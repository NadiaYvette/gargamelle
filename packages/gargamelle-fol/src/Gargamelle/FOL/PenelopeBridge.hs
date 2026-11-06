{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Gargamelle.FOL.PenelopeBridge
  ( translateEffectTypeToFOL
  , verifyEffectBudgetZ3
  ) where

import Gargamelle.Core.Institution.Liquid
import Gargamelle.Core.Institution.Liquid.Penelope
import Gargamelle.FOL.LiquidBridge (SubtypeResult (..), checkLiquidSubtypingZ3)

-- | Lowers an EffectType into a first-order formula with explicit pre/post
-- conditions and parameter bounds.
translateEffectTypeToFOL :: EffectType -> LiquidPred
translateEffectTypeToFOL EffectType{..} =
  PAnd [effOpPreCond, effOpPostCond]

-- | Submits negated budget formula to Z3; returns True if UNSAT (valid budget bounds).
--
-- Checks whether under the base signature and operation preconditions, the operation's
-- postcondition / budget bounds universally hold.
verifyEffectBudgetZ3 :: LiquidSig -> EffectType -> IO Bool
verifyEffectBudgetZ3 sig effType = do
  let vc = SenSubtype
        { subValueVar = "v_budget"
        , subSort     = effOpResult effType
        , subLhs      = effOpPreCond effType
        , subRhs      = effOpPostCond effType
        }
  res <- checkLiquidSubtypingZ3 sig vc
  pure $ case res of
    SubtypeValid -> True
    SubtypeRejected _ -> False
