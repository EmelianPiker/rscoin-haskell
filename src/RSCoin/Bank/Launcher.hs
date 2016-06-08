{-# LANGUAGE FlexibleContexts #-}

-- | Functions launching Bank.

module RSCoin.Bank.Launcher
       ( launchBank
       , addMintetteIO
       ) where

import           Control.Monad.Catch   (bracket)
import           Control.Monad.Trans   (liftIO)
import           Data.Acid.Advanced    (update')

import           RSCoin.Core           (Mintette, PublicKey, SecretKey)
import           RSCoin.Timed          (MsgPackRpc, fork, killThread,
                                        runRealModeLocal)

import           RSCoin.Bank.AcidState (AddMintette (AddMintette), State,
                                        closeState, openState)
import           RSCoin.Bank.Server    (serve)
import           RSCoin.Bank.Worker    (runWorker)

bankWrapper :: FilePath -> (State -> MsgPackRpc ()) -> IO ()
bankWrapper storagePath =
    runRealModeLocal .
    bracket (liftIO $ openState storagePath) (liftIO . closeState)

launchBank :: FilePath -> SecretKey -> IO ()
launchBank storagePath sk = bankWrapper storagePath launch
  where
    launch st = do
        workerThread <- fork $ runWorker sk st
        serve st workerThread $ restartWorkerAction st
    restartWorkerAction st tId = do
        killThread tId
        fork $ runWorker sk st

addMintetteIO :: FilePath -> Mintette -> PublicKey -> IO ()
addMintetteIO storagePath m k =
    bankWrapper storagePath $ flip update' (AddMintette m k)
