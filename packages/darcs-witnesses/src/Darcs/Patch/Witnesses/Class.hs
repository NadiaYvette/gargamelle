{-# LANGUAGE GADTs #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

module Darcs.Patch.Witnesses.Class
  ( Invert(..)
  , Commute(..)
  , CleanMerge(..)
  , commuteFL
  , commuteRL
  ) where

import Darcs.Patch.Witnesses.Ordered (FL(..), (:>)(..), (:\/:)(..), (:/\:)(..), (+>+))

class Invert (p :: * -> * -> *) where
  invert :: p wX wY -> p wY wX

class Commute (p :: * -> * -> *) where
  commute :: (:>) p p wX wZ -> Maybe ((:>) p p wX wZ)

class CleanMerge (p :: * -> * -> *) where
  cleanMerge :: (:\/:) p p wX wY -> Maybe ((:/\:) p p wX wY)

instance Invert p => Invert (FL p) where
  invert NilFL = NilFL
  invert (p :>: ps) = invert ps +>+ (invert p :>: NilFL)

instance Commute p => Commute (FL p) where
  commute = commuteFL

-- | Commute a single patch past a forward list: (p :> qs) -> (qs' :> p')
commuteOne :: Commute p => (:>) p (FL p) wA wC -> Maybe ((:>) (FL p) p wA wC)
commuteOne (p :> NilFL) = Just (NilFL :> p)
commuteOne (p :> (q :>: qs)) = do
  q' :> p' <- commute (p :> q)
  qs' :> p'' <- commuteOne (p' :> qs)
  pure ((q' :>: qs') :> p'')

-- | Commute two forward lists: (xs :> ys) -> (ys' :> xs')
commuteFL :: Commute p => (:>) (FL p) (FL p) wA wC -> Maybe ((:>) (FL p) (FL p) wA wC)
commuteFL (NilFL :> ys) = Just (ys :> NilFL)
commuteFL ((x :>: rest) :> ys) = do
  ys' :> rest' <- commuteFL (rest :> ys)
  ys'' :> x'   <- commuteOne (x :> ys')
  pure (ys'' :> (x' :>: rest'))

-- | Helper for commuting backwards
commuteRL :: Commute p => (:>) (FL p) p wA wC -> Maybe ((:>) p (FL p) wA wC)
commuteRL (NilFL :> p) = Just (p :> NilFL)
commuteRL ((q :>: qs) :> p) = do
  p' :> qs' <- commuteRL (qs :> p)
  p'' :> q' <- commute (q :> p')
  pure (p'' :> (q' :>: qs'))
