{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Main
Description : gargamelle-audit CLI executable
Copyright   : (c) Nadia Yvette Chambers, 2026
License     : EUPL-1.2

@purpose
CLI executable for architectural audit, ratchet enforcement, and JSON self-repair diagnostics.

@behavior
Dispatches subcommands `check`, `baseline`, and `--self-test`.

@theory
Closed-loop verification gate and zero-regression codebase ratchet.

@contracts
Exits 0 on clean ratchet, exits 1 on blocking violations.

@pattern
CLI command-line dispatch.

@example
gargamelle-audit check --self-test
-}

module Main (main) where

import System.Environment (getArgs)
import System.Exit (exitWith)

import Gargamelle.Audit.Runner
  ( runAuditBaseline
  , runAuditCheck
  , runSelfTest
  )

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["check", "--self-test"] ->
      runSelfTest >>= exitWith

    ("check" : rest) -> do
      let (mRoot, mBaseline, touched, jsonRepair) = parseCheckArgs rest
      runAuditCheck mRoot mBaseline touched jsonRepair >>= exitWith

    ("baseline" : rest) -> do
      let (mRoot, mOut) = parseBaselineArgs rest
      runAuditBaseline mRoot mOut >>= exitWith

    ["--help"] -> do
      putStrLn "Usage: gargamelle-audit (check [--root DIR] [--baseline FILE] [--touched F1,F2] [--json-repair] [--self-test] | baseline [--root DIR] [--output FILE])"
    _ -> do
      putStrLn "Usage: gargamelle-audit (check [--root DIR] [--baseline FILE] [--touched F1,F2] [--json-repair] [--self-test] | baseline [--root DIR] [--output FILE])"

parseCheckArgs :: [String] -> (Maybe FilePath, Maybe FilePath, [FilePath], Bool)
parseCheckArgs args = go args Nothing Nothing [] False
  where
    go [] r b t j = (r, b, t, j)
    go ("--root":dir:rest) _ b t j = go rest (Just dir) b t j
    go ("--baseline":file:rest) r _ t j = go rest r (Just file) t j
    go ("--touched":files:rest) r b _ j = go rest r b (splitComma files) j
    go ("--json-repair":rest) r b t _ = go rest r b t True
    go (_:rest) r b t j = go rest r b t j

    splitComma s = case break (== ',') s of
      (chunk, "") -> [chunk]
      (chunk, _:tl) -> chunk : splitComma tl

parseBaselineArgs :: [String] -> (Maybe FilePath, Maybe FilePath)
parseBaselineArgs args = go args Nothing Nothing
  where
    go [] r o = (r, o)
    go ("--root":dir:rest) _ o = go rest (Just dir) o
    go ("--output":file:rest) r _ = go rest r (Just file)
    go (_:rest) r o = go rest r o
