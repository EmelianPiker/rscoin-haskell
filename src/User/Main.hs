{-# LANGUAGE ScopedTypeVariables #-}

import           Control.Monad.Catch (MonadCatch, bracket, catch, throwM)
import           Control.Monad.Trans (MonadIO)
import qualified Data.Text           as T

import qualified RSCoin.Core         as C
import           RSCoin.Timed        (ContextArgument (CACustomLocation, CADefault),
                                      runRealModeUntrusted)
import           RSCoin.Timed        (WorkMode, getNodeContext)
import qualified RSCoin.User         as U
import qualified RSCoin.User.Wallet  as W

import           Actions             (initializeStorage, processCommand)
import qualified UserOptions         as O

main :: IO ()
main = do
    opts@O.UserOptions{..} <- O.getUserOptions
    C.initLogging logSeverity
    let ctxArg =
            if defaultContext
                then CADefault
                else CACustomLocation configPath
    runRealModeUntrusted C.userLoggerName ctxArg $
        bracket (U.openState rebuildDB walletPath) U.closeState $
        \st -> do
            C.logDebug $
                mconcat ["Called with options: ", (T.pack . show) opts]
            handleUnitialized
                (processCommand st userCommand opts)
                (initializeStorage st opts)
  where
    handleUnitialized
        :: (MonadIO m, MonadCatch m, C.WithNamedLogger m)
        => m () -> m () -> m ()
    handleUnitialized action initialization =
        action `catch` handler initialization action
      where
        handler i a W.NotInitialized =
            C.logInfo "Initalizing storage..." >> i >> a
        handler _ _ e = throwM e
