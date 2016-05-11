module RSCoin.Timed.Misc
       ( repeatForever
       ) where

import Control.Exception.Base      (SomeException)
import Control.Monad.Catch         (MonadCatch, catch)
import Control.Monad.Trans         (MonadIO, liftIO)
import Control.Monad.STM           (atomically)
import Control.Concurrent.STM.TVar (newTVarIO, readTVarIO, writeTVar)

import RSCoin.Timed.MonadTimed     (MicroSeconds, MonadTimed, for,
                                    fork, mcs, ms, startTimer, wait)

-- | Repeats an action periodically. 
--   If it fails, handler is invoked, determing delay for retrying.
--   Can be interrupted with asyncronious exception.
repeatForever :: (MonadTimed m, MonadIO m, MonadCatch m)
              => MicroSeconds    -- ^ Period between action launches
              -> (SomeException -> m MicroSeconds)
                                 -- ^ What to do on exception,
                                 --   returns delay before retrying
              -> m ()            -- ^ Action
              -> m ()
repeatForever period handler action = do
    timer <- startTimer
    nextDelay <- liftIO $ newTVarIO Nothing
    fork $
        let setNextDelay = liftIO . atomically . writeTVar nextDelay . Just
            action'      = action >> timer >>=
                            \passed -> setNextDelay (period - passed)
            handler' e   = handler e >>= setNextDelay
        in  action' `catch` handler'

    waitForRes nextDelay

  where
    continue = repeatForever period handler action
    waitForRes nextDelay = do
        wait $ for 10 ms
        res <- liftIO $ readTVarIO nextDelay
        case res of
            Nothing -> waitForRes nextDelay
            Just t  -> wait (for t mcs) >> continue
