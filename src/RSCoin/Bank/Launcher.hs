{-# LANGUAGE FlexibleContexts #-}

-- | Functions launching Bank.

module RSCoin.Bank.Launcher
       ( bankWrapperReal
       , launchBankReal
       , launchBank
       , addMintetteIO
       ) where

import           Control.Monad.Catch   (bracket)
import           Control.Monad.Trans   (liftIO)
import           Data.Acid.Advanced    (update')
import           Data.Time.Units       (TimeUnit)

import           RSCoin.Core           (Mintette, PublicKey, SecretKey)
import           RSCoin.Timed          (MsgPackRpc, WorkMode, fork, killThread,
                                        runRealModeLocal)

import           RSCoin.Bank.AcidState (AddMintette (AddMintette), State,
                                        closeState, openState)
import           RSCoin.Bank.Server    (serve)
import           RSCoin.Bank.Worker    (runWorkerWithPeriod)

bankWrapperReal :: FilePath -> (State -> MsgPackRpc a) -> IO a
bankWrapperReal storagePath =
    runRealModeLocal .
    bracket (liftIO $ openState storagePath) (liftIO . closeState)

launchBankReal :: (TimeUnit t) => t -> FilePath -> SecretKey -> IO ()
launchBankReal periodDelta storagePath sk =
    bankWrapperReal storagePath $ launchBank periodDelta sk

launchBank
    :: (TimeUnit t, WorkMode m)
    => t -> SecretKey -> State -> m ()
launchBank periodDelta sk st = do
    workerThread <- fork $ runWorkerWithPeriod periodDelta sk st
    serve st workerThread restartWorkerAction
  where
    restartWorkerAction tId = do
        killThread tId
        fork $ runWorkerWithPeriod periodDelta sk st

addMintetteIO :: FilePath -> Mintette -> PublicKey -> IO ()
addMintetteIO storagePath m k =
    bankWrapperReal storagePath $ flip update' (AddMintette m k)
