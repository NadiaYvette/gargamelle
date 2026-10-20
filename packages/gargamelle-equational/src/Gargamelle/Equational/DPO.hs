{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE BlockArguments #-}

module Gargamelle.Equational.DPO
  ( Rule(..)
  , DPOStepResult(..)
  , applyDPO
  , isDPOApplicable
  , makeRule
  ) where

import Proarrow.Core (CategoryOf(..), type (~>))
import Proarrow.Tools.DPO (HasPushoutComplements(..), Rule(..), dpoStep)

-- | Construct a DPO rewrite rule from a left leg (l <- a) and right leg (a -> r).
makeRule :: forall k (a :: k) (l :: k) (r :: k). (a ~> l) -> (a ~> r) -> Rule a l r
makeRule = Rule

-- | Grounded result of executing a Double-Pushout (DPO) rewrite step.
-- When the gluing condition holds, produces the context/complement object 'd',
-- the rewritten host object 'h', and canonical inclusions.
-- When the gluing condition fails (dangling edge or identification conflict),
-- reports 'DPOGluingFailed'.
data DPOStepResult k g r where
  DPOSuccess
    :: forall k g r (d :: k) (h :: k).
       (d ~> g)  -- ^ Context inclusion into host object g
    -> (d ~> h)  -- ^ Context inclusion into rewritten object h
    -> (r ~> h)  -- ^ Right-hand pattern embedding into rewritten object h
    -> DPOStepResult k g r
  DPOGluingFailed :: DPOStepResult k g r

-- | Apply a DPO rewrite rule to a host object along a match morphism (l ~> g).
applyDPO
  :: forall k (a :: k) (l :: k) (r :: k) (g :: k). HasPushoutComplements k
  => Rule a l r
  -> (l ~> g)
  -> DPOStepResult k g r
applyDPO rule match =
  dpoStep rule match DPOSuccess DPOGluingFailed

-- | Check whether a rule can be applied at a match without executing the full rewrite.
isDPOApplicable
  :: forall k (a :: k) (l :: k) (r :: k) (g :: k). HasPushoutComplements k
  => Rule a l r
  -> (l ~> g)
  -> Bool
isDPOApplicable rule match =
  dpoStep rule match (\_ _ _ -> True) False
