-- | Command line options for Bank

module BankOptions
       ( Command (..)
       , Options (..)
       , getOptions
       ) where

import qualified Data.Text              as T
import           Options.Applicative    (Parser, auto, command, execParser,
                                         fullDesc, help, helper, info, long,
                                         metavar, option, progDesc,
                                         short, showDefault, subparser, value,
                                         (<>))

import           Serokell.Util.OptParse (strOption)

import           RSCoin.Core            (Severity (Error),
                                         defaultPeriodDelta,
                                         defaultSecretKeyPath)

data Command
    = Serve
    | AddMintette String Int T.Text
    | AddExplorer String Int T.Text Int

data Options = Options
    { cloCommand     :: Command
    , cloPath        :: FilePath
    , cloPeriodDelta :: Integer
    , cloLogSeverity :: Severity
    , cloSkPath      :: FilePath
    }

commandParser :: Parser Command
commandParser =
    subparser
        (command
             "serve"
             (info
                  serveOpts
                  (progDesc "Simply run Bank serving users and mintettes")) <>
         command
             "add-mintette"
             (info addMintetteOpts (progDesc "Add given mintette to database")) <>
         command
             "add-explorer"
             (info addExplorerOpts (progDesc "Add given explorer to database")))
  where
    serveOpts = pure Serve
    addMintetteOpts =
        AddMintette <$>
        strOption (long "host") <*>
        option auto (long "port") <*>
        strOption
            (long "key" <>
             help "Mintette's public key (directly, not from file)" <>
             metavar "PUBLIC KEY")
    addExplorerOpts =
        AddExplorer <$> strOption (long "host") <*> option auto (long "port") <*>
        strOption
            (long "key" <>
             help "Explorer's public key (directly, not from file)" <>
             metavar "PUBLIC KEY") <*>
        option
            auto
            (long "id" <> help "Id of period which this explorer expects" <>
             value 0 <>
             showDefault)

optionsParser :: FilePath -> Parser Options
optionsParser defaultSKPath =
    Options
    <$>
    commandParser
    <*>
    strOption
        (long "path" <> value "bank-db" <> showDefault <>
         help "Path to database")
    <*>
    option
        auto
        (long "period-delta" <> value (toInteger defaultPeriodDelta) <>
         showDefault <> help "Period length in seconds")
    <*>
    option
        auto
        (long "log-severity" <> value Error <> showDefault <>
         help "Logging severity")
    <*>
    strOption
         (short 'k' <> long "secret-key" <> help "Path to bank secret key" <>
          value defaultSKPath <> showDefault <> metavar "PATH TO KEY")

getOptions :: IO Options
getOptions = do
    defaultSKPath <- defaultSecretKeyPath
    execParser $
        info
            (helper <*> optionsParser defaultSKPath)
            (fullDesc <> progDesc "RSCoin's Bank")
