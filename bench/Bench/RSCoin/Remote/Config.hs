{-# LANGUAGE TemplateHaskell #-}

-- | Config for remote benchmark.

module Bench.RSCoin.Remote.Config
       ( RemoteConfig (..)
       , MintetteData (..)
       , UsersData (..)
       , readRemoteConfig
       ) where

import qualified Data.Aeson.TH                        as A
import           Data.Maybe                           (fromMaybe)
import           Data.Text                            (Text)
import qualified Data.Yaml                            as Y

import           Bench.RSCoin.Remote.StageRestriction (defaultOptions)

data RemoteConfig = RemoteConfig
    { rcUsersNum        :: !Word
    , rcTransactionsNum :: !Word
    , rcBank            :: !Text
    , rcMintettes       :: ![MintetteData]
    , rcUsers           :: !UsersData
    , rcShardDivider    :: !Word
    , rcShardDelta      :: !Word
    , rcPeriod          :: !Word
    } deriving (Show)

data MintetteData = MintetteData
    { mdHasRSCoin :: !Bool
    , mdHost      :: !Text
    } deriving (Show)

data UsersData = UsersData
    { udHasRSCoin :: !Bool
    , udHost      :: !Text
    } deriving (Show)

$(A.deriveJSON defaultOptions ''RemoteConfig)
$(A.deriveJSON defaultOptions ''MintetteData)
$(A.deriveJSON defaultOptions ''UsersData)

readRemoteConfig :: FilePath -> IO RemoteConfig
readRemoteConfig fp =
    fromMaybe (error "FATAL: failed to parse config") <$> Y.decodeFile fp
