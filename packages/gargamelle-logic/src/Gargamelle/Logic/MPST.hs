module Gargamelle.Logic.MPST
  ( Role(..)
  , Message(..)
  , GlobalType(..)
  , LocalType(..)
  ) where

-- | Participant role identifier in a multiparty protocol.
newtype Role = Role { getRole :: String }
  deriving (Eq, Show, Ord)

-- | Message label and payload sort.
data Message = Message
  { msgLabel :: String
  , msgSort  :: String
  } deriving (Eq, Show, Ord)

-- | Global session type representing the protocol choreography.
data GlobalType
  = GEnd
  | GComm Role Role Message GlobalType
  | GBranch Role Role [(Message, GlobalType)]
  | GRec String GlobalType
  | GVar String
  deriving (Eq, Show)

-- | Projected local session type for an individual participant role.
data LocalType
  = LEnd
  | LSend Role Message LocalType
  | LRecv Role Message LocalType
  | LSelect Role [(Message, LocalType)]
  | LBranch Role [(Message, LocalType)]
  | LRec String LocalType
  | LVar String
  deriving (Eq, Show)
