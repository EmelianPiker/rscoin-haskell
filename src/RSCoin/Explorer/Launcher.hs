-- | Convenience functions to launch explorer or do high-level operations
-- with it.

module RSCoin.Explorer.Launcher
       ( explorerWrapperReal
       , launchExplorerReal
       , launchExplorer
       , launchWeb
       ) where

import           Control.Monad.Catch                  (bracket)
import           Control.Monad.Trans                  (MonadIO (liftIO))

import           Network.Wai                          (Middleware)
import           Network.Wai.Handler.Warp             (run)
import           Network.Wai.Middleware.RequestLogger (logStdout, logStdoutDev)

import           RSCoin.Core                          (SecretKey, Severity (..),
                                                       initLoggerByName)
import           RSCoin.Timed                         (MsgPackRpc, WorkMode,
                                                       fork_,
                                                       runRealModeUntrusted)

import           RSCoin.Explorer.AcidState            (State, closeState,
                                                       openState)
import           RSCoin.Explorer.Channel              (Channel, newChannel)
import           RSCoin.Explorer.Server               (serve)
import qualified RSCoin.Explorer.Web                  as Web

explorerWrapperReal :: FilePath
                    -> Maybe FilePath
                    -> (State -> MsgPackRpc a)
                    -> IO a
explorerWrapperReal storagePath confPath =
    runRealModeUntrusted confPath .
    bracket (liftIO $ openState storagePath) (liftIO . closeState)

launchExplorerReal :: Int
                   -> Int
                   -> Severity
                   -> FilePath
                   -> Maybe FilePath
                   -> SecretKey
                   -> IO ()
launchExplorerReal portRpc portWeb severity storagePath confPath sk = do
    channel <- newChannel
    explorerWrapperReal storagePath confPath $
        \st ->
             do fork_ $ launchExplorer portRpc sk channel st
                launchWeb portWeb severity channel st

launchExplorer
    :: WorkMode m
    => Int -> SecretKey -> Channel -> State -> m ()
launchExplorer port sk ch st = serve port ch st sk

loggingMiddleware :: Severity -> Middleware
loggingMiddleware Debug = logStdoutDev
loggingMiddleware Info = logStdout
loggingMiddleware _ = id

launchWeb
    :: MonadIO m
    => Int -> Severity -> Channel -> State -> m ()
launchWeb port sev ch st = do
    app <- Web.mkApplication ch st
    liftIO $ initLoggerByName sev Web.wsLoggerName
    liftIO . run port . loggingMiddleware sev $ app
