{-# LANGUAGE TemplateHaskell #-}

-- This module contains functions to work with compile-time
-- configuration and data type representing this configuration.

module RSCoin.Core.CompileConfig
    ( RSCoinConfig (..)
    , RSCoinServer (..)
    , rscoinConfigStr
    , toAddr
    , rscoinConfig
    ) where

import qualified Data.Aeson.TH                   as A
import           Data.FileEmbed                  (embedStringFile,
                                                  makeRelativeToProject)
import           Data.Maybe                      (fromMaybe)
import           Data.String                     (IsString)
import           Data.Yaml                       (decode)

import           RSCoin.Core.CompileConfigHelper (defaultOptions)
import           RSCoin.Timed.MonadRpc

data RSCoinServer = RSCoinServer
    { rscHost :: !String
    , rscPort :: !Port
    } deriving (Show)

data RSCoinConfig = RSCoinConfig
    { rscShardDivider  :: !Int
    , rscShardDelta    :: !Int
    , rscRpcTimeout    :: !Word
    , rscDefaultBank   :: !RSCoinServer
    , rscDefaultSigner :: !RSCoinServer
    } deriving (Show)

$(A.deriveJSON defaultOptions ''RSCoinServer)
$(A.deriveJSON defaultOptions ''RSCoinConfig)

toAddr (RSCoinServer host port) = (host, port)

rscoinConfigStr :: IsString s => s
rscoinConfigStr = $(makeRelativeToProject "rscoin.yaml" >>= embedStringFile)

-- | Reading configuration from `rscoin.yaml` file and return it in data type.
rscoinConfig :: RSCoinConfig
rscoinConfig =
    fromMaybe (error "FATAL: failed to parse rscoin.yaml") $ decode rscoinConfigStr
