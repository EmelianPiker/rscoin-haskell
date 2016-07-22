module JsonDemo where

import Prelude

import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Console (log, CONSOLE)

import Data.Tuple (Tuple (..))
import Data.Tuple.Nested (tuple4)

import Data.Argonaut.Printer (printJson)
import Data.Generic (class Generic)

import App.RSCoin as W
import Serokell.Aeson.Helper (encodeJson)

data V = V { getV :: forall v. v } --this doesn't work either

logJS :: forall o e. (Generic o) => o -> Eff ( console :: CONSOLE | e) Unit
logJS = log <<< printJson <<< encodeJson

helper :: forall o e. (Generic o) => o -> Eff ( console :: CONSOLE | e) Unit
helper v = do
  --log $ show v   --these types don't have Show instances
    logJS v

main :: forall e. Eff (console :: CONSOLE | e) Unit
main = do
    let coin     = W.Coin {getColor: 0, getCoin: W.Rational "0.3242342"}
        key      = W.PublicKey "YblQ7+YCmxU/4InsOwSGH4Mm37zGjgy7CLrlWlnHdnM="
        hash     = W.Hash "DldRwCblQ7Loqy6wYJnaodHl30d3j3eH+qtFzfEv46g="
        addr     = W.Address { getAddress:  key }
        tx       = W.TransactionSummarySerializable {txId: hash, txInputs: [tuple4 hash 0 coin addr], txOutputs: [(Tuple addr coin)], txInputsSum: [Tuple 0 coin], txOutputsSum: [Tuple 0 coin]}
        err      = W.ParseError "error"
        introMsg = W.IMAddressInfo addr
        aiMsg    = W.AIGetTransactions (Tuple 0 2)
        outMsg   = W.OMTxNumber 8 10
        helper'  = do
            helper coin
            helper key
            helper hash
            helper addr
            helper tx
            helper err
            helper introMsg
            helper aiMsg
            helper outMsg
    helper'
