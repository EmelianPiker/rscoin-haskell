{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE RecordWildCards   #-}
{-# LANGUAGE TemplateHaskell   #-}

-- | The most basic primitives from the paper.

module RSCoin.Core.Primitives
       ( Color
       , Coin (..)
       , Address (..)
       , AddrId
       , Transaction (..)
       , TransactionId
       ) where

import           Data.Binary         (Binary (get, put))
import           Data.Hashable       (Hashable (hashWithSalt))
import           Data.Maybe          (catMaybes, fromMaybe)
import           Data.SafeCopy       (base, deriveSafeCopy)
import qualified Data.Text           as T
import           Data.Text.Buildable (Buildable (build))
import qualified Data.Text.Format    as F
import           Formatting          (bprint, float, int, (%))

import           Serokell.Util.Text  (listBuilderJSON, pairBuilder,
                                      tripleBuilder)

import           RSCoin.Core.Crypto  (Hash, PublicKey, constructPublicKey,
                                      printPublicKey)

type Color = Int

-- | Coin is the least possible unit of currency.
-- We use very simple model at this point.
data Coin = Coin
    { getColor :: Color
    , getCoin  :: Rational
    } deriving (Show, Eq)

reportError :: String -> Coin -> Coin -> a
reportError s c1 c2 =
        error $ "Error: " ++ s ++
                " of coins with different colors: " ++
                show c1 ++ " " ++ show c2

instance Ord Coin where
    compare (Coin _ a1) (Coin _ a2)
        | otherwise    = compare a1 a2
--    -- is this instance better?
--    compare c1@(Coin col1 a1) c2@(Coin col2 a2)
--        | col1 /= col2 = reportError "comprison" c1 c2
--        | otherwise    = compare a1 a2

instance Binary Coin where
    put Coin{..} = put (getColor, getCoin)
    get = uncurry Coin <$> get

instance Hashable Coin where
    hashWithSalt s Coin{..} = hashWithSalt s (getColor, getCoin)

instance Buildable Coin where
    build (Coin col c) =
        bprint (float % " coin(s) of color " % int) valueDouble col
      where
        valueDouble :: Double
        valueDouble = fromRational c

instance Num Coin where
    (+) c1@(Coin col c) c2@(Coin col' c')
      | col == col' = Coin col (c + c')
      | otherwise = reportError "sum" c1 c2
    (*) c1@(Coin col c) c2@(Coin col' c')
      | col == col' = Coin col (c * c')
      | otherwise = reportError "product" c1 c2
    (-) c1@(Coin col c) c2@(Coin col' c')
      | col == col' = Coin col (c - c')
      | otherwise = reportError "subtraction" c1 c2
    abs (Coin a b) = Coin a (abs b)
    signum (Coin col c) = Coin col (signum c)
    fromInteger c = Coin 0 (fromInteger c)

-- | Address can serve as input or output to transactions.
-- It is simply a public key.
newtype Address = Address
    { getAddress :: PublicKey
    } deriving (Ord, Buildable, Binary, Eq, Hashable)

instance Show Address where
    show (Address pk) = "Address " ++ printPublicKey pk
instance Read Address where
    readsPrec i = catMaybes . map (\(k, s) -> flip (,) s . Address <$> constructPublicKey (removePrefix k)) . readsPrec i
      where removePrefix t = fromMaybe t $ T.stripPrefix (T.pack "Address ") t

-- | AddrId identifies usage of address as output of transaction.
-- Basically, it is tuple of transaction identifier, index in list of outputs
-- and associated value.
type AddrId = (TransactionId, Int, Coin)

instance Buildable (TransactionId, Int, Coin) where
    build (t,i,c) =
        mconcat
            [ "Addrid { transactionId="
            , build t
            , ", index="
            , build i
            , ", coins="
            , build c
            , " }"]

-- | Transaction represents act of transfering units of currency from
-- set of inputs to set of outputs.
data Transaction = Transaction
    { txInputs  :: ![AddrId]
    , txOutputs :: ![(Address, Coin)]
    } deriving (Show, Eq)

instance Binary Transaction where
    put Transaction{..} = put (txInputs, txOutputs)
    get = uncurry Transaction <$> get

instance Hashable Transaction where
    hashWithSalt s Transaction{..} = hashWithSalt s (txInputs, txOutputs)

instance Buildable Transaction where
    build Transaction{..} =
        F.build
            template
            ( listBuilderJSON $ map tripleBuilder txInputs
            , listBuilderJSON $ map pairBuilder txOutputs)
      where
        template = "Transaction { inputs = {}, outputs = {} }"

-- | Transaction is identified by its hash
type TransactionId = Hash

$(deriveSafeCopy 0 'base ''Coin)
$(deriveSafeCopy 0 'base ''Address)
$(deriveSafeCopy 0 'base ''Transaction)
