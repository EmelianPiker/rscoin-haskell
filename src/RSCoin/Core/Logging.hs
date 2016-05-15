{-# LANGUAGE ViewPatterns #-}

-- | Logging functionality.

module RSCoin.Core.Logging
       ( Severity (..)
       , initLogging
       , initLoggerByName
       , LoggerName
       , bankLoggerName
       , mintetteLoggerName
       , userLoggerName
       , timedLoggerName
       , communicationLoggerName
       , logDebug
       , logInfo
       , logWarning
       , logError
       , logMessage
       ) where

import           Control.Monad.IO.Class    (MonadIO, liftIO)
import qualified Data.Text                 as T
import           System.IO                 (stderr, stdout)
import           System.Log.Formatter      (simpleLogFormatter)
import           System.Log.Handler        (setFormatter)
import           System.Log.Handler.Simple (streamHandler)
import           System.Log.Logger         (Priority (DEBUG, ERROR, INFO, WARNING),
                                            logM, removeHandler, rootLoggerName,
                                            setHandlers, setLevel,
                                            updateGlobalLogger)

-- | This type is intended to be used as command line option
-- which specifies which messages to print.
data Severity
    = Debug
    | Info
    | Warning
    | Error
    deriving (Show, Read, Eq)

convertSeverity :: Severity -> Priority
convertSeverity Debug = DEBUG
convertSeverity Info = INFO
convertSeverity Warning = WARNING
convertSeverity Error = ERROR

initLogging :: Severity -> IO ()
initLogging sev@(convertSeverity -> s) = do
    updateGlobalLogger rootLoggerName removeHandler
    updateGlobalLogger rootLoggerName $ setLevel s
    mapM_ (initLoggerByName sev) predefinedLoggers

initLoggerByName :: Severity -> LoggerName -> IO ()
initLoggerByName (convertSeverity -> s) name = do
    stdoutHandler <-
        (flip setFormatter) stdoutFormatter <$> streamHandler stdout s
    stderrHandler <-
        (flip setFormatter) stderrFormatter <$> streamHandler stderr ERROR
    updateGlobalLogger name $ setHandlers [stdoutHandler, stderrHandler]
  where
    stderrFormatter = simpleLogFormatter "[$time] [$loggername] $prio: $msg"
    stdoutFormatter h r@(pr,_) n
      | pr > DEBUG = simpleLogFormatter "[$loggername] $msg" h r n
    stdoutFormatter h r n
      | otherwise = simpleLogFormatter "[$loggername] $msg" h r n

type LoggerName = String

bankLoggerName, mintetteLoggerName, userLoggerName, timedLoggerName, communicationLoggerName :: LoggerName
bankLoggerName = "bank"
mintetteLoggerName = "mintette"
userLoggerName = "user"
timedLoggerName = "timed"
communicationLoggerName = "timed"

predefinedLoggers :: [LoggerName]
predefinedLoggers =
    [bankLoggerName, mintetteLoggerName, userLoggerName, timedLoggerName]

logDebug :: MonadIO m
         => LoggerName -> T.Text -> m ()
logDebug = logMessage Debug

logInfo :: MonadIO m
        => LoggerName -> T.Text -> m ()
logInfo = logMessage Info

logWarning :: MonadIO m
        => LoggerName -> T.Text -> m ()
logWarning = logMessage Warning

logError :: MonadIO m
        => LoggerName -> T.Text -> m ()
logError = logMessage Error

logMessage
    :: MonadIO m
    => Severity -> LoggerName -> T.Text -> m ()
logMessage severity loggerName =
    liftIO . logM loggerName (convertSeverity severity) . T.unpack
