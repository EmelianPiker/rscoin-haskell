-- | Launch Notary stuff.

module RSCoin.Notary.Launcher
        ( launchNotaryReal
        ) where

import           Control.Monad.Catch                  (bracket)
import           Control.Monad.Trans                  (MonadIO, liftIO)
import           Network.Wai                          (Middleware)
import           Network.Wai.Handler.Warp             (run)
import           Network.Wai.Middleware.RequestLogger (logStdout, logStdoutDev)

import           RSCoin.Core                          (Severity (..),
                                                       notaryLoggerName)
import           RSCoin.Notary.AcidState              (RSCoinNotaryState,
                                                       closeState, openMemState,
                                                       openState)
import           RSCoin.Notary.Server                 (serveNotary)
import           RSCoin.Notary.Web.Servant            (servantApp)
import           RSCoin.Timed                         (fork_,
                                                       runRealModeUntrusted)

launchNotaryReal :: Severity -> Maybe FilePath -> Maybe FilePath -> Int -> IO ()
launchNotaryReal logSeverity dbPath confPath webPort = do
    let openAction = maybe openMemState openState dbPath
    runRealModeUntrusted notaryLoggerName confPath $
        bracket (liftIO openAction) (liftIO . closeState) $
        \st -> do
            fork_ $ serveNotary st
            launchWeb webPort logSeverity st

loggingMiddleware :: Severity -> Middleware
loggingMiddleware Debug = logStdoutDev
loggingMiddleware Info  = logStdout
loggingMiddleware _     = id

launchWeb
    :: MonadIO m
    => Int -> Severity -> RSCoinNotaryState -> m ()
launchWeb port sev st =
    liftIO . run port . loggingMiddleware sev . servantApp $ st
