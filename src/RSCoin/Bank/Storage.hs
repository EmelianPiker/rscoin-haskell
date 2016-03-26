{-# LANGUAGE Rank2Types      #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Storage for Bank data

module RSCoin.Bank.Storage
       ( Storage
       , mkStorage
       , getMintettes
       , getPeriodId
       , addMintette
       , startNewPeriod
       ) where

import           Control.Lens               (Getter, makeLenses, use, (%=),
                                             (+=), (.=))
import           Control.Monad              (guard, unless)
import           Control.Monad.State        (State)
import           Control.Monad.Trans.Except (ExceptT, throwE)
import           Data.Typeable              (Typeable)
import           Safe                       (headMay)

import           RSCoin.Core                (ActionLog, Dpk, HBlock (..),
                                             Mintette, Mintettes, PeriodId,
                                             PeriodResult, PublicKey, SecretKey,
                                             checkActionLog, checkLBlock,
                                             mkGenesisHBlock, sign)

import           RSCoin.Bank.Error          (BankError (BEInternal))

-- | Storage contains all the data used by Bank
data Storage = Storage
    { _mintettes        :: Mintettes
    , _pendingMintettes :: [(Mintette, PublicKey)]
    , _periodId         :: PeriodId
    , _blocks           :: [HBlock]
    , _dpk              :: Dpk
    , _actionLogs       :: [ActionLog]
    } deriving (Typeable)

$(makeLenses ''Storage)

-- | Make empty storage
mkStorage :: Storage
mkStorage = Storage [] [] 0 [] [] []

type Query a = Getter Storage a

getMintettes :: Query Mintettes
getMintettes = mintettes

getPeriodId :: Query PeriodId
getPeriodId = periodId

type Update = State Storage
type ExceptUpdate = ExceptT BankError (State Storage)

-- | Add given mintette to storage and associate given key with it.
addMintette :: Mintette -> PublicKey -> Update ()
addMintette m k = pendingMintettes %= ((m, k):)

-- | When period finishes, Bank receives period results from mintettes,
-- updates storage and starts new period with potentially different set
-- of mintettes.
startNewPeriod :: SecretKey -> [Maybe PeriodResult] -> ExceptUpdate ()
startNewPeriod sk results = do
    mts <- use mintettes
    unless (length mts == length results) $
        throwE $
        BEInternal
            "Length of results is different from the length of mintettes"
    pId <- use periodId
    startNewPeriodDo sk pId results

startNewPeriodDo :: SecretKey
                 -> PeriodId
                 -> [Maybe PeriodResult]
                 -> ExceptUpdate ()
startNewPeriodDo sk 0 _ = do
    startNewPeriodFinally sk [] mkGenesisHBlock
startNewPeriodDo sk pId results = do
    lastHBlock <- head <$> use blocks
    curDpk <- use dpk
    logs <- use actionLogs
    let keys = map fst curDpk
    unless (length keys == length results) $
        throwE $
        BEInternal "Length of keys is different from the length of results"
    let checkedResults = map (checkResult pId lastHBlock) $ zip3 results keys logs
    undefined

startNewPeriodFinally :: SecretKey
                      -> [Int]
                      -> (SecretKey -> Dpk -> HBlock)
                      -> ExceptUpdate ()
startNewPeriodFinally sk goodMintettes newBlockCtor = do
    periodId += 1
    updateMintettes sk goodMintettes
    newBlock <- newBlockCtor sk <$> use dpk
    blocks %= (newBlock:)

checkResult :: PeriodId
            -> HBlock
            -> (Maybe PeriodResult, PublicKey, ActionLog)
            -> Maybe PeriodResult
checkResult expectedPid lastHBlock (r, key, storedLog) = do
    (pId, lBlocks, actionLog) <- r
    guard $ pId == expectedPid
    guard $ checkActionLog (headMay storedLog) actionLog
    mapM_ (guard . checkLBlock key (hbHash lastHBlock) actionLog) lBlocks
    r

updateMintettes :: SecretKey -> [Int] -> ExceptUpdate ()
updateMintettes sk goodMintettes = do
    existing <- use mintettes
    pending <- use pendingMintettes
    mintettes .= map (existing !!) goodMintettes ++ map fst pending
    currentDpk <- use dpk
    dpk .= map (currentDpk !!) goodMintettes ++ map doSign pending
    currentLogs <- use actionLogs
    actionLogs .= map (currentLogs !!) goodMintettes ++
        replicate (length pending) []
  where
    doSign (_,mpk) = (mpk, sign sk mpk)