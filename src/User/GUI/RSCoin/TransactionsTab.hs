{-# LANGUAGE NoOverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module GUI.RSCoin.TransactionsTab
       ( createTransactionsTab
       , initTransactionsTab
       ) where

import           Control.Exception       (SomeException (..), catch)
import           Control.Monad           (void, when)
import           Control.Monad.IO.Class  (liftIO)
import qualified Data.Text               as T
import           Graphics.UI.Gtk         (AttrOp ((:=)), on)
import qualified Graphics.UI.Gtk         as G

import           GUI.RSCoin.ErrorMessage (reportSimpleError)
import           GUI.RSCoin.Glade        (GladeMainWindow (..))
import           GUI.RSCoin.GUIAcid      (Contact (..), GUIState,
                                          addTransaction, getContacts)
import           GUI.RSCoin.MainWindow   (TransactionsTab (..))
import qualified GUI.RSCoin.MainWindow   as M
import           GUI.RSCoin.WalletTab    (updateWalletTab)
import qualified RSCoin.Core             as C
import           RSCoin.Timed            (runRealModeLocal)
import qualified RSCoin.User             as U

import           Serokell.Util.Text      (readFractional)

createTransactionsTab :: GladeMainWindow -> TransactionsTab
createTransactionsTab GladeMainWindow{..} =
    TransactionsTab
        gEntryPayTo
        gButtonChooseContacts
        gSpinButtonSendAmount
        gButtonConfirmSend
        gButtonClearSend

initTransactionsTab :: U.RSCoinUserState -> GUIState -> M.MainWindow -> IO ()
initTransactionsTab st gst mw = do
    let tr@TransactionsTab{..} = M.tabTransactions mw
    sendAmountAdjustment <- G.adjustmentNew 0 0 99999999999 1 1 1
    G.spinButtonSetAdjustment spinButtonSendAmount sendAmountAdjustment
    void (buttonClearSend `on`
          G.buttonActivated $ onClearButtonPressed tr)
    void (buttonConfirmSend `on`
          G.buttonActivated $ onSendButtonPressed st gst mw)
    void (buttonChooseContacts `on`
          G.buttonActivated $ onChooseContactsButtonPressed gst mw)

onClearButtonPressed :: TransactionsTab -> IO ()
onClearButtonPressed TransactionsTab{..} = do
    G.entrySetText entryPayTo ""
    G.entrySetText spinButtonSendAmount ""

onSendButtonPressed :: U.RSCoinUserState -> GUIState -> M.MainWindow -> IO ()
onSendButtonPressed st gst mw@M.MainWindow{..} =
    act `catch` handler
  where
    handler (e :: SomeException) =
        reportSimpleError mainWindow $ "Exception has happened: " ++ show e
    act = do
      let TransactionsTab{..} = tabTransactions
      sendAddressPre <- G.entryGetText entryPayTo
      sendAmount <- readFractional . T.pack <$> G.entryGetText spinButtonSendAmount
      let sendAddress = C.Address <$> C.constructPublicKey (T.pack sendAddressPre)
      constructDialog sendAddress sendAmount
    constructDialog Nothing _ =
        reportSimpleError mainWindow "Couldn't read address, most probably wrong format."
    constructDialog _ (Left _) =
        reportSimpleError mainWindow "Wrong amount format -- should be positive integer."
    constructDialog (Just _) (Right amount) | amount <= 0 = do
        reportSimpleError mainWindow "Amount should be positive."
        G.entrySetText (spinButtonSendAmount tabTransactions) ""
    constructDialog (Just address) (Right amount) = do
        userAmount <- runRealModeLocal $ U.getUserTotalAmount True st
        if amount > C.getCoin userAmount
        then do
            reportSimpleError mainWindow $
                 "Amount exceeds your assets -- you have only " ++
                 show (C.getCoin userAmount) ++ " coins."
            G.entrySetText (spinButtonSendAmount tabTransactions) $ show userAmount
        else do
            tr <- runRealModeLocal $
                U.formTransactionFromAll st address $ C.Coin amount 0 -- FIXME: allow sending coin with some color
            liftIO $ addTransaction gst (C.hash tr) (Just tr)
            dialog <- G.messageDialogNew
                (Just mainWindow)
                [G.DialogDestroyWithParent]
                G.MessageInfo
                G.ButtonsOk
                "Successfully formed and sent transaction."
            void $ G.dialogRun dialog
            G.widgetDestroy dialog
            onClearButtonPressed tabTransactions
            updateWalletTab st gst mw

onChooseContactsButtonPressed :: GUIState -> M.MainWindow -> IO ()
onChooseContactsButtonPressed gst M.MainWindow{..} = do
    contacts <- getContacts gst
    if null contacts
    then reportSimpleError mainWindow "Your contact list is empty -- nothing to choose from."
    else do
        dialog <- G.dialogNew
        G.set dialog [ G.windowTitle := "Choose contact"]
        void $ G.dialogAddButton dialog "Choose" G.ResponseOk
        void $ G.dialogAddButton dialog "Cancel" G.ResponseCancel
        upbox <- G.castToBox <$> G.dialogGetContentArea dialog
        view <- G.treeViewNew
        model <- setupModel view
        G.boxPackStart upbox view G.PackGrow 10
        G.widgetShowAll upbox
        mapM_ (G.listStoreAppend model) contacts
        response <- G.dialogRun dialog
        when (response == G.ResponseOk) $ do
            sel <- G.treeViewGetSelection view
            selNum <- G.treeSelectionCountSelectedRows sel
            rows <- G.treeSelectionGetSelectedRows sel
            if selNum == 0
            then reportSimpleError mainWindow "No contacts were selected."
            else do
                let row = head $ head rows
                    e = contactAddress $ contacts !! row
                G.entrySetText (M.entryPayTo tabTransactions) e
        G.widgetDestroy dialog
  where
    setupModel view = do
        model <- G.listStoreNew ([] :: [Contact])
        appendColumn view model True "Name" $
            \c -> [G.cellText := contactName c]
        appendColumn view model True "Address" $
            \c -> [G.cellText := contactAddress c]
        G.treeViewSetModel view model
        return model
    appendColumn view model expand title attributesSetter = do
        column <- G.treeViewColumnNew
        G.treeViewColumnSetTitle column title
        G.treeViewColumnSetExpand column expand
        renderer <- G.cellRendererTextNew
        G.cellLayoutPackStart column renderer False
        G.cellLayoutSetAttributes column renderer model attributesSetter
        void $ G.treeViewAppendColumn view column
