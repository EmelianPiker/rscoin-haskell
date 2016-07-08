{-# LANGUAGE FlexibleContexts #-}

import qualified Data.Text       as T
import           Data.Time.Units (Second)

import qualified Options         as Opts
import qualified RSCoin.Bank     as B
import           RSCoin.Core     (Address (Address), Mintette (Mintette),
                                  bankLoggerName, constructPublicKey,
                                  defaultLayout', initLogging,
                                  keyGen, logWarning, readPublicKey,
                                  readSecretKey)

main :: IO ()
main = do
    Opts.Options{..} <- Opts.getOptions
    initLogging cloLogSeverity
    -- @TODO make Notary addr, bankPort configurable
    let layout = defaultLayout' "127.0.0.1"
    case cloCommand of
        Opts.AddAddress pk' strategy -> do
            addr <- Address <$> maybe (snd <$> keyGen) readPk pk'
            B.addAddressIO cloPath addr strategy
        Opts.AddMintette name port pk -> do
            let m = Mintette name port
            k <-
                maybe (readPublicKeyFallback pk) return $ constructPublicKey pk
            B.addMintetteIO cloPath m k
        Opts.Serve skPath -> do
            let periodDelta = fromInteger cloPeriodDelta :: Second
            B.launchBankReal layout periodDelta cloPath =<< readSecretKey skPath
  where
    readPk pk = maybe (readPublicKeyFallback pk) return (constructPublicKey pk)
    readPublicKeyFallback pk = do
        logWarning
            bankLoggerName
            "Failed to parse public key, trying to interpret as a filepath to key"
        readPublicKey $ T.unpack pk
