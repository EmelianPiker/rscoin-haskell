import           Control.Exception     (bracket)
import qualified Data.Text             as T

import           RSCoin.Core           (initLogging, logDebug)
import qualified RSCoin.User.AcidState as A

import           Actions               (proceedCommand)
import qualified UserOptions           as O

main :: IO ()
main = do
    opts@O.UserOptions{..} <- O.getUserOptions
    initLogging logSeverity
    bracket
        (A.openState
             walletPath
             addressesNum
             (bankKeyPath isBankMode bankModePath))
        A.closeState $
        \st ->
             do logDebug $
                    mconcat ["Called with options: ", (T.pack . show) opts]
                proceedCommand st userCommand
  where
    bankKeyPath True p = Just p
    bankKeyPath False _ = Nothing
