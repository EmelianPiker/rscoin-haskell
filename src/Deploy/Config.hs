{-# LANGUAGE TemplateHaskell #-}

-- | Configuration for rscoin-deploy.

module Config
       ( DeployConfig (..)
       , BankData (..)
       , NotaryData (..)
       , MintetteData (..)
       , ExplorerData (..)
       , readDeployConfig
       ) where

import qualified Data.Aeson.TH as A
import           Data.Text     (Text)
import qualified Data.Yaml     as Y

import           RSCoin.Core   (Severity)

data DeployConfig = DeployConfig
    { dcDirectory :: !FilePath
    , dcExec      :: !Text
    , dcBank      :: !BankData
    , dcNotary    :: !NotaryData
    , dcMintettes :: ![MintetteData]
    , dcExplorers :: ![ExplorerData]
    , dcPeriod    :: !Word
    } deriving (Show)

data BankData = BankData
    { bdSecret   :: !FilePath
    , bdSeverity :: !(Maybe Severity)
    -- , bdProfiling :: !(Maybe ProfilingType)
    } deriving (Show)

data NotaryData = NotaryData
    { ndSeverity :: !(Maybe Severity)
    } deriving (Show)

data MintetteData = MintetteData
    { mdSeverity :: !(Maybe Severity)
    -- , mdProfiling :: !(Maybe ProfilingType)
    } deriving (Show)

data ExplorerData = ExplorerData
    { edSeverity :: !(Maybe Severity)
    -- , mdProfiling :: !(Maybe ProfilingType)
    } deriving (Show)

$(A.deriveJSON A.defaultOptions ''Severity)
$(A.deriveJSON A.defaultOptions ''DeployConfig)
$(A.deriveJSON A.defaultOptions ''BankData)
$(A.deriveJSON A.defaultOptions ''MintetteData)
$(A.deriveJSON A.defaultOptions ''ExplorerData)
$(A.deriveJSON A.defaultOptions ''NotaryData)

readDeployConfig :: FilePath -> IO DeployConfig
readDeployConfig fp =
    either (error . ("[FATAL] Failed to parse config: " ++) . show) id <$>
    Y.decodeFileEither fp
