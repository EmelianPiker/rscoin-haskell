module App.ViewNew.Address where

import Prelude                        (($), map, show)

import App.Types                       (Action, State, Coin(Coin), Color(Color),
                                       TransactionSummarySerializable(TransactionSummarySerializable),
                                       queryToString)
import App.Routes                     (txUrl) as R
import App.CSS                        (darkRed, opacity, logoPath, lightGrey,
                                       headerBitmapPath, noBorder, adaSymbolPath)

import Pux.Html                       (Html, tbody, text, th, tr, thead, a, span,
                                       table, div, small, h3, td, img, ul, li,
                                       input, label)
import Pux.Html.Attributes            (aria, data_, type_, className, id_,
                                       placeholder, value, src, alt, role, href,
                                       autoComplete)
import Pux.Router                     (link)
import Pux.CSS                        (style, backgroundColor, padding, px,
                                       color, white, backgroundImage, url)

import Data.Tuple.Nested              (uncurry2)
import Data.Array                     (length)
import Data.Maybe                     (fromMaybe)

view :: State -> Html Action
view state =
    div
        []
        [ div
            [ className "row" ]
            [ div
                [ className "dark-red-color"
                ]
                [ h3 [] [ text "ADDRESS"
                        ]
                ]
            , div
                [ className "row" ]
                [ div
                    [ className "col-xs-8" ]
                    [ table
                        [ className "table" ]
                        [ tbody
                            []
                            [ tr
                                []
                                [ td [] [ text "Address" ]
                                , td [] [ text "oqpwieoqweipqie" ]
                                ]
                            , tr
                                [ className "light-grey-background" ]
                                [ td [] [ text "Transactions" ]
                                , td [] [ text "127" ]
                                ]
                            , tr
                                []
                                [ td [] [ text "Final balance" ]
                                , td
                                    []
                                    [ img
                                        [ src adaSymbolPath
                                        ]
                                        []
                                    , text "213.12"
                                    , div
                                        [ className "pull-right" ]
                                        [ text "Color balance"
                                        , span
                                            [ className "btn-group"
                                            , data_ "toggle" "buttons"
                                            ]
                                            [ label
                                                [ className "btn btn-primary active" ]
                                                [ input
                                                    [ type_ "checkbox"
                                                    , autoComplete "off"
                                                    ]
                                                    []
                                                , text "Show/Hide colors"
                                                ]
                                                -- @sasha: we can use http://www.bootstraptoggle.com/
                                                -- or some other implementation if you prefer it. Please just let me know and I will replace them
                                            ]
                                        ]
                                    ]
                                ]
                            ]
                        ]

                    ]
                , div
                    [ className "col-xs-4" ]
                    [ -- @sasha: this is from http://getbootstrap.com/javascript/#markup
                      -- and from http://getbootstrap.com/components/#nav-tabs
                      ul
                        [ className "nav nav-pills" -- try experimenting with either nav-tabs or nav-pills classes .. I think nav-pills would require less overrides to match our style. There is laso nav-justified if we want to use it
                        -- we could even use fade effect if it looks good to you http://getbootstrap.com/javascript/#fade-effect
                        , role "tablist"
                        ]
                        [ li
                            [ role "presentation"
                            , className "active"
                            ]
                            [ a
                                [ href "#color-balance"
                                , id_ "color-balance-tab"
                                , aria "controls" "color-balance"
                                , role "tab"
                                , data_ "toggle" "tab"
                                ]
                                [ text "Color balance" ]
                            ]
                        , li
                            [ role "presentation"
                            , className ""
                            ]
                            [ a
                                [ href "#qr-code"
                                , id_ "qr-code-tab"
                                , aria "controls" "qr-code"
                                , role "tab"
                                , data_ "toggle" "tab"
                                ]
                                [ text "QR Code" ]
                            ]
                        ]
                    , div
                        [ className "tab-content" ]
                        [ div
                            [ role "tabpanel"
                            , className "tab-pane active"
                            , id_ "color-balance"
                            , aria "labelledby" "color-balance-tab"
                            ]
                            [ div
                                [ id_ "color-table" ]
                                [ table
                                    [ className "table" ]
                                    [ tbody
                                        []
                                        [ tr
                                            []
                                            [ td [] [ text "Red" ]
                                            , td
                                                []
                                                [ img
                                                    [ src adaSymbolPath
                                                    ]
                                                    []
                                                , text "71,2929"
                                                ]
                                            ]
                                        , tr
                                            []
                                            [ td [] [ text "Blue" ]
                                            , td
                                                []
                                                [ img
                                                    [ src adaSymbolPath
                                                    ]
                                                    []
                                                , text "71,2929"
                                                ]
                                            ]
                                        , tr
                                            []
                                            [ td [] [ text "Blue" ]
                                            , td
                                                []
                                                [ img
                                                    [ src adaSymbolPath
                                                    ]
                                                    []
                                                , text "71,2929"
                                                ]
                                            ]
                                        , tr
                                            []
                                            [ td [] [ text "Blue" ]
                                            , td
                                                []
                                                [ img
                                                    [ src adaSymbolPath
                                                    ]
                                                    []
                                                , text "71,2929"
                                                ]
                                            ]
                                        , tr
                                            []
                                            [ td [] [ text "Blue" ]
                                            , td
                                                []
                                                [ img
                                                    [ src adaSymbolPath
                                                    ]
                                                    []
                                                , text "71,2929"
                                                ]
                                            ]
                                        ]
                                    ]
                                ]
                            ]
                        , div
                            [ role "tabpanel"
                            , className "tab-pane"
                            , id_ "qr-code"
                            , aria "labelledby" "qr-code-tab"
                            ]
                            [ div
                                [ className "col-xs-5" ]
                                [ img
                                    [ src "http://www.appcoda.com/wp-content/uploads/2013/12/qrcode.jpg"
                                    , id_ "qr-code-img"
                                    ]
                                    []
                                ]
                            , div
                                [ className "col-xs-7" ]
                                [ text "Scan this QR Code to copy address to clipboard" ]
                            ]
                        ]
                    ]
                ]
            ]
        , div
            [ className "row light-grey-background" ]
            [ div [] [ text "test" ]
            , div [] [ text "test" ]
            ]
        ]
