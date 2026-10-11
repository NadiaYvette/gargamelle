{-# LANGUAGE DataKinds, TypeFamilies, GADTs, KindSignatures, FlexibleInstances, MultiParamTypeClasses, PolyKinds, RankNTypes, TypeApplications #-}

module Main where

import Propositional
import Institution
import Data.Proxy
import GHC.TypeLits (Symbol, KnownSymbol, symbolVal)

-- Define two atoms: P and Q
type P = "P"
type Q = "Q"

-- A signature containing both atoms
type Sig = '[P, Q]

-- Helper to build proxies for atoms
p :: Proxy P
p = Proxy
q :: Proxy Q
q = Proxy

-- Build a simple sentence: P ∧ Q
sent :: SentProp Sig
sent = Conj (Atom p) (Atom q)

-- A model where both P and Q are true
modelTrue :: ModProp Sig
modelTrue = ModProp $ \_ -> True

-- A model where P is true, Q is false
-- Compare the Symbol of the proxy with symbolVal p
modelPTrue :: ModProp Sig
modelPTrue = ModProp $ \sym ->
  if symbolVal sym == symbolVal p then True else False

-- A helper that uses the Institution class
testSat :: Institution sig => Proxy sig -> Model sig -> Sentence sig -> Bool
testSat = satisfies

main :: IO ()
main = do
  putStrLn "Signature: [P, Q]"
  putStrLn $ "Sentence: " ++ show sent
  putStrLn $ "Satisfies in model where both P and Q are true? " ++ show (testSat (Proxy :: Proxy Sig) modelTrue sent)
  putStrLn $ "Satisfies in model where P true, Q false? " ++ show (testSat (Proxy :: Proxy Sig) modelPTrue sent)
  -- Also test a disjunction
  let sent2 = Disj (Atom p) (Atom q)
  putStrLn $ "Sentence: " ++ show sent2
  putStrLn $ "Satisfies in model where P true, Q false? " ++ show (testSat (Proxy :: Proxy Sig) modelPTrue sent2)