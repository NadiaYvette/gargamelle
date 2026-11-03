{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE TypeOperators #-}

{-|
Module      : Gargamelle.Effect
Description : Unified effect orchestration layer for Gargamelle powered by Penelope and Polytropos
Copyright   : (c) 2026 The Gargamelle Authors
License     : EUPL-1.2
Maintainer  : nadia.yvette.chambers@ik.me

Umbrella module re-exporting Arrow Rope effect orchestration, O(1) variant routers,
profunctor optics, pipeline fusion, and Penelope's polycategorical effect system.
-}
module Gargamelle.Effect
  ( -- * Core Rope Arrow & Handlers
    module Effect.Rope
  , module Effect.Strand
  , module Effect.Handlers
    -- * Polytropos O(1) Variant Router
  , module Gargamelle.Effect.Router
    -- * Profunctor Optics for Open Records & Variants
  , module Gargamelle.Effect.Optics
    -- * Coyoneda Pipeline Fusion
  , module Gargamelle.Effect.Fusion
    -- * Penelope Polycategorical Engine
  , Penelope(..)
  , PolyEffect
  , PolyHEffect
  , PortSig
  , runPenelopePure
  , elaborateAll
  , interpretAll
  , interpretSub
    -- * Penelope Unary Eff Monad
  , Eff(..)
  , send
  , runEff
  , runEffM
    -- * Penelope Binary Arrow Rope
  , PenelopeRope
  ) where

import Effect.Rope
import Effect.Strand
import Effect.Handlers
import Gargamelle.Effect.Router
import Gargamelle.Effect.Optics
import Gargamelle.Effect.Fusion
import Penelope.Core
import Penelope.Effects.Unary
import qualified Penelope.Effects.Binary as P

-- | Type alias for Penelope's binary arrow projection over polycategorical circuits
type PenelopeRope = P.Rope
