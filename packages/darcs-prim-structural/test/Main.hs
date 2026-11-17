{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (unless)
import Darcs.Patch.Prim.Structural
import Darcs.Patch.Witnesses
import System.Exit (exitFailure, exitSuccess)

main :: IO ()
main = do
  putStrLn "Running darcs-prim-structural test suite..."

  -- 1. Two distinct Cabal set insertions commute
  let p1 = PrimCabalSet "pkg.cabal" CabalExposedModules SetInsert "Foo.Bar" :: StructuralPrim () ()
      p2 = PrimCabalSet "pkg.cabal" CabalExposedModules SetInsert "Foo.Baz" :: StructuralPrim () ()
  case commute (p1 :> p2) of
    Just (PrimCabalSet f2 _ _ it2 :> PrimCabalSet f1 _ _ it1) -> do
      unless (f2 == "pkg.cabal" && it2 == "Foo.Baz" && f1 == "pkg.cabal" && it1 == "Foo.Bar") $ do
        putStrLn "Failed: Cabal set commute returned incorrect values"
        exitFailure
    _ -> do
      putStrLn "Failed: Cabal set insertions should commute"
      exitFailure

  -- 2. Two distinct declaration rewrites in the same file commute
  let d1 = PrimDeclRewrite "src/Lib.hs" "funcA" "funcA = 1" "funcA = 2" :: StructuralPrim () ()
      d2 = PrimDeclRewrite "src/Lib.hs" "funcB" "funcB = True" "funcB = False" :: StructuralPrim () ()
  case commute (d1 :> d2) of
    Just (PrimDeclRewrite f2 sym2 _ _ :> PrimDeclRewrite f1 sym1 _ _) -> do
      unless (f2 == "src/Lib.hs" && sym2 == "funcB" && f1 == "src/Lib.hs" && sym1 == "funcA") $ do
        putStrLn "Failed: Decl rewrite commute returned incorrect values"
        exitFailure
    _ -> do
      putStrLn "Failed: Distinct symbol rewrites should commute"
      exitFailure

  -- 3. Invert involution
  unless (invert (invert p1) == p1 && invert (invert d1) == d1) $ do
    putStrLn "Failed: Invert involution"
    exitFailure

  putStrLn "All darcs-prim-structural tests passed successfully."
  exitSuccess
