-- | Convenience functions to launch mintette.

module RSCoin.Mintette.Launcher
       ( ContextArgument (..)

       , dumpStorageStatistics
       , launchMintetteReal
       , mintetteWrapperReal
       ) where

import           Control.Monad.Catch       (bracket)
import           Control.Monad.Trans       (MonadIO (liftIO))
import qualified Data.Text.IO              as TIO
import           Formatting                (int, sformat, stext, (%))

import           RSCoin.Core               (ContextArgument (..), RealMode,
                                            mintetteLoggerName, runRealModeUntrusted)

import           RSCoin.Mintette.Acidic    (GetPeriodId (..), closeState, getStatistics,
                                            openMemState, openState)
import           RSCoin.Mintette.AcidState (State, query)
import           RSCoin.Mintette.Env       (RuntimeEnv)
import           RSCoin.Mintette.Server    (serve)

mintetteWrapperReal :: Bool
                    -> Maybe FilePath
                    -> ContextArgument
                    -> (State -> RealMode a)
                    -> IO a
mintetteWrapperReal deleteIfExists dbPath ca action = do
    let openAction = maybe openMemState (openState deleteIfExists) dbPath
    runRealModeUntrusted mintetteLoggerName ca . bracket openAction closeState $
        action

launchMintetteReal
    ::
    Bool -> Int -> RuntimeEnv -> Maybe FilePath -> ContextArgument -> IO ()
launchMintetteReal deleteIfExists port env dbPath ctxArg =
    mintetteWrapperReal deleteIfExists dbPath ctxArg $ \st -> serve port st env

dumpStorageStatistics :: Bool -> FilePath -> ContextArgument -> IO ()
dumpStorageStatistics deleteIfExists dbPath ctxArg =
    mintetteWrapperReal deleteIfExists (Just dbPath) ctxArg impl
  where
    impl st = do
        pId <- query st GetPeriodId
        liftIO . TIO.putStrLn .
            sformat ("Storage statistics (period id is " % int % "):\n" % stext)
            pId =<< getStatistics st
