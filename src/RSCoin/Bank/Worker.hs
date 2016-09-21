{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Worker that handles end of period.

module RSCoin.Bank.Worker
       ( runWorkerDefaultPeriod
       , runWorker
       , runExplorerWorker
       ) where

import           Control.Exception.Base   (AsyncException)
import           Control.Monad            (when)
import           Control.Monad.Catch      (Handler (..), SomeException, catch, catches,
                                           throwM)
import           Control.Monad.Extra      (unlessM)
import           Control.Monad.Trans      (MonadIO (liftIO))
import           Data.IORef               (IORef, readIORef)
import           Data.List                (sortOn)
import           Data.Maybe               (fromMaybe)
import           Data.Time.Units          (TimeUnit, convertUnit)
import           Formatting               (build, int, sformat, (%))

import           Serokell.Util.Exceptions ()

import           Control.TimeWarp.Timed   (for, ms, repeatForever, sec, wait)
import           RSCoin.Core              (defaultPeriodDelta, sign)
import qualified RSCoin.Core              as C

import           RSCoin.Bank.AcidState    (GetExplorersAndPeriods (..),
                                           GetHBlockWithMetadata (..), GetPeriodId (..),
                                           SetExplorerPeriod (..), State,
                                           SuspendExplorer (..), query, update)

-- | Start worker which runs appropriate action when a period
-- finishes. Default period length is used.
runWorkerDefaultPeriod
    :: C.WorkMode m
    => C.SecretKey -> State -> m ()
runWorkerDefaultPeriod = runWorker defaultPeriodDelta

-- | Start worker with provided period. Generalization of 'runWorker'.
-- IORef is used as synchronization primitive between this worker
-- and another worker (which communicates with explorers).
-- Its value is True is empty iff this worker is doing something now.
runWorker
    :: (TimeUnit t, C.WorkMode m)
    => t -> C.SecretKey -> State -> m ()
runWorker periodDelta bankSK st =
    repeatForever (convertUnit periodDelta) handler worker
  where
    worker = do
        periodId <- query st GetPeriodId
        let sig = sign bankSK periodId
        C.sendBankLocalControlRequest $ C.FinishPeriod sig
    handler e = do
        C.logError $
            sformat
                ("Error was caught by worker, restarting in 20 seconds: " % build)
                e
        return $ sec 20

-- | Start worker which sends data to explorers.
runExplorerWorker
    :: (C.WorkMode m)
    => IORef Bool -> C.SecretKey -> State -> m ()
runExplorerWorker mainIsBusy sk st =
    foreverSafe $
    do waitUntilPredicate (fmap not . liftIO $ readIORef mainIsBusy)
       blocksNumber <- query st GetPeriodId
       explorersAndPeriods <- query st GetExplorersAndPeriods
       let outdated = filter ((/= blocksNumber) . snd) explorersAndPeriods
           explorers = map fst explorersAndPeriods
        -- if all explorers are up-to-date, it doesn't make sense to
        -- do anything until period finish.
       when (null outdated) $ waitUntilPredicate (liftIO $ readIORef mainIsBusy)
       failedExplorers <-
           map fst . filter (not . snd) . zip explorers <$>
           communicateWithExplorers sk st blocksNumber outdated
       mapM_ (update st . SuspendExplorer) failedExplorers
  where
    foreverSafe action = do
        action `catches` [Handler skipAsyncHandler, Handler handler]
        foreverSafe action
    skipAsyncHandler (e :: AsyncException) = throwM e
    handler (e :: SomeException) = do
        C.logError $ sformat ("Error occurred inside ExplorerWorker: " % build) e
        wait $ for 10 sec
    shortWait = wait $ for 100 ms
    -- It would be much more elegant to use MVar here, but it's not
    -- supported by C.WorkMode
    waitUntilPredicate predicate =
        unlessM predicate $ shortWait >> waitUntilPredicate predicate

communicateWithExplorers
    :: C.WorkMode m
    => C.SecretKey -> State -> C.PeriodId -> [(C.Explorer, C.PeriodId)] -> m [Bool]
communicateWithExplorers sk st blocksNumber =
    mapM (communicateWithExplorer sk st blocksNumber) . sortOn (negate . snd)

communicateWithExplorer
    :: C.WorkMode m
    => C.SecretKey -> State -> C.PeriodId -> (C.Explorer, C.PeriodId) -> m Bool
communicateWithExplorer sk st blocksNumber (explorer,expectedPeriod)
  | blocksNumber == expectedPeriod = return True
  | expectedPeriod >= 0 && expectedPeriod < blocksNumber =
      sendBlockToExplorer sk st explorer expectedPeriod
  | otherwise =
      False <$
      C.logWarning
          (sformat
               (build % " expects block with strange PeriodId (" % int % ")")
               explorer
               expectedPeriod)

sendBlockToExplorer
    :: C.WorkMode m
    => C.SecretKey -> State -> C.Explorer -> C.PeriodId -> m Bool
sendBlockToExplorer sk st explorer pId = do
    blk <- fromMaybe reportFatalError <$> query st (GetHBlockWithMetadata pId)
    let sendAndUpdate = do
            newExpectedPeriod <- C.announceNewBlock explorer sk pId blk
            update st $ SetExplorerPeriod explorer newExpectedPeriod
    (True <$ sendAndUpdate) `catch` handler
  where
    reportFatalError =
        error "[FATAL] GetHBlock returned Nothing in sendBlockToExplorer"
    -- TODO: catch appropriate exception according to protocol implementation
    handler (e :: SomeException) =
        False <$
        (C.logWarning .
         sformat ("Error occurred in communicating with explorer: " % build) $
         e)
