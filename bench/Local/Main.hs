{-# LANGUAGE DataKinds       #-}
{-# LANGUAGE DeriveGeneric   #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TypeOperators   #-}

module Main where

import           Control.Concurrent              (forkIO, threadDelay)
import           Control.Concurrent.Async        (forConcurrently)
import           Control.Monad                   (forM_, replicateM, void)
import           Data.Int                        (Int64)
import           Data.Maybe                      (fromMaybe)
import           Data.String                     (IsString)
import           Data.Time.Units                 (Second)
import           Formatting                      (build, int, sformat, (%))
import           System.IO.Temp                  (withSystemTempDirectory)
-- workaround to make stylish-haskell work :(
import           Options.Generic

import           RSCoin.Core                     (PublicKey, SecretKey,
                                                  Severity (..), bankSecretKey,
                                                  defaultPeriodDelta,
                                                  finishPeriod, initLogging,
                                                  keyGen)
import           RSCoin.Timed                    (runRealModeLocal)
import           RSCoin.User.Wallet              (UserAddress)

import           Bench.RSCoin.FilePathUtils      (tempBenchDirectory)
import           Bench.RSCoin.Local.InfraThreads (addMintette, bankThread,
                                                  mintetteThread)
import           Bench.RSCoin.Logging            (initBenchLogger, logInfo)
import           Bench.RSCoin.UserLogic          (benchUserTransactions,
                                                  initializeBank,
                                                  initializeUser, userThread)
import           Bench.RSCoin.Util               (ElapsedTime, measureTime_)

data BenchOptions = BenchOptions
    { users         :: Int            <?> "number of users"
    , transactions  :: Maybe Word     <?> "number of transactions per user"
    , mintettes     :: Int            <?> "number of mintettes"
    , severity      :: Maybe Severity <?> "severity for global logger"
    , benchSeverity :: Maybe Severity <?> "severity for bench logger"
    , period        :: Maybe Word     <?> "period delta (seconds)"
    } deriving (Generic, Show)

instance ParseField  Word
instance ParseField  Severity
instance ParseFields Severity
instance ParseRecord Severity
instance ParseRecord BenchOptions

type KeyPairList = [(SecretKey, PublicKey)]

bankHost :: IsString s => s
bankHost = "127.0.0.1"

generateMintetteKeys :: Word -> IO KeyPairList
generateMintetteKeys = flip replicateM keyGen . fromIntegral

runMintettes :: FilePath -> KeyPairList -> IO ()
runMintettes benchDir secretKeys
    = forM_ (zip [1..] secretKeys) $ \(mintetteId, (secretKey, publicKey)) -> do
        addMintette mintetteId benchDir publicKey
        void $ forkIO $ mintetteThread mintetteId benchDir secretKey

establishMintettes :: FilePath -> Word -> IO ()
establishMintettes benchDir mintettesNumber = do
    keyPairs <- generateMintetteKeys mintettesNumber
    logInfo $ sformat ("Running " % int % " mintettes…") mintettesNumber
    runMintettes benchDir keyPairs
    logInfo $ sformat (int % " mintettes are launched") mintettesNumber
    threadDelay $ 2 * 10 ^ (6 :: Int)

establishBank :: FilePath -> Second -> IO ()
establishBank benchDir periodDelta = do
    logInfo "Running bank..."
    _ <- forkIO $ bankThread periodDelta benchDir
    logInfo "Bank is launched"
    threadDelay $ 2 * 10 ^ (6 :: Int)

initializeUsers :: FilePath -> [Int64] -> IO [UserAddress]
initializeUsers benchDir userIds = do
    let initUserAction = userThread bankHost benchDir initializeUser
    logInfo $ sformat ("Initializing " % int % " users…") $ length userIds
    mapM initUserAction userIds

initializeSuperUser :: Word -> FilePath -> [UserAddress] -> IO ()
initializeSuperUser txNum benchDir userAddresses = do
    let bankId = 0
    logInfo "Initializaing user in bankMode…"
    userThread
        bankHost
        benchDir
        (const $ initializeBank txNum userAddresses)
        bankId
    logInfo
        "Initialized user in bankMode, finishing period"
    runRealModeLocal $ finishPeriod bankSecretKey
    threadDelay $ 1 * 10 ^ (6 :: Int)

runTransactions :: Word
                -> FilePath
                -> [UserAddress]
                -> [Int64]
                -> IO ElapsedTime
runTransactions txNum benchDir userAddresses userIds = do
    let benchUserAction =
            userThread bankHost benchDir $
            benchUserTransactions txNum userAddresses
    logInfo "Running transactions…"
    measureTime_ $ forConcurrently userIds benchUserAction

main :: IO ()
main = do
    BenchOptions{..} <- getRecord "rscoin-user-bench"
    let mintettesNumber = fromIntegral $ unHelpful mintettes
        userNumber      = unHelpful users
        txNum           = fromMaybe 1000  $ unHelpful transactions
        globalSeverity  = fromMaybe Error $ unHelpful severity
        bSeverity       = fromMaybe Info  $ unHelpful benchSeverity
        periodDelta     = fromMaybe defaultPeriodDelta $
                          fromIntegral <$> unHelpful period
    withSystemTempDirectory tempBenchDirectory $ \benchDir -> do
        initLogging globalSeverity
        initBenchLogger bSeverity

        establishMintettes benchDir mintettesNumber
        establishBank      benchDir periodDelta

        let userIds    = [1 .. fromIntegral userNumber]
        userAddresses <- initializeUsers benchDir userIds
        initializeSuperUser txNum benchDir userAddresses

        logInfo . sformat ("Elapsed time: " % build) =<<
            runTransactions txNum benchDir userAddresses userIds
