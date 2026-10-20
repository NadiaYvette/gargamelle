{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}

{-|
Module      : Gargamelle.Effect.Optics
Description : Re-exports pure profunctor optics from Polytropos
Copyright   : (c) 2026 The Gargamelle Authors
License     : EUPL-1.2
Maintainer  : nadia.yvette.chambers@ik.me

Re-exports 'Polytropos.Profunctors' upstreamed into @polytropos@.
-}
module Gargamelle.Effect.Optics
  ( module Polytropos.Profunctors
  ) where

import Polytropos.Profunctors
