import           Actions               (proceedCommand)
import qualified RSCoin.User.AcidState as A
import qualified UserOptions           as O

import           Control.Exception     (bracket)

main :: IO ()
main = do
    opts@O.UserOptions{..} <- O.getUserOptions
    bracket (A.openState walletPath 10 isBankMode) A.closeState $
        \st ->
             do putStrLn $ "Called with options: " ++ show opts
                proceedCommand st userCommand
