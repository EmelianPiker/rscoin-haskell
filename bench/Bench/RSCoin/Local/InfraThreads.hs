module Bench.RSCoin.Local.InfraThreads
        ( addMintette
        , bankThread
        , mintetteThread
        , notaryThread
        ) where

import           Data.Optional              (Optional (Default))
import           Data.Time.Units            (TimeUnit)

import           System.FilePath            ((</>))

import qualified RSCoin.Bank                as B
import           RSCoin.Core                (ContextArgument (CADefault),
                                             Mintette (Mintette), PublicKey,
                                             SecretKey, Severity (Warning),
                                             defaultEpochDelta, defaultPort,
                                             localhost, testBankSecretKey)
import qualified RSCoin.Mintette            as M
import qualified RSCoin.Notary              as N

import           Bench.RSCoin.FilePathUtils (dbFormatPath)

addMintette :: Int -> PublicKey -> IO ()
addMintette mintetteId =
    B.addMintetteReq CADefault testBankSecretKey mintette
  where
    mintette = Mintette localhost (defaultPort + mintetteId)

bankThread :: TimeUnit t => t -> FilePath -> IO ()
bankThread periodDelta benchDir =
    B.launchBankReal
        False
        periodDelta
        (benchDir </> "bank-db")
        CADefault
        testBankSecretKey

mintetteThread :: Int -> FilePath -> SecretKey -> IO ()
mintetteThread mintetteId benchDir sk =
    M.launchMintetteReal
        False
        defaultEpochDelta
        port
        (M.mkRuntimeEnv 100000 sk)
        dbPath
        CADefault
  where
    port = defaultPort + mintetteId
    dbPath = Just $ benchDir </> dbFormatPath "mintette-db" mintetteId

notaryThread :: FilePath -> IO ()
notaryThread benchDir =
    N.launchNotaryReal Warning False dbPath B.CADefault webPort [] Default Default
  where
    webPort = defaultPort - 1
    dbPath = Just $ benchDir </> "notary-db"
