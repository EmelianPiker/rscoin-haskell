{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE Rank2Types       #-}
{-# LANGUAGE TemplateHaskell  #-}

-- | Storage for mintette's data.

module RSCoin.Signer.Storage
        ( Storage
        , emptySignerStorage
        , signedTxs
        ) where

import           Control.Lens (makeLenses)
import           Data.Set     (Set)
import qualified Data.Set     as S

import           RSCoin.Core  (Transaction)

data Storage = Storage
    { _signedTxs :: Set Transaction  -- ^ Signed transactions
    } deriving Show

$(makeLenses ''Storage)

emptySignerStorage :: Storage
emptySignerStorage = Storage S.empty