{-# LANGUAGE DataKinds, TypeFamilies, GADTs, PolyKinds, FlexibleInstances, MultiParamTypeClasses #-}

module SessionTypes where

import Institution
import Data.Proxy
import GHC.TypeLits (Symbol, KnownSymbol, symbolVal)
import qualified Data.Map as Map

-- | A wrapper for session type signatures (lists of roles?).
-- We keep it phantom for now.
newtype STSSig (syms :: [Symbol]) = STSSig (Proxy syms)

-- | Terms: we represent session channels or endpoints.
-- For simplicity, we use strings to represent channel names.
data Term (syms :: [Symbol]) where
  Chan :: KnownSymbol sym => Proxy sym -> Term syms
  -- We could add more constructors for channel operations (send, receive, etc.)

-- | Sentences: we represent session type propositions.
-- For now, we use channel equality and basic session type predicates (like readiness).
data STSentence (syms :: [Symbol]) where
  ChanEq :: Term syms -> Term syms -> STSentence syms
  Ready  :: Term syms -> STSentence syms
  -- We could add more: Send, Recv, Select, Offer, etc.

-- | Model: a session type environment mapping channels to their current state.
-- We use a simple map from channel names to a string representing the state.
newtype STSModel (syms :: [Symbol]) = STSModel
  { channels :: Map.Map String String -- channel name -> current state (e.g., "ready", "sent", "received")
  }

instance Institution (STSSig syms) where
  type Sentence (STSSig syms) = STSentence syms
  type Model  (STSSig syms)  = STSModel syms
  satisfies _ m (ChanEq t1 t2) = evalTerm m t1 == evalTerm m t2
  satisfies _ m (Ready t)      = evalTerm m t `Map.lookup` channels m == Just "ready"

evalTerm :: STSModel syms -> Term syms -> String
evalTerm m (Chan s) = symbolVal s -- channel evaluates to its name

-- Smart constructors
chan :: KnownSymbol sym => Proxy sym -> Term syms
chan = Chan

chanEq :: Term syms -> Term syms -> STSentence syms
chanEq = ChanEq

ready :: Term syms -> STSentence syms
ready = Ready
