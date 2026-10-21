{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BlockArguments #-}

module Main (main) where

import Test.Hspec
import Database.SQLite.Simple (open, close)
import Persistence.Schema
import Persistence.Beam

main :: IO ()
main = hspec do
  -- Tested against Note [Beam SQLite Relational Persistence and Concurrency Locking] [ref:note-beam-sqlite-persistence]
  describe "Beam SQLite Relational Persistence" do
    it "initializes SQLite schema cleanly in-memory" do
      conn <- open ":memory:"
      initEvidenceDb conn
      evList <- listAllEvidence conn
      evList `shouldBe` []
      close conn

    it "persists and retrieves evidence records" do
      conn <- open ":memory:"
      initEvidenceDb conn
      insertEvidenceRecord conn 1 "PropSig" "AstPatchV1" "TypeMismatch" 1600000000
      evs <- listAllEvidence conn
      length evs `shouldBe` 1
      case evs of
        (ev:_) -> do
          evidenceId ev `shouldBe` 1
          evidenceSig ev `shouldBe` "PropSig"
          evidenceChangeRep ev `shouldBe` "AstPatchV1"
          evidenceReason ev `shouldBe` "TypeMismatch"
        [] -> expectationFailure "Expected non-empty evidence list"

      byRep <- findEvidenceByRep conn "AstPatchV1"
      length byRep `shouldBe` 1
      close conn

    it "links counterexamples to evidence via foreign keys" do
      conn <- open ":memory:"
      initEvidenceDb conn
      insertEvidenceRecord conn 10 "FOLSig" "SortPatch" "SMT-Failed" 1600000100
      insertCounterexample conn 100 10 "x = -1, y = 0"

      ces <- findCounterexamplesFor conn 10
      length ces `shouldBe` 1
      case ces of
        (ce:_) -> do
          counterexampleId ce `shouldBe` 100
          counterexamplePayload ce `shouldBe` "x = -1, y = 0"
        [] -> expectationFailure "Expected non-empty counterexample list"
      close conn

    it "tracks autonomous workflow run lifecycle" do
      conn <- open ":memory:"
      initEvidenceDb conn
      startRunRecord conn 42 "InFlight" 1600000200
      completeRunRecord conn 42 "Success" 1600000250
      close conn
