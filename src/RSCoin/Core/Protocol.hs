{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE Rank2Types       #-}
{-# OPTIONS_GHC -fno-warn-missing-signatures #-}

-- | Protocol implements all low level communication between
-- entities (User, Bank, Mintette).

module RSCoin.Core.Protocol
       ( BankMethod (..)
       , DumpMethod (..)
       , MintetteMethod (..)
       , RSCoinMethod (..)
       , SignerMethod (..)
       , WithResult
       , Server
       , T.Client
       , method
       , T.serve
       , call
       , execBank
       , execBankSafe
       , execMintette
       , execMintetteSafe
       , execSigner
       , callBank
       , callBankSafe
       , callMintette
       , callMintetteSafe
       , callSigner
       , unCps
       ) where

import           Control.Monad.IO.Class  (MonadIO, liftIO)
import qualified Data.ByteString.Char8   as BS
import           Data.IORef              (newIORef, readIORef, writeIORef)
import           Data.Maybe              (fromJust)

import           Data.MessagePack        (MessagePack)

import           RSCoin.Core.Constants   (bankPort, rpcTimeout)
import           RSCoin.Core.Crypto      ()
import           RSCoin.Core.MessagePack ()
import           RSCoin.Core.Types       (Mintette (..))
import qualified RSCoin.Timed            as T

-- TODO: this module should provide more safety and expose better api

-- | Requests used in RSCoin transport layer.
data RSCoinMethod
    = RSCBank     BankMethod
    | RSCMintette MintetteMethod
    | RSCDump     DumpMethod
    | RSCSign     SignerMethod
    deriving (Show)

-- | Requests processed by a Bank.
data BankMethod
    = GetMintettes
    | GetAddresses
    | GetBlockchainHeight
    | GetHBlock
    | GetTransaction
    | FinishPeriod
    deriving (Show)

-- | Requests processed by a Mintette.
data MintetteMethod
    = PeriodFinished
    | AnnounceNewPeriod
    | CheckTx
    | CommitTx
    deriving (Show)

-- | Requests for dumping state.
data DumpMethod
    = GetHBlocks
    | GetLogs
    | GetMintetteUtxo
    | GetMintetteBlocks
    | GetMintetteLogs
    deriving (Show)

-- | Requests for multisign transactions.
data SignerMethod
    = SignTransaction
    deriving (Show)

type Server a = T.Server a

-- | Create server method.
method :: T.MethodType m f => RSCoinMethod -> f -> T.Method m
method m = T.method (show m)

--call :: RpcType a => RSCoinMethod -> a
-- FIXME: RpcType isn't exported so my idea of using Show RSCoinMethod for method name
-- doesn't hold any more
-- | Call RSCoinMethod.
call m = T.call (show m)

-- TODO: this can be modeled with Cont monad
-- | Continuation passing style transformation.
-- For more see: https://en.wikibooks.org/wiki/Haskell/Continuation_passing_style
type WithResult a = forall m . T.WorkMode m => (a -> m ()) -> m ()

-- | Send a request to a Bank using Continuation passing style (CPS).
execBank :: MessagePack a => T.Client a -> WithResult a
execBank = (>>=) . callBank

-- | Send a request to a Mintette using Continuation passing style (CPS).
execMintette :: MessagePack a => Mintette -> T.Client a -> WithResult a
execMintette m = (>>=) . callMintette m

-- | Send a request to a Bank using Continuation passing style (CPS).
-- Rises an exception if Bank doesn't respond in rpcTimeout time.
execBankSafe :: MessagePack a => T.Client a -> WithResult a
execBankSafe = (>>=) . callBankSafe

-- | Send a request to a Mintette using Continuation passing style (CPS).
-- Rises an exception if Mintette doesn't respond in rpcTimeout time.
execMintetteSafe :: MessagePack a => Mintette -> T.Client a -> WithResult a
execMintetteSafe m = (>>=) . callMintetteSafe m

-- | Send request to Signer.
execSigner :: MessagePack a => T.Client a -> WithResult a
execSigner = (>>=) . callSigner

-- | Send a request to a Bank.
callBank :: (MessagePack a, T.WorkMode m) => T.Client a -> m a
callBank action = do
    bankHost <- T.getHost <$> T.getBankSettings
    T.execClient (bankHost, bankPort) action

-- | Send a request to a Mintette.
callMintette :: (MessagePack a, T.WorkMode m)
             => Mintette -> T.Client a -> m a
callMintette Mintette {..} action =
    T.execClient (BS.pack mintetteHost, mintettePort) action

-- | Send a request to a Bank.
-- Rises an exception if Bank doesn't respond in rpcTimeout time.
callBankSafe :: (MessagePack a, T.WorkMode m) => T.Client a -> m a
callBankSafe action = do
    bankHost <- T.getHost <$> T.getBankSettings
    T.execClientTimeout rpcTimeout (bankHost, bankPort) action

-- | Send a request to a Mintette.
-- Rises an exception if Mintette doesn't respond in rpcTimeout time.
callMintetteSafe :: (MessagePack a, T.WorkMode m)
             => Mintette -> T.Client a -> m a
callMintetteSafe Mintette {..} action =
    T.execClientTimeout rpcTimeout (BS.pack mintetteHost, mintettePort) action

-- TODO: TEMRORAL SOLUTION
signerHost = "127.0.0.1"
signerPort = 1234

callSigner :: (MessagePack a, T.WorkMode m) => T.Client a -> m a
callSigner action = T.execClientTimeout rpcTimeout (signerHost, signerPort) action

-- | Reverse Continuation passing style (CPS) transformation
unCps :: forall a m . MonadIO m => ((a -> m ()) -> m ()) -> m a
unCps withResult = do
    ref <- liftIO $ newIORef Nothing
    withResult $ liftIO . writeIORef ref . Just
    fromJust <$> liftIO (readIORef ref)
