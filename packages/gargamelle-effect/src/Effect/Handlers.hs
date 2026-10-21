{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}

-- | Handlers module for the Kernmantle effect orchestration layer.
--
-- Interprets strand effect requests into a concrete arrow computation,
-- supporting both real IO execution (Kleisli IO) and pure deterministic mocking.
module Effect.Handlers
  ( Handlers(..)
  , MockState(..)
  , initialMockState
  , productionHandlers
  , pureMockHandlers
  , beamSqliteHandlers
  ) where

import Control.Arrow (Kleisli(..))
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Data.Text (Text)
import qualified Data.Text as T
import Data.Word (Word64)
import Database.SQLite.Simple (Connection)
import Persistence.Schema (evidenceReason)
import Persistence.Beam (findEvidenceByRep, insertEvidenceRecord)
import Effect.Strand

-- | A record of handlers mapping each strand to a target arrow @core@.
data Handlers core = Handlers
  { handleLogMsg    :: forall a b. LogMsg a b -> core a b
  , handleReadFile  :: forall a b. ReadFile a b -> core a b
  , handleWriteFile :: forall a b. WriteFile a b -> core a b
  , handleSandbox   :: forall a b. RunSandbox a b -> core a b
  , handleQueryBeam :: forall a b. QueryBeam a b -> core a b
  , handleRandom    :: forall a b. Random a b -> core a b
  , handleTimer     :: forall a b. Timer a b -> core a b
  }

-- | Production handlers running in Kleisli IO.
productionHandlers :: Handlers (Kleisli IO)
productionHandlers = Handlers
  { handleLogMsg = \case
      LogInfo msg  -> Kleisli $ \_ -> putStrLn ("[INFO] " ++ T.unpack msg)
      LogWarn msg  -> Kleisli $ \_ -> putStrLn ("[WARN] " ++ T.unpack msg)
      LogError msg -> Kleisli $ \_ -> putStrLn ("[ERROR] " ++ T.unpack msg)
  , handleReadFile = \case
      ReadTextFile fp -> Kleisli $ \_ -> do
        content <- readFile fp
        pure (Right (T.pack content))
  , handleWriteFile = \case
      WriteTextFile fp txt -> Kleisli $ \_ -> do
        writeFile fp (T.unpack txt)
        pure (Right ())
  , handleSandbox = \case
      RunCommand _cmd _args -> Kleisli $ \_ ->
        pure (0, T.pack "sandbox-success", T.empty)
  , handleQueryBeam = \case
      QueryEvidence _k -> Kleisli $ \_ -> pure Nothing
      StoreEvidence _k _v -> Kleisli $ \_ -> pure True
  , handleRandom = \case
      GetRandomWord -> Kleisli $ \_ -> pure 42
      GetRandomRange (lo, _hi) -> Kleisli $ \_ -> pure lo
  , handleTimer = \case
      GetTimestamp -> Kleisli $ \_ -> pure 1000000
      DelayMicroseconds _ -> Kleisli $ \_ -> pure ()
  }

-- | Pure state for hermetic unit testing without IO side effects.
data MockState = MockState
  { mockLogs       :: [Text]
  , mockFiles      :: Map FilePath Text
  , mockEvidence   :: Map Text Text
  , mockRandomSeed :: Word64
  } deriving (Show, Eq)

initialMockState :: MockState
initialMockState = MockState [] Map.empty Map.empty 42

-- | Pure mock handlers returning deterministic mock values without IO.
pureMockHandlers :: Handlers (Kleisli (Either Text))
pureMockHandlers = Handlers
  { handleLogMsg = \case
      LogInfo _  -> Kleisli $ \_ -> Right ()
      LogWarn _  -> Kleisli $ \_ -> Right ()
      LogError _ -> Kleisli $ \_ -> Right ()
  , handleReadFile = \case
      ReadTextFile fp -> Kleisli $ \_ -> Right (Right (T.pack ("mock-content-for-" ++ fp)))
  , handleWriteFile = \case
      WriteTextFile _fp _txt -> Kleisli $ \_ -> Right (Right ())
  , handleSandbox = \case
      RunCommand _cmd _args -> Kleisli $ \_ -> Right (0, T.pack "mock-run-ok", T.empty)
  , handleQueryBeam = \case
      QueryEvidence _k -> Kleisli $ \_ -> Right (Just (T.pack "mock-evidence-val"))
      StoreEvidence _k _v -> Kleisli $ \_ -> Right True
  , handleRandom = \case
      GetRandomWord -> Kleisli $ \_ -> Right 42
      GetRandomRange (lo, _) -> Kleisli $ \_ -> Right lo
  , handleTimer = \case
      GetTimestamp -> Kleisli $ \_ -> Right 123456
      DelayMicroseconds _ -> Kleisli $ \_ -> Right ()
  }

-- | Specialized handlers wired directly to a Beam SQLite database
beamSqliteHandlers :: Connection -> Handlers (Kleisli IO)
beamSqliteHandlers conn = productionHandlers
  { handleQueryBeam = \case
      QueryEvidence rep -> Kleisli $ \_ -> do
        mRec <- findEvidenceByRep conn rep
        pure (fmap evidenceReason mRec)
      StoreEvidence rep reason -> Kleisli $ \_ -> do
        insertEvidenceRecord conn 1 "Institution" rep reason 1000000
        pure True
  }

