import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// The Keycard's app: the cards in the readers, which of their accounts Logos apps may use, offering
// more with the card's PIN, and the card's own administration: pairing, the PIN and the PUK. A .rep
// SLOT answers a pending reply, so calls go through logos.watch.
Item {
    id: root
    objectName: "keycardRoot"
    anchors.fill: parent

    Rectangle { anchors.fill: parent; color: Theme.palette.background }

    readonly property var backend: logos.module("keycard_ui")

    // Writable, fed by the signal: a binding with a function call would latch false at creation.
    property bool ready: false
    Connections {
        target: logos
        function onViewModuleReadyChanged(moduleName, isReady) {
            if (moduleName === "keycard_ui") root.ready = isReady && root.backend !== null
        }
    }

    function j(t, fb) { try { return JSON.parse(t && t.length ? t : fb) } catch (e) { return JSON.parse(fb) } }
    readonly property var cards: ready ? j(backend.cardsJson, "[]") : []
    readonly property var keycards: cards.filter(function (c) { return c.version !== undefined })
    // The forms act on the only Keycard; with more, on the first, by its reader.
    readonly property var card: keycards.length > 0 ? keycards[0] : null
    readonly property string reader: card ? card.reader : ""
    readonly property bool needsPairing: card !== null && card.secureChannel === 1 && !card.paired
    readonly property var accounts: ready ? j(backend.accountsJson, "[]") : []
    readonly property var exporting: ready ? j(backend.exportJson, "{}") : ({})
    readonly property bool working: exporting.state === "working"
    property bool showPinForms: false

    function familyWords(f) {
        return f === "evm" ? "EVM" : f === "bitcoin" ? "native segwit" : "taproot"
    }

    function cardLine(c) {
        if (c.version === undefined) return c.reader + ": " + (c.error || "not a Keycard")
        var s = "Keycard " + c.version + ", in " + c.reader
        if (!c.initialized) return s + ", not set up yet"
        if (!c.keyUid) return s + ", holding no key yet"
        if (c.secureChannel === 1) s += c.paired ? ", paired" : ", not paired"
        if (c.pinRetries !== undefined)
            s += ", PIN: " + c.pinRetries + (c.pinRetries === 1 ? " try left" : " tries left")
        return s
    }

    function exportLine() {
        if (root.working) return "Reading the card's public keys…"
        if (root.exporting.state === "done") {
            var n = (root.exporting.accounts || []).length
            return "Offered " + n + (n === 1 ? " account." : " accounts.")
        }
        if (root.exporting.state === "failed") return "Not offered: " + (root.exporting.error || "")
        return ""
    }

    Flickable {
        anchors.fill: parent
        contentHeight: column.implicitHeight + 2 * Theme.spacing.medium
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: column
            x: Theme.spacing.medium
            y: Theme.spacing.medium
            width: parent.width - 2 * Theme.spacing.medium
            spacing: Theme.spacing.small

            LogosText { text: "Keycard"; font.pixelSize: 22 }

            LogosText {
                objectName: "keycardNote"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.palette.textSecondary
                text: "Its keys stay on the card. Logos apps see only the accounts offered here. "
                      + "A Keycard has no screen: when it signs, you rely on what this computer shows, "
                      + "so read the signer's lines before you enter the PIN."
            }

            // ── the cards in the readers ─────────────────────────────────────────
            LogosText { text: "In a reader"; font.bold: true }
            LogosText {
                objectName: "noCard"
                visible: root.ready && root.cards.length === 0
                color: Theme.palette.textSecondary
                text: "No card in a reader. Insert a Keycard."
            }
            Repeater {
                model: root.cards
                delegate: LogosText {
                    objectName: "cardLine_" + index
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    text: root.cardLine(modelData)
                }
            }

            // ── pairing a 3.x card ───────────────────────────────────────────────
            LogosText {
                objectName: "pairNote"
                visible: root.needsPairing
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.palette.textSecondary
                text: "This card's secure channel needs pairing once, with its pairing password. "
                      + "The module keeps the pairing; the password itself is not kept."
            }
            RowLayout {
                visible: root.needsPairing
                spacing: Theme.spacing.small
                LogosTextField {
                    id: pairingField
                    objectName: "pairingField"
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    placeholderText: "Pairing password"
                }
                LogosButton {
                    objectName: "pairButton"
                    text: "Pair"
                    enabled: root.ready && pairingField.text.length > 0
                    onClicked: logos.watch(root.backend.pair(root.reader, pairingField.text),
                                           function (paired) { if (paired) pairingField.text = "" })
                }
            }

            // ── offering accounts ────────────────────────────────────────────────
            LogosText { text: "Offer accounts"; font.bold: true }
            RowLayout {
                spacing: Theme.spacing.small
                LogosCheckbox { id: evmBox; objectName: "offerEvm"; text: "EVM"; checked: true }
                LogosCheckbox { id: segwitBox; objectName: "offerSegwit"; text: "Bitcoin, native segwit" }
                LogosCheckbox {
                    id: taprootBox
                    objectName: "offerTaproot"
                    text: "Bitcoin, taproot"
                    // Taproot signing needs applet 4.0.
                    enabled: root.card === null || root.card.taproot === true
                }
            }
            RowLayout {
                spacing: Theme.spacing.small
                ButtonGroup { id: chainGroup }
                LogosRadioButton { id: mainChain; objectName: "chainMain"; ButtonGroup.group: chainGroup; text: "Bitcoin" }
                LogosRadioButton { objectName: "chainTest"; ButtonGroup.group: chainGroup; text: "Test networks"; checked: true }
            }
            RowLayout {
                spacing: Theme.spacing.small
                LogosText { text: "Account" }
                LogosTextField {
                    id: accountField
                    objectName: "offerAccount"
                    Layout.preferredWidth: 80
                    text: "0"
                    validator: IntValidator { bottom: 0; top: 2147483647 }
                }
                LogosTextField {
                    id: labelField
                    objectName: "offerLabel"
                    Layout.fillWidth: true
                    placeholderText: "Name (optional)"
                }
            }
            RowLayout {
                spacing: Theme.spacing.small
                LogosTextField {
                    id: pinField
                    objectName: "offerPin"
                    Layout.preferredWidth: 160
                    echoMode: TextInput.Password
                    placeholderText: "The card's PIN"
                    validator: RegularExpressionValidator { regularExpression: /[0-9]{0,6}/ }
                }
                LogosButton {
                    objectName: "offerButton"
                    text: "Offer"
                    enabled: root.ready && root.card !== null && !root.needsPairing && !root.working
                             && pinField.text.length === 6
                             && (evmBox.checked || segwitBox.checked || (taprootBox.checked && taprootBox.enabled))
                    onClicked: {
                        var families = []
                        if (evmBox.checked) families.push("evm")
                        if (segwitBox.checked) families.push("bitcoin")
                        if (taprootBox.checked && taprootBox.enabled) families.push("bitcoin_taproot")
                        var pin = pinField.text
                        pinField.text = ""
                        logos.watch(root.backend.offer(root.reader, JSON.stringify(families),
                                                       mainChain.checked ? "main" : "test",
                                                       parseInt(accountField.text || "0"),
                                                       labelField.text, pin),
                                    function (started) {})
                    }
                }
            }
            LogosText {
                objectName: "offerNote"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Theme.palette.textSecondary
                text: "The PIN opens the card for this export only. Only public keys are kept."
            }
            LogosText {
                objectName: "exportLine"
                Layout.fillWidth: true
                visible: text !== ""
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                color: root.exporting.state === "failed" ? Theme.palette.error : Theme.palette.text
                text: root.exportLine()
            }

            // ── the accounts offered ─────────────────────────────────────────────
            LogosText { text: "Offered to apps"; font.bold: true }
            LogosText {
                objectName: "noAccounts"
                visible: root.ready && root.accounts.length === 0
                color: Theme.palette.textSecondary
                text: "No account offered yet."
            }
            Repeater {
                id: accountRepeater
                objectName: "accountRepeater"
                model: root.accounts
                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.small
                    LogosText {
                        objectName: "accountLine_" + index
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        text: (modelData.label || root.familyWords(modelData.family)) + " — "
                              + (modelData.address || modelData.path || modelData.id)
                              + (modelData.available ? "" : ", card not inserted")
                    }
                    LogosButton {
                        objectName: "removeAccount_" + index
                        text: "Remove"
                        onClicked: logos.watch(root.backend.removeAccount(modelData.id), function (gone) {})
                    }
                }
            }

            // ── the PIN and the PUK ──────────────────────────────────────────────
            LogosButton {
                objectName: "pinFormsToggle"
                text: root.showPinForms ? "Hide the PIN and PUK" : "The PIN and PUK"
                onClicked: root.showPinForms = !root.showPinForms
            }
            ColumnLayout {
                visible: root.showPinForms
                Layout.fillWidth: true
                spacing: Theme.spacing.small

                LogosText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: Theme.palette.textSecondary
                    text: "A PIN is six digits and the PUK twelve. Too many wrong PINs block the PIN, "
                          + "and the PUK then sets a new one; too many wrong PUKs block the card for good."
                }
                LogosText { text: "Change the PIN" }
                RowLayout {
                    spacing: Theme.spacing.small
                    LogosTextField {
                        id: currentPin
                        objectName: "currentPin"
                        Layout.preferredWidth: 140
                        echoMode: TextInput.Password
                        placeholderText: "Current PIN"
                        validator: RegularExpressionValidator { regularExpression: /[0-9]{0,6}/ }
                    }
                    LogosTextField {
                        id: newPin
                        objectName: "newPin"
                        Layout.preferredWidth: 140
                        echoMode: TextInput.Password
                        placeholderText: "New PIN"
                        validator: RegularExpressionValidator { regularExpression: /[0-9]{0,6}/ }
                    }
                    LogosButton {
                        objectName: "changePinButton"
                        text: "Change"
                        enabled: root.ready && root.card !== null && !root.needsPairing
                                 && currentPin.text.length === 6 && newPin.text.length === 6
                        onClicked: {
                            var pin = currentPin.text, fresh = newPin.text
                            currentPin.text = ""
                            newPin.text = ""
                            logos.watch(root.backend.changePin(root.reader, pin, fresh), function (done) {})
                        }
                    }
                }
                LogosText { text: "Unblock the PIN with the PUK" }
                RowLayout {
                    spacing: Theme.spacing.small
                    LogosTextField {
                        id: pukField
                        objectName: "pukField"
                        Layout.preferredWidth: 180
                        echoMode: TextInput.Password
                        placeholderText: "PUK"
                        validator: RegularExpressionValidator { regularExpression: /[0-9]{0,12}/ }
                    }
                    LogosTextField {
                        id: unblockPin
                        objectName: "unblockNewPin"
                        Layout.preferredWidth: 140
                        echoMode: TextInput.Password
                        placeholderText: "New PIN"
                        validator: RegularExpressionValidator { regularExpression: /[0-9]{0,6}/ }
                    }
                    LogosButton {
                        objectName: "unblockButton"
                        text: "Unblock"
                        enabled: root.ready && root.card !== null && !root.needsPairing
                                 && pukField.text.length === 12 && unblockPin.text.length === 6
                        onClicked: {
                            var puk = pukField.text, fresh = unblockPin.text
                            pukField.text = ""
                            unblockPin.text = ""
                            logos.watch(root.backend.unblockPin(root.reader, puk, fresh), function (done) {})
                        }
                    }
                }
            }

            LogosText {
                objectName: "noticeLine"
                Layout.fillWidth: true
                visible: root.ready && root.backend.noticeText !== ""
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: root.ready ? root.backend.noticeText : ""
            }
            LogosText {
                objectName: "lastError"
                Layout.fillWidth: true
                visible: root.ready && root.backend.lastError !== ""
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                color: Theme.palette.error
                text: root.ready ? root.backend.lastError : ""
            }
        }
    }
}
