module Bench.RSCoin.Local.InfraThreads
        ( addMintette
        , bankThread
        , mintetteThread
        , notaryThread
        ) where

import           Control.Monad.Catch        (bracket)
import           Control.Monad.Trans        (liftIO)
import           Data.Time.Units            (TimeUnit)
import           System.FilePath            ((</>))

import qualified RSCoin.Bank                as B
import           RSCoin.Core                (Mintette (Mintette),
                                             PlatformLayout (..), PublicKey,
                                             SecretKey, bankSecretKey,
                                             defaultPort, localhost, localPlatformLayout)
import qualified RSCoin.Mintette            as M
import qualified RSCoin.Notary              as N
import           RSCoin.Timed               (fork, runRealModeLocal)

import           Bench.RSCoin.FilePathUtils (dbFormatPath)

addMintette :: Int -> PublicKey -> IO ()
addMintette mintetteId = B.addMintetteIO bankSecretKey mintette
  where
    mintette = Mintette localhost (defaultPort + mintetteId)

bankThread :: (TimeUnit t) => t -> FilePath -> IO ()
bankThread periodDelta benchDir
    = B.launchBankReal localPlatformLayout periodDelta (benchDir </> "bank-db") bankSecretKey

mintetteThread :: Int -> FilePath -> SecretKey -> IO ()
mintetteThread mintetteId benchDir secretKey =
    runRealModeLocal $
    bracket
        (liftIO $
         M.openState $ benchDir </> dbFormatPath "mintette-db" mintetteId)
        (liftIO . M.closeState) $
    \mintetteState ->
         do _ <- fork $ M.runWorker secretKey mintetteState
            M.serve (defaultPort + mintetteId) mintetteState secretKey

notaryThread :: FilePath -> IO ()
notaryThread benchDir =
    runRealModeLocal $
    bracket
        (liftIO $ N.openState $ benchDir </> "notary-db")
        (liftIO . N.closeState)
        (N.serve $ snd $ getNotaryAddr localPlatformLayout)

