import           Options.Applicative (Parser, execParser, fullDesc, help,
                                      helper, info, metavar, progDesc,
                                      showDefault, strArgument, value, (<>))

import           RSCoin.Core         (defaultSecretKeyPath, keyGen,
                                      writePublicKey, writeSecretKey)

parser :: FilePath -> Parser FilePath
parser def =
    strArgument
        (metavar "PATH" <> help "Path to store private key" <>
         value def <> showDefault)

main :: IO ()
main = do
    def <- defaultSecretKeyPath
    fpName <-
        execParser $
        info (helper <*> parser def) (fullDesc <> progDesc "RSCoin's keygen")
    let fpSecret = fpName <> ".sec"
    let fpPublic = fpName <> ".pub"
    (sk,pk) <- keyGen
    writePublicKey fpPublic pk
    writeSecretKey fpSecret sk
