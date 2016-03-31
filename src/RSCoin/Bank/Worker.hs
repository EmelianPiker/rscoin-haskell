{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE ScopedTypeVariables #-}

-- | Worker that handles end of period.

module RSCoin.Bank.Worker
       ( runWorker
       ) where


import           Control.Concurrent       (forkFinally, threadDelay)
import           Control.Exception        (SomeException, catch)
import           Control.Monad            (void)
import           Data.Acid                (createCheckpoint, query, update)
import           Data.IORef               (modifyIORef, newIORef, readIORef)
import           Data.List                (intersperse)
import           Data.Monoid              ((<>))
import           Data.Text.Buildable      (Buildable (build))
import           Data.Time.Units          (toMicroseconds)

import           Serokell.Util.Exceptions ()
import           Serokell.Util.Text       (formatSingle')

import           RSCoin.Core              (Mintettes, NewPeriodData, PeriodId,
                                           PeriodResult, SecretKey,
                                           announceNewPeriod, logError, logInfo,
                                           logWarning, periodDelta,
                                           sendPeriodFinished)

import           RSCoin.Bank.AcidState    (GetMintettes (..), GetPeriodId (..),
                                           StartNewPeriod (..), State)

-- | Start worker which runs appropriate action when a period finishes
runWorker :: SecretKey -> State -> IO ()
runWorker sk st =
    foreverE $
    do onPeriodFinished sk st
       threadDelay (fromIntegral $ toMicroseconds periodDelta)
  where
    foreverE f = void $ forkFinally f $ handler $ foreverE f
    handler f (Left (e :: SomeException)) = do
        logError $
            formatSingle'
                "Error was caught by worker, restarting in 1 minute: {}"
                e
        threadDelay $ 1 * 60 * 1000 * 1000
        f
    handler f (Right _) = f

instance Buildable [NewPeriodData] where
    build xs = "[" <> mconcat (intersperse "," $ map build xs) <> "]"

onPeriodFinished :: SecretKey -> State -> IO ()
onPeriodFinished sk st = do
    mintettes <- query st GetMintettes
    pId <- query st GetPeriodId
    logInfo $ formatSingle' "Period {} has just finished!" pId
    -- Mintettes list is empty before the first period, so we'll simply
    -- get [] here in this case (and it's fine).
    periodResults <- getPeriodResults mintettes pId
    newPeriodData <- update st $ StartNewPeriod sk periodResults
    createCheckpoint st
    newMintettes <- query st GetMintettes
    mapM_
        (\(m,mId) ->
              announceNewPeriod m (newPeriodData !! mId) `catch`
              handlerAnnouncePeriod)
        (zip newMintettes [0 ..])
    logInfo $
        formatSingle'
            "Announced new period with the following data:\n{}"
            newPeriodData
  where
    -- TODO: catch appropriate exception according to protocol
    -- implementation (here and below)
    handlerAnnouncePeriod (e :: SomeException) =
        logWarning $
            formatSingle' "Error occurred in communicating with mintette {}" e

getPeriodResults :: Mintettes -> PeriodId -> IO [Maybe PeriodResult]
getPeriodResults mts pId = do
    res <- newIORef []
    mapM_ (f res) mts
    readIORef res
  where
    f res mintette =
        sendPeriodFinished
            mintette
            pId
            (\pr ->
                  modifyIORef res (Just pr :)) `catch`
        handler res
    handler res (e :: SomeException) = do
        logWarning $
            formatSingle' "Error occurred in communicating with mintette {}" e
        modifyIORef res (Nothing :)
