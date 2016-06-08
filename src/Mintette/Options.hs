-- | Command line options for Mintette

module Options
       ( Options (..)
       , getOptions
       ) where

import           Data.ByteString     (ByteString)

import           Options.Applicative (Parser, auto, execParser, fullDesc, help,
                                      helper, info, long, metavar, option,
                                      progDesc, short, showDefault, strOption,
                                      switch, value, (<>))

import           RSCoin.Core         (Severity (Error), defaultBankHost,
                                      defaultPort, defaultSecretKeyPath)

data Options = Options
    { cloPort          :: Int
    , cloPath          :: FilePath
    , cloSecretKeyPath :: FilePath
    , cloLogSeverity   :: Severity
    , cloMemMode       :: Bool
    , cloBankHost      :: ByteString
    }

optionsParser :: FilePath -> Parser Options
optionsParser defaultSKPath =
    Options <$>
    option auto (short 'p' <> long "port" <> value defaultPort <> showDefault) <*>
    strOption
        (long "path" <> value "mintette-db" <> showDefault <>
         help "Path to database") <*>
    strOption
        (long "sk" <> value defaultSKPath <> metavar "FILEPATH" <> showDefault) <*>
    option auto
        (long "log-severity" <> value Error <> showDefault <>
         help "Logging severity") <*>
    switch (short 'm' <> long "memory-mode" <> help "Run in memory mode") <*>
    option auto
        (long "bank-host" <> value defaultBankHost <> showDefault <>
         help "Host name for bank")

getOptions :: IO Options
getOptions = do
    defaultSKPath <- defaultSecretKeyPath
    execParser $
        info
            (helper <*> optionsParser defaultSKPath)
            (fullDesc <> progDesc "RSCoin's Mintette")
