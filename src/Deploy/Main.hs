{-# LANGUAGE TupleSections #-}

import           Control.Concurrent      (ThreadId, forkIO, killThread,
                                          threadDelay)
import           Control.Exception       (finally)
import           Control.Monad           (forM_)
import           Data.Maybe              (fromMaybe)
import           Data.String.Conversions (cs)
import           Formatting              (build, int, sformat, shown, stext,
                                          string, (%))
import qualified Options.Applicative     as Opts
import           Serokell.Util.OptParse  (strArgument)
import           System.FilePath         ((</>))
import           System.IO.Temp          (createTempDirectory)
import qualified Turtle                  as Cherepakha

import qualified RSCoin.Core             as C

import           Config                  (BankData (..), DeployConfig (..),
                                          ExplorerData (..), MintetteData (..),
                                          NotaryData (..), readDeployConfig)

optionsParser :: Opts.Parser FilePath
optionsParser =
    strArgument $ mconcat [Opts.value "local.yaml", Opts.showDefault]

getConfigPath :: IO FilePath
getConfigPath =
    Opts.execParser $
    Opts.info
        (Opts.helper <*> optionsParser)
        (mconcat
             [ Opts.fullDesc
             , Opts.progDesc "Wrapper tool to deploy rscoin locally"])

data CommonParams = CommonParams
    { cpExec    :: Cherepakha.Text
    , cpBaseDir :: FilePath
    , cpPeriod  :: Word
    } deriving (Show)

waitSec :: Word -> IO ()
waitSec = threadDelay . (* 1000000) . fromIntegral

toModernFilePath :: FilePath -> Cherepakha.FilePath
toModernFilePath = Cherepakha.fromText . cs

startMintette :: CommonParams
              -> (Word, MintetteData)
              -> IO (ThreadId, C.PublicKey)
startMintette CommonParams{..} (idx,MintetteData{..}) = do
    let workingDir = cpBaseDir </> mconcat ["mintette-workspace-", show idx]
        workingDirModern = toModernFilePath workingDir
        skPath = workingDir </> "key"
        pkPath = workingDir </> "key.pub"
        keyGenCommand = mconcat [cpExec, "rscoin-keygen"]
        fullKeyGenCommand = mconcat [keyGenCommand, " ", cs skPath]
        runCommand = mconcat [cpExec, "rscoin-mintette"]
        severityArg =
            maybe "" (sformat (" --log-severity " % shown)) mdSeverity
        port = mintettePort idx
        dbDir = workingDir </> "mintette-db"
        fullRunCommand =
            sformat
                (stext % " --sk " % string % " --port " %
                 int %
                 stext %
                 " --bank-host 127.0.0.1 " %
                 " --path " %
                 string)
                runCommand
                skPath
                port
                severityArg
                dbDir
    Cherepakha.mkdir workingDirModern
    (Cherepakha.ExitSuccess,_) <-
        Cherepakha.shellStrict fullKeyGenCommand mempty
    key <-
        fromMaybe (error "FATAL: constructPulicKey failed") .
        C.constructPublicKey <$>
        (Cherepakha.readTextFile $ toModernFilePath pkPath)
    waitSec 1
    (, key) <$> forkIO (() <$ Cherepakha.shell fullRunCommand mempty)

startExplorer :: CommonParams
              -> (Word, ExplorerData)
              -> IO (ThreadId, C.PublicKey)
startExplorer CommonParams{..} (idx,ExplorerData{..}) = do
    let workingDir = cpBaseDir </> mconcat ["explorer-workspace-", show idx]
        workingDirModern = toModernFilePath workingDir
        skPath = workingDir </> "key"
        pkPath = workingDir </> "key.pub"
        keyGenCommand = mconcat [cpExec, "rscoin-keygen"]
        fullKeyGenCommand = mconcat [keyGenCommand, " ", cs skPath]
        runCommand = mconcat [cpExec, "rscoin-explorer"]
        severityArg =
            maybe "" (sformat (" --log-severity " % shown)) edSeverity
        portRpc = explorerPort idx
        portWeb = explorerWebPort idx
        dbDir = workingDir </> "explorer-db"
        fullRunCommand =
            sformat
                (stext % " --sk " % string % " --port-rpc " % int % " --port-web " % int % stext %
                 " --bank-host 127.0.0.1 " %
                 " --path " %
                 string)
                runCommand
                skPath
                portRpc
                portWeb
                severityArg
                dbDir
    Cherepakha.mkdir workingDirModern
    (Cherepakha.ExitSuccess,_) <-
        Cherepakha.shellStrict fullKeyGenCommand mempty
    key <-
        fromMaybe (error "FATAL: constructPulicKey failed") .
        C.constructPublicKey <$>
        (Cherepakha.readTextFile $ toModernFilePath pkPath)
    waitSec 1
    (, key) <$> forkIO (() <$ Cherepakha.shell fullRunCommand mempty)

type PortsAndKeys = [(Int, C.PublicKey)]

startNotary :: CommonParams -> NotaryData -> IO ThreadId
startNotary CommonParams{..} NotaryData{..} = do
    let workingDir = cpBaseDir </> "notary-workspace"
        workingDirModern = toModernFilePath workingDir
        dbDir = workingDir </> "notary-db"
        notaryCommand = mconcat [cpExec, "rscoin-notary"]
        severityArg =
            maybe "" (sformat (" --log-severity " % shown)) ndSeverity
        serveCommand =
            sformat
                (stext % " --path " % string % stext)
                notaryCommand
                dbDir
                severityArg
    Cherepakha.mkdir workingDirModern
    forkIO (() <$ Cherepakha.shell serveCommand mempty)

startBank :: CommonParams -> PortsAndKeys -> PortsAndKeys -> BankData -> IO ()
startBank CommonParams{..} mintettes explorers BankData{..} = do
    let workingDir = cpBaseDir </> "bank-workspace"
        workingDirModern = toModernFilePath workingDir
        dbDir = workingDir </> "bank-db"
        bankCommand = mconcat [cpExec, "rscoin-bank"]
        addMintetteCommand =
            sformat
                (stext % " --path " % string % " add-mintette " %
                 " --host 127.0.0.1 " %
                 " --port " %
                 int %
                 " --key " %
                 build)
                bankCommand
                dbDir
        addExplorerCommand =
            sformat
                (stext % " --path " % string % " add-explorer " %
                 " --host 127.0.0.1 " %
                 " --port " %
                 int %
                 " --key " %
                 build)
                bankCommand
                dbDir
        severityArg =
            maybe "" (sformat (" --log-severity " % shown)) bdSeverity
        serveCommand =
            sformat
                (stext % " --path " % string %
                 " --period-delta " %
                 int %
                 stext %
                 " serve " %
                 " --secret-key " %
                 string)
                bankCommand
                dbDir
                cpPeriod
                severityArg
                bdSecret
    Cherepakha.mkdir workingDirModern
    forM_
        mintettes
        (\(port,key) ->
              Cherepakha.shellStrict (addMintetteCommand port key) mempty)
    waitSec 1
    forM_
        explorers
        (\(port,key) ->
              Cherepakha.shellStrict (addExplorerCommand port key) mempty)
    waitSec 1
    Cherepakha.echo "Deployed successfully!"
    () <$ Cherepakha.shell serveCommand mempty

withTempDirectoryWorkaround :: FilePath -> String -> (FilePath -> IO a) -> IO a
withTempDirectoryWorkaround baseDir template callback =
    callback =<< createTempDirectory baseDir template

mintettePort :: Integral a => a -> Int
mintettePort = (C.defaultPort + 1 +) . fromIntegral

explorerPort :: Integral a => a -> Int
explorerPort = (C.defaultPort + 3000 +) . fromIntegral

explorerWebPort :: Integral a => a -> Int
explorerWebPort = (C.defaultPort + 5000 +) . fromIntegral

main :: IO ()
main = do
    DeployConfig{..} <- readDeployConfig =<< getConfigPath
    absoluteDir <-
        ((</> dcDirectory) . cs . either (error . show) id . Cherepakha.toText) <$>
        Cherepakha.pwd
    absoluteSecret <-
        ((</> bdSecret dcBank) .
         cs . either (error . show) id . Cherepakha.toText) <$>
        Cherepakha.pwd
    let killAll app =
            () <$
            Cherepakha.procStrict "killall" ["-q", "-s", "SIGINT", app] mempty
    killAll "rscoin-mintete"
    killAll "rscoin-notary"
    killAll "rscoin-explorer"
    killAll "rscoin-bank"
    withTempDirectoryWorkaround absoluteDir "rscoin-deploy" $
        \tmpDir ->
             do let cp =
                        CommonParams
                        { cpExec = dcExec
                        , cpBaseDir = tmpDir
                        , cpPeriod = dcPeriod
                        }
                    bd =
                        dcBank
                        { bdSecret = absoluteSecret
                        }
                    mintettePorts =
                        map mintettePort [0 .. length dcMintettes - 1]
                    explorerPorts =
                        map explorerPort [0 .. length dcExplorers - 1]
                (mintetteThreads,mintetteKeys) <-
                    unzip <$> mapM (startMintette cp) (zip [0 ..] dcMintettes)
                waitSec 2
                (explorerThreads,explorerKeys) <-
                    unzip <$> mapM (startExplorer cp) (zip [0 ..] dcExplorers)
                waitSec 2
                let mintettes = zip mintettePorts mintetteKeys
                    explorers = zip explorerPorts explorerKeys
                notaryThread <- startNotary cp dcNotary
                startBank cp mintettes explorers bd `finally`
                    (mapM_ killThread $
                     notaryThread : mintetteThreads ++ explorerThreads)
