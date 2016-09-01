{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE FlexibleInstances         #-}
{-# LANGUAGE RankNTypes                #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE TemplateHaskell           #-}
{-# LANGUAGE TupleSections             #-}
{-# LANGUAGE TypeSynonymInstances      #-}

-- | HSpec specification of Storages.

module Test.RSCoin.Pure.StorageSpec
       ( spec
       ) where

import           Control.Exception              (Exception)
import           Control.Lens                   (at, ix, makeLenses, preuse,
                                                 use, view, (+=), (.=), (^.),
                                                 _1, _3)
import           Control.Monad                  (forM, when)
import           Control.Monad.Catch            (MonadThrow (throwM))
import           Control.Monad.State.Lazy       (gets)
import           Data.List                      (elemIndex)
import qualified Data.Map                       as M
import           Data.Maybe                     (fromJust)
import           Data.Text                      (Text)
import           Data.Typeable                  (Typeable)
import           Test.Hspec                     (Spec, describe)
import           Test.Hspec.QuickCheck          (prop)
import           Test.QuickCheck                (Arbitrary (arbitrary), Gen,
                                                 frequency)

import qualified RSCoin.Bank.Error              as B
import qualified RSCoin.Bank.Storage            as B
import qualified RSCoin.Core                    as C
import qualified RSCoin.Mintette.Error          as M
import qualified RSCoin.Mintette.Storage        as M

import           Test.RSCoin.Core.Arbitrary     ()
import qualified Test.RSCoin.Pure.BankState     as B
import qualified Test.RSCoin.Pure.MintetteState as M
import qualified Test.RSCoin.Pure.Update        as T

-- @TODO: duplicate with Test.RSCoin.Full.Error
data TestError
    = TestError Text
    deriving (Show, Typeable, Eq)

instance Exception TestError

data RSCoinState = RSCoinState
    { _bankState        :: B.BankState
    , _mintettesState   :: M.Map C.Mintette M.MintetteState
    , _availableOutputs :: [(C.SecretKey, C.AddrId)]
    , _periodId         :: C.PeriodId   -- FIXME: periodId may be taken from BankState, remove it!
    } deriving (Show)

$(makeLenses ''RSCoinState)

testNodeContext :: C.NodeContext
testNodeContext = C.defaultNodeContextWithLogger C.testingLoggerName

spec :: Spec
spec =
    describe "Storage" $ do
        prop "something happens when transaction is sent and period finishes"
            sendTxAndFinishPeriod

type Update = T.Update C.RSCoinError RSCoinState
type UpdateVoid = Update ()

class CanUpdate a where
    doUpdate :: a -> UpdateVoid

data SomeUpdate = forall a . CanUpdate a => SomeUpdate a

instance CanUpdate SomeUpdate where
    doUpdate (SomeUpdate upd) = doUpdate upd

data EmptyUpdate = EmptyUpdate
    deriving Show

instance Arbitrary EmptyUpdate where
    arbitrary = pure EmptyUpdate

instance CanUpdate EmptyUpdate where
    doUpdate _ = return ()

data AddMintette =
    AddMintette C.Mintette
                (C.SecretKey, C.PublicKey)
                M.MintetteState
    deriving (Show)

instance Arbitrary AddMintette where
    arbitrary = do
        mId <- arbitrary
        mintette <- arbitrary
        sk <- arbitrary
        return $ AddMintette mId (sk, C.derivePublicKey sk) mintette

instance CanUpdate AddMintette where
    doUpdate (AddMintette mId (_, pk) mintette) = do
        liftBankUpdate $ B.addMintette mId pk
        mintettesState . at mId .= Just mintette

data StartNewPeriod = StartNewPeriod
    deriving Show

instance Arbitrary StartNewPeriod where
    arbitrary = pure StartNewPeriod

-- NOTE: this is reimplementation of Bank.Worker
instance CanUpdate StartNewPeriod where
    doUpdate _ = do
        mintettes <- use $ bankState . B.bankStorage . B.getMintettes
        pId <- use $ bankState . B.bankStorage . B.getPeriodId
        bankSk <- use $ bankState . B.bankKey
        periodResults <-
            forM mintettes $
            \mId ->
                 do mSk <- preuse $ mintettesState . ix mId . M.mintetteKey
                    maybe
                        (throwM $ TestError "No mintettes secret key")
                        (liftMintetteUpdate mId . flip M.finishPeriod pId)
                        mSk
        (bankPk, genesisAddr) <-
            liftA2 (,) (^. C.bankPublicKey) (^. C.genesisAddress) testNodeContext
        newPeriodData <-
            liftBankUpdate . B.startNewPeriod bankPk genesisAddr bankSk $ map Just periodResults
        newMintettes <- use $ bankState . B.bankStorage . B.getMintettes
        mapM_
            (\(m,mId) ->
                  do when (length newPeriodData < mId) $
                         throwM $ TestError "No such mintette"
                     liftMintetteUpdate m $
                         M.startPeriod (newPeriodData !! mId))
            (zip newMintettes [0 ..])
        periodId += 1

-- Only 1-to-1 transactions are supported here at this point.
data SendGoodTransaction = SendGoodTransaction
    { sgtInputIdx        :: Word
    , sgtOutputSecretKey :: C.SecretKey
    } deriving (Show)

instance Arbitrary SendGoodTransaction where
    arbitrary = SendGoodTransaction <$> arbitrary <*> arbitrary

instance CanUpdate SendGoodTransaction where
    doUpdate SendGoodTransaction{..} = do
        mts <- use mintettesState
        outputs <- use availableOutputs
        bankMintettes <- use $ bankState . B.bankStorage . B.getMintettes
        let actualIdx = (fromIntegral sgtInputIdx `mod` length outputs)
            (sk,addrId) = outputs !! actualIdx
            tx =
                C.Transaction
                    [addrId]
                    [ ( C.Address $ C.derivePublicKey sgtOutputSecretKey
                      , view _3 addrId)]
            signature = C.sign sk tx
            ownersIn =
                map (flip M.elemAt mts) $ C.owners (M.toList mts) (view _1 addrId)
            getConfirmation (m,ms) = do
                addr <- fromJust <$> use (bankState . B.bankStorage . B.getAddressFromUtxo addrId)
                confirmation <-
                    liftMintetteUpdate m $
                    M.checkNotDoubleSpent
                        (ms ^. M.mintetteKey)
                        tx
                        addrId
                        [(addr, signature)]
                return
                    ( (fromJust $ elemIndex m bankMintettes, addrId)
                    , confirmation)
            ownersOut =
                map (flip M.elemAt mts) $ C.owners (M.toList mts) (C.hash tx)
        confirmations <- mapM getConfirmation ownersIn
        let commitTx (m,ms) =
                liftMintetteUpdate m $ M.commitTx (ms ^. M.mintetteKey) tx $
                M.fromList confirmations
        mapM_ commitTx ownersOut
        availableOutputs . ix actualIdx .=
            (sgtOutputSecretKey, (C.hash tx, 0, view _3 addrId))

instance Arbitrary SomeUpdate where
    arbitrary =
        frequency
            [ (1, SomeUpdate <$> (arbitrary :: Gen EmptyUpdate))
            , (10, SomeUpdate <$> (arbitrary :: Gen AddMintette))
            , (10, SomeUpdate <$> (arbitrary :: Gen StartNewPeriod))
            , (100, SomeUpdate <$> (arbitrary :: Gen SendGoodTransaction))
            ]

instance Arbitrary RSCoinState where
    arbitrary = do
        bank <- arbitrary
        updates :: [SomeUpdate] <- arbitrary
        return . T.execUpdate (sequence_ . map doUpdate $ updates) $
            RSCoinState bank M.empty [genesisOutput] 0
      where
        genesisAddress = testNodeContext ^. C.genesisAddress
        genesisOutput =
            ( bankSecretKey
            , ( C.hash $ C.initialTx genesisAddress
              , 0
              , C.genesisValue
              )
            )
        bankSecretKey = C.testBankSecretKey

-- TODO: there must be a better way to write this (in more lens style)
liftBankUpdate :: T.Update B.BankError B.Storage a -> T.Update C.RSCoinError RSCoinState a
liftBankUpdate upd = do
    bank <- gets $ B._bankStorage . _bankState
    (res, newBank) <- T.runUpdateSafe upd bank
    bankState . B.bankStorage .= newBank
    return res

-- liftUserUpdate :: T.Update U.UserError U.WalletStorage a -> T.Update C.RSCoinError RSCoinState a
-- liftUserUpdate upd = do
--     user <- gets $ U._userStorage . _userState
--     (res, newUser) <- T.runUpdateSafe upd user
--     userState . U.userStorage .= newUser
--     return res

liftMintetteUpdate :: C.Mintette -> T.Update M.MintetteError M.Storage a -> T.Update C.RSCoinError RSCoinState a
liftMintetteUpdate mintette upd = do
    mMintette <- gets (fmap M._mintetteStorage . M.lookup mintette . _mintettesState)
    mRes <- return $ mMintette >>= T.runUpdateSafe upd
    maybe (throwM $ TestError "No mintette") updateMintette mRes
    -- FIXME: return Maybe a instead of error ?
  where
    updateMintette (ret, newStorage) = do
        mintettesState . ix mintette . M.mintetteStorage .= newStorage
        return ret

sendTxAndFinishPeriod :: SendGoodTransaction -> StartNewPeriod -> RSCoinState -> Bool
sendTxAndFinishPeriod sendTx startNewPeriod st = const True st'
  where
    st' = T.execUpdate (doUpdate sendTx >> doUpdate startNewPeriod) st
