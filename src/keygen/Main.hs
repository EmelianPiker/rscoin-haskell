import           Control.Monad                      (replicateM)

import           KeygenOptions              as Opts

import           Options.Applicative                ((<>))

import           RSCoin.Core                        (derivePublicKey, keyGen,
                                                     readSecretKey, sign,
                                                     writePublicKey,
                                                     writeSecretKey)

main :: IO ()
main = do
    Opts.Options{..} <- Opts.getOptions
    case cloCommand of
        Opts.Single keyName -> do
            let fpSecret = keyName <> ".sec"
                fpPublic = keyName
            (sk,pk) <- keyGen
            writeSecretKey fpSecret sk
            writePublicKey fpPublic pk
        Opts.Batch genNum genPath skPath -> do
            masterSK <- readSecretKey skPath
            keys <- replicateM genNum (generator masterSK)
            let generatedKeys = unlines $ map show keys
            writeFile genPath generatedKeys
  where
    generator masterSK = do
        (sk, pk) <- keyGen
        let sig      = sign masterSK pk
            masterPK = derivePublicKey masterSK
        return (masterPK, (pk, sk), sig)
