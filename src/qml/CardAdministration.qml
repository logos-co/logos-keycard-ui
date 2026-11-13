import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "accountkit" as Accounts

ColumnLayout {
    id: admin
    objectName: "cardAdministrationPanel"
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Theme.spacing.small
    // ADR-A: administration is a top-level area, not a modal. `active` tracks whether the
    // Administration tab is showing, replacing the dialog's open/close lifecycle.
    property bool active: false
    property var backend
    property var cards: []
    // Local card names live in cardGroups (not on the card object); used for the picker label.
    property var cardGroups: []
    property bool advancedOpen: false
    // Authenticity, checked automatically on card load. The module attempts an identity proof
    // on any card (4.0 via its certificate, 3.x applets that support identify_card); cards that
    // cannot prove identity return an error, shown as "Could not verify".
    property string authenticity: ""
    function checkAuthenticity() {
        authenticity = ""
        if (!selected) return
        authenticity = "Checking…"
        var p = {action:"check_identity", reader:selected.reader, cardId:selected.adminId, keyUid:selected.keyUid || ""}
        logos.watch(backend.administer(JSON.stringify(p)), function(raw) {
            var r; try { r = JSON.parse(raw) } catch(e) { r = {ok:false} }
            authenticity = r.ok ? (r.genuine ? "Verified by Keycard" : "Not certified by Keycard") : "Could not verify"
        })
    }
    readonly property var usableCards: cards.filter(function(c) { return !!c.adminId })
    // The saved name for a card, resolved from cardGroups by the reader it sits in ("" if none).
    function cardName(c) {
        if (!c) return ""
        for (var i = 0; i < cardGroups.length; i++) {
            var cs = cardGroups[i].connections || []
            for (var j = 0; j < cs.length; j++) {
                if (cs[j].reader === c.reader) return cardGroups[i].name || ""
            }
        }
        return ""
    }
    property var selected: null
    property string preferredCard: ""
    property bool busy: false
    property bool failed: false
    // Result/status line shown under the form. Must be declared: assignments to an undeclared
    // property throw in QML strict mode, which aborted perform()/runStatusOp after busy=true and
    // left every admin action locked on a real card. (Pre-existing; surfaced in live dogfood.)
    property string message: ""
    // Title for the op dialog when a no-form status op (Card details / authenticity) is running.
    property string infoTitle: ""
    property var generated: []
    readonly property bool changed: !!selected && !usableCards.some(function(c) { return c.reader === selected.reader && c.adminId === selected.adminId && (c.keyUid || "") === (selected.keyUid || "") })
    // Actions available for the current card state. Gating mirrors the Status desktop
    // Keycard management UI (DetailsView.qml + KeycardStateInfo.qml); see
    // docs/keycard-state-action-map.md. status + check_identity are read-only info, not
    // actions (surfaced as buttons in the Card status section via runStatusOp).
    readonly property var choices: {
        if (!selected) return []
        // No PIN yet: the only thing you can do is set the card up.
        if (!selected.initialized) return [{id:"initialize",label:"Set up card"}]
        // A 3.x card that isn't paired: pair before anything else is possible.
        if (selected.secureChannel === 1 && !selected.paired) return [{id:"pair",label:"Pair this app"}]

        var hasKeys = !!selected.keyUid                      // Status hasKeyPair: a seed is present
        var locked = selected.pinRetries === 0               // Status isBlockedPIN: PIN locked
        var canReset = (selected.capabilities & 16) !== 0

        // PIN locked: recovery only. Everything that needs the current PIN is hidden.
        if (locked) {
            var r = [{id:"unblock_pin",label:"Unblock PIN"}]
            if (canReset) r.push({id:"factory_reset",label:"Factory reset card"})
            return r
        }

        var ops = []
        // Seed provisioning only while the card holds no seed; seed-present ops otherwise.
        if (!hasKeys) {
            ops = ops.concat([{id:"generate_phrase",label:"Create recovery phrase"},
                {id:"load_phrase",label:"Import recovery phrase"},
                {id:"generate_key",label:"Generate keys without backup"}])
        } else {
            ops = ops.concat([{id:"verify_phrase",label:"Check recovery phrase"},
                {id:"remove_key",label:"Erase keys from card"}])
        }
        // Credential + metadata: any usable card (has PIN, not locked).
        ops = ops.concat([{id:"change_pin",label:"Change PIN"},{id:"change_puk",label:"Change PUK"}])
        if (selected.secureChannel === 1) ops = ops.concat([{id:"change_pairing_password",label:"Change pairing password"},{id:"unpair",label:"Remove a pairing slot"}])
        ops = ops.concat([{id:"set_name",label:"Name stored on card"},{id:"set_ndef",label:"NFC text message"},
            {id:"read_data",label:"Read card data"},{id:"write_data",label:"Write card data"}])
        if (canReset) ops.push({id:"factory_reset",label:"Factory reset card"})
        return ops
    }
    readonly property string action: choices[operation.currentIndex] ? choices[operation.currentIndex].id : ""
    // ADR-A: present the available actions as a visible, risk-grouped list instead of one dropdown.
    // Only actions available for the current card state appear (reuse `choices`); the destructive
    // tier is the set that already carries a typed-confirmation gate. `adminOperation` stays as the
    // hidden backing model so the selection source of truth, and the doctests, are unchanged.
    readonly property var actionGroups: {
        var tiers = [
            {name:"Set up and keys", danger:false, advanced:false, ids:["initialize","pair","generate_phrase","load_phrase","verify_phrase","change_pin","change_puk","unblock_pin","set_name"]},
            {name:"Destructive", danger:true, advanced:false, ids:["remove_key","factory_reset"]},
            {name:"Advanced", danger:false, advanced:true, ids:["change_pairing_password","unpair","set_ndef","read_data","write_data","generate_key"]}
        ]
        var byId = {}; choices.forEach(function(o) { byId[o.id] = o })
        return tiers.map(function(t) { return {name:t.name, danger:t.danger, advanced:t.advanced, items: t.ids.filter(function(id) { return byId[id] }).map(function(id) { return byId[id] })} })
                    .filter(function(g) { return g.items.length > 0 })
    }
    readonly property bool needsPin: ["check_identity","status","initialize","pair","factory_reset","unblock_pin","read_data"].indexOf(action) < 0
    readonly property bool needsNewPin: ["initialize","change_pin","unblock_pin"].indexOf(action) >= 0
    readonly property bool needsPuk: ["initialize","change_puk","unblock_pin"].indexOf(action) >= 0
    readonly property bool needsPairing: ["pair","change_pairing_password"].indexOf(action) >= 0 || (action === "initialize" && selected && selected.secureChannel === 1 && customPairing.checked)
    readonly property bool needsPhrase: ["load_phrase","verify_phrase"].indexOf(action) >= 0
    readonly property bool loadingGenerated: action === "generate_phrase" && generated.length > 0
    readonly property string confirmation: action === "factory_reset" ? "RESET" : action === "remove_key" ? "ERASE" : action === "generate_key" ? "NO BACKUP" : action === "write_data" ? "WRITE" : ""
    // Putting a wallet onto the card, which a card that holds keys already refuses.
    readonly property bool loadsKeys: ["load_phrase","generate_key","generate_phrase"].indexOf(action) >= 0
    readonly property bool holdsKeys: !!(selected && selected.keyUid)
    // Why the button below can't be pressed yet, in words: it is often a field out of view.
    readonly property string blocked: {
        if (!selected || busy || !action) return ""
        if (changed) return "The card changed. Press Refresh card to see it as it is now."
        if (loadsKeys && holdsKeys) return "This card already holds keys. Erase them first (Erase keys from card) to put another wallet on it."
        if (needsPin && pin.text.length !== 6) return loadingGenerated ? "Type the card's PIN again to load the phrase." : "Type the card's PIN."
        if (needsNewPin && (newPin.text.length !== 6 || newPin.text !== repeatPin.text)) return "Type the new PIN twice."
        if (needsPhrase && phrase.text.trim().length === 0) return "Type the recovery phrase."
        if ((action === "load_phrase" || loadingGenerated) && !backedUp.checked) return "Confirm you have backed up the phrase."
        if (confirmation && confirm.text !== confirmation) return "Type " + confirmation + " to confirm."
        return ""
    }
    function clearSecrets() { advanced.checked = false; customPairing.checked = false; pin.text = ""; newPin.text = ""; repeatPin.text = ""; puk.text = ""; repeatPuk.text = ""; pairing.text = ""; repeatPairing.text = ""; alternate.text = ""; repeatAlternate.text = ""; phrase.text = ""; passphrase.text = ""; generated = []; backedUp.checked = false; confirm.text = "" }
    function selectCard(index) { clearSecrets(); selected = index >= 0 ? usableCards[index] : null; operation.currentIndex = -1; message = ""; if (typeof opDialog !== "undefined") opDialog.close(); checkAuthenticity() }
    // Card status and authenticity need no PIN; run them directly from the status section
    // without the action/confirm flow. Self-contained so it never touches a pending action.
    function runStatusOp(id) {
        if (!selected || busy || changed) return
        infoTitle = id === "check_identity" ? "Card authenticity" : "Card details"
        opDialog.open()
        busy = true; message = "Working with the card…"; failed = false
        var p = {action:id, reader:selected.reader, cardId:selected.adminId, keyUid:selected.keyUid || ""}
        logos.watch(backend.administer(JSON.stringify(p)), function(raw) {
            busy = false
            var r
            try { r = JSON.parse(raw) } catch(e) { r = {ok:false, error:"The card did not return a valid response. Refresh its status before retrying."} }
            failed = !r.ok || r.genuine === false
            message = r.ok ? (r.message || "Done.") : (r.error || "Operation failed.")
            if (r.ok && id === "status") message += (r.cardName ? "\nName on card: " + r.cardName : "") + "\nPIN attempts left: " + r.pinRetries + " · PUK attempts left: " + r.pukRetries + "\nPrivate keys: " + (r.hasKey ? "present" : "not loaded") + (selected.secureChannel === 1 ? "\nFree pairing slots: " + r.freePairingSlots + " · This app's slot: " + r.pairingSlot : "")
            r = null
        })
    }
    onActiveChanged: {
        if (active) { busy = false; picker.currentIndex = Math.max(0, usableCards.findIndex(function(c) { return c.adminId === admin.preferredCard })); selectCard(usableCards.length ? picker.currentIndex : -1); preferredCard = "" }
        else { clearSecrets(); selected = null; message = ""; data.text = ""; opDialog.close() }
    }
    // Auto-select a card when the list populates (e.g. a card inserted while the tab is already
    // open, so onActiveChanged did not fire). Keeps Details and Actions populated as soon as a
    // card is readable, and clears the selection when the last card is removed.
    onUsableCardsChanged: {
        if (!active) return
        if (usableCards.length === 0) { if (selected) selectCard(-1); return }
        if (!selected || !usableCards.some(function(c) { return c.adminId === selected.adminId })) {
            picker.currentIndex = 0
            selectCard(0)
        }
    }
    onChangedChanged: if (changed) { clearSecrets(); message = "The card or wallet changed. Select the card again before continuing."; failed = true; opDialog.close() }
    onActionChanged: { clearSecrets(); data.text = ""; message = ""; if (action !== "") opDialog.open() }
    function perform() {
        if (!selected || changed || busy) return
        var op = loadingGenerated ? "load_phrase" : action
        var p = {action:op, reader:selected.reader,cardId:selected.adminId,keyUid:selected.keyUid || ""}
        if (needsPin) p.pin = pin.text
        if (needsNewPin) p.newPin = newPin.text
        if (needsPuk) p.puk = puk.text
        if (needsPairing) p.pairingPassword = pairing.text
        if (action === "initialize" && alternate.text) p.alternatePin = alternate.text
        if (needsPhrase || loadingGenerated) { p.phrase = loadingGenerated ? generated.join(" ") : phrase.text; p.passphrase = passphrase.text }
        if (action === "generate_phrase" && !loadingGenerated) p.words = Number(wordCount.currentText.split(" ")[0])
        if (action === "unpair") p.slot = Number(slot.text)
        if (["read_data","write_data"].indexOf(action) >= 0) p.dataType = dataType.currentIndex === 0 ? 0 : 2
        if (["set_name","set_ndef","write_data"].indexOf(action) >= 0) p.text = data.text
        if (op === "load_phrase") p.confirmation = "BACKED UP"
        else if (confirmation) p.confirmation = confirm.text
        busy = true; message = "Working with the card…"; failed = false
        var request = JSON.stringify(p); p = null
        // Clear typed secrets before dispatch. Generated words remain only until loading completes.
        pin.text = ""; newPin.text = ""; repeatPin.text = ""; puk.text = ""; repeatPuk.text = ""; pairing.text = ""; repeatPairing.text = ""; alternate.text = ""; repeatAlternate.text = ""; phrase.text = ""; passphrase.text = ""
        logos.watch(backend.administer(request), function(raw) {
            busy = false
            var r
            try { r = JSON.parse(raw) } catch(e) { r = {ok:false,error:"The card did not return a valid response. Refresh its status before retrying."} }
            failed = !r.ok || r.genuine === false; message = r.ok ? r.message || "Done." : r.error || "Operation failed."
            if (r.phrase) generated = r.phrase.split(" ")
            if (r.ok && op === "load_phrase") generated = []
            if (r.ok && op === "status") message += (r.cardName ? "\nName on card: " + r.cardName : "") + "\nPIN attempts left: " + r.pinRetries + " · PUK attempts left: " + r.pukRetries + "\nPrivate keys: " + (r.hasKey ? "present" : "not loaded") + (selected.secureChannel === 1 ? "\nFree pairing slots: " + r.freePairingSlots + " · This app's slot: " + r.pairingSlot : "")
            if (r.data !== undefined) data.text = r.data
            r = null
        })
        request = ""
    }
    LogosScrollView {
        id: adminScroll
        Layout.fillWidth: true; Layout.fillHeight: true
        contentWidth: availableWidth
        ColumnLayout {
        width: adminScroll.availableWidth
        spacing: Theme.spacing.small
        LogosText { visible: admin.usableCards.length > 0; Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small; text: "Select card"; font.pixelSize: Theme.typography.subtitleText; font.weight: Theme.typography.weightBold; color: Theme.palette.text }
        RowLayout {
            visible: admin.usableCards.length > 0
            Layout.fillWidth: true
            LogosComboBox { id: picker; objectName: "adminCardPicker"; Layout.fillWidth: true; enabled: !admin.busy; model: admin.usableCards.map(function(c) { return (admin.cardName(c) || "No name") + " · " + c.adminId.split(":").pop().slice(0,8) + " · " + c.reader }); onActivated: admin.selectCard(currentIndex) }
            LogosIconButton { objectName: "adminRefresh"; iconSource: Qt.resolvedUrl("assets/refresh.svg"); enabled: !admin.busy; onClicked: logos.watch(admin.backend.refresh(), function() { admin.selectCard(picker.currentIndex) }) }
        }
        ColumnLayout {
            visible: admin.usableCards.length === 0
            Layout.fillWidth: true; Layout.topMargin: Theme.spacing.xxlarge; Layout.alignment: Qt.AlignHCenter; spacing: Theme.spacing.small
            LogosText { Layout.alignment: Qt.AlignHCenter; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Theme.typography.subtitleText; font.weight: Theme.typography.weightBold; color: Theme.palette.text; text: "No Keycard to administer" }
            LogosText { Layout.alignment: Qt.AlignHCenter; Layout.maximumWidth: 420; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: Theme.palette.textSecondary; text: "To administer a card, connect it over USB in a card reader. A Keycard Shell is for signing only; move its card into a reader." }
            RowLayout {
                Layout.alignment: Qt.AlignHCenter; spacing: Theme.spacing.tiny
                LogosLink { text: "Get a reader"; href: "https://keycard.tech/products/keycard-reader-for-desktop"; onActivated: function(url) { emptyGetReaderCopy.copy(); Qt.openUrlExternally(url) } }
                LogosCopyButton { id: emptyGetReaderCopy; value: "https://keycard.tech/products/keycard-reader-for-desktop"; feedbackText: "URL copied"; size: 24; iconSize: 14 }
            }
        }
        LogosText { visible: admin.usableCards.length > 0; Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small; text: "Details"; font.pixelSize: Theme.typography.subtitleText; font.weight: Theme.typography.weightBold; color: Theme.palette.text }
        Rectangle {
            visible: !!admin.selected && !admin.changed
            Layout.fillWidth: true
            Layout.preferredHeight: detailsCol.implicitHeight + 2 * Theme.spacing.small
            radius: Theme.spacing.radiusLarge
            color: Theme.palette.backgroundSecondary
            border.width: 1; border.color: Theme.palette.borderSubtle
            ColumnLayout {
                id: detailsCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.spacing.small }
                spacing: Theme.spacing.tiny
                RowLayout {
                    Layout.fillWidth: true; spacing: Theme.spacing.small
                    LogosText { Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText; color: Theme.palette.text; text: "Card name:  " + (admin.selected ? (admin.cardName(admin.selected) || "No name") : "") }
                    LogosButton { objectName: "statusDetails"; text: "More details"; enabled: !admin.busy; onClicked: admin.runStatusOp("status") }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: Theme.spacing.tiny
                    LogosText { wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText; color: Theme.palette.textSecondary; text: admin.selected ? "Fingerprint:  " + admin.selected.adminId.split(":").pop() : "" }
                    LogosCopyButton { visible: !!admin.selected; value: admin.selected ? admin.selected.adminId.split(":").pop() : ""; feedbackText: "Fingerprint copied"; size: 24; iconSize: 14 }
                    Item { Layout.fillWidth: true }
                }
                LogosText { Layout.fillWidth: true; textFormat: Text.PlainText; color: Theme.palette.textSecondary; text: admin.selected ? "Version:  " + (admin.selected.initialized ? "Keycard " + admin.selected.version : "Not set up") : "" }
                LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.PlainText; color: Theme.palette.textSecondary; text: "Authenticity:  " + (admin.authenticity || "—") }
            }
        }
        LogosText {
            visible: !!admin.selected && !admin.changed && admin.choices.length > 0
            Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small; text: "Actions"; font.pixelSize: Theme.typography.subtitleText; font.weight: Theme.typography.weightBold; color: Theme.palette.text
        }
        Repeater {
            model: admin.actionGroups
            delegate: ColumnLayout {
                id: groupItem
                required property var modelData
                Layout.fillWidth: true; spacing: Theme.spacing.tiny
                visible: !!admin.selected && !admin.changed
                LogosText {
                    Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small
                    text: groupItem.modelData.advanced ? ((admin.advancedOpen ? "▾  " : "▸  ") + groupItem.modelData.name) : groupItem.modelData.name
                    font.pixelSize: Theme.typography.secondaryText
                    color: groupItem.modelData.danger ? Theme.palette.error : Theme.palette.textSecondary
                    TapHandler { enabled: !!groupItem.modelData.advanced; onTapped: admin.advancedOpen = !admin.advancedOpen }
                }
                Repeater {
                    model: groupItem.modelData.items
                    delegate: LogosButton {
                        required property var modelData
                        objectName: "adminAction_" + modelData.id
                        Layout.fillWidth: true
                        visible: !groupItem.modelData.advanced || admin.advancedOpen
                        enabled: !!admin.selected && !admin.busy && !admin.changed
                        text: (admin.action === modelData.id ? "●  " : "") + modelData.label
                        onClicked: operation.currentIndex = admin.choices.findIndex(function(o) { return o.id === modelData.id })
                    }
                }
            }
        }
        LogosComboBox { id: operation; objectName: "adminOperation"; visible: false; Layout.fillWidth: true; model: admin.choices.map(function(o) { return o.label }); enabled: !!admin.selected && !admin.busy && !admin.changed }
        LogosDialog {
            id: opDialog
            objectName: "adminOpDialog"
            title: admin.infoTitle !== "" ? admin.infoTitle : (admin.choices[operation.currentIndex] ? admin.choices[operation.currentIndex].label : "Card action")
            parent: Overlay.overlay
            anchors.centerIn: parent
            width: Math.min((parent ? parent.width : 600) - 40, 560)
            closePolicy: admin.busy ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)
            onClosed: if (!admin.busy) { admin.infoTitle = ""; operation.currentIndex = -1 }
            contentItem: ColumnLayout {
                spacing: Theme.spacing.small
                LogosScrollView {
                    id: form; Layout.fillWidth: true; Layout.maximumHeight: 460; Layout.preferredHeight: Math.min(formCol.implicitHeight + 8, 460); contentWidth: availableWidth
                    visible: !!admin.action
                    ColumnLayout {
                        id: formCol
                        width: form.availableWidth; spacing: Theme.spacing.small
                        enabled: !admin.busy && !admin.changed && !!admin.selected
                LogosText { visible: admin.action === "factory_reset" || admin.action === "remove_key"; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.error; text: admin.action === "factory_reset" ? "Factory reset erases this card's keys, PIN, PUK, pairings and card metadata. It requires no PIN. You need a recovery backup to restore access to funds. Saved wallet names and accounts on this computer are retained." : "Erase the recovery keys from this card. You need a recovery backup to restore access to funds. PIN, PUK and pairings remain. Saved accounts on this computer are retained." }
                LogosText { visible: admin.action === "generate_key"; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.error; text: "Generates keys inside an empty card with NO recovery phrase. If this card is lost or reset, its wallet cannot be recovered. Use Create recovery phrase for a recoverable wallet." }
                LogosText { visible: admin.loadsKeys && admin.holdsKeys; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "This card already holds keys. Erase keys explicitly before loading a different wallet."; color: Theme.palette.error }
                LogosTextField { id: pin; objectName: "adminPin"; visible: admin.needsPin; Layout.fillWidth: true; placeholderText: "Current PIN (6 digits)"; echoMode: TextInput.Password; validator: RegularExpressionValidator { regularExpression: /[0-9]{0,6}/ } }
                LogosTextField { id: newPin; objectName: "adminNewPin"; visible: admin.needsNewPin; Layout.fillWidth: true; placeholderText: "New PIN (6 digits)"; echoMode: TextInput.Password; validator: RegularExpressionValidator { regularExpression: /[0-9]{0,6}/ } }
                LogosTextField { id: repeatPin; objectName: "adminRepeatPin"; visible: admin.needsNewPin; Layout.fillWidth: true; placeholderText: "Repeat new PIN"; echoMode: TextInput.Password }
                RowLayout {
                    visible: admin.needsPuk; Layout.fillWidth: true
                    LogosTextField { id: puk; objectName: "adminPuk"; Layout.fillWidth: true; placeholderText: admin.action === "unblock_pin" ? "Current PUK (12 digits)" : "New PUK (12 digits)"; echoMode: TextInput.Password; validator: RegularExpressionValidator { regularExpression: /[0-9]{0,12}/ } }
                    LogosInfoButton { title: "PUK"; text: "The PUK unblocks a PIN after too many failed attempts. Keep it separately from the card. Changing the PUK requires the current PIN. A wrong PUK consumes a recovery attempt." }
                }
                LogosTextField { id: repeatPuk; objectName: "adminRepeatPuk"; visible: admin.needsPuk && admin.action !== "unblock_pin"; Layout.fillWidth: true; placeholderText: "Repeat new PUK"; echoMode: TextInput.Password }
                LogosTextField { id: alternate; visible: admin.action === "initialize" && admin.selected && admin.selected.secureChannel === 2; Layout.fillWidth: true; placeholderText: "Alternate PIN (optional, 6 digits)"; echoMode: TextInput.Password; validator: RegularExpressionValidator { regularExpression: /[0-9]{0,6}/ } }
                LogosTextField { id: repeatAlternate; visible: alternate.visible && !!alternate.text; Layout.fillWidth: true; placeholderText: "Repeat alternate PIN"; echoMode: TextInput.Password }
                LogosText { visible: alternate.visible; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Keycard 4.0 has an alternate wallet PIN. If omitted, it uses the first six PUK digits. It must differ from the main PIN."; color: Theme.palette.textSecondary }
                LogosButton {
                    id: advanced; objectName: "adminAdvanced"; visible: admin.action === "initialize" && admin.selected && admin.selected.secureChannel === 1
                    property bool checked: false
                    text: checked ? "Advanced options ▾" : "Advanced options ▸"
                    onClicked: checked = !checked
                    onCheckedChanged: if (!checked) customPairing.checked = false
                }
                LogosCheckbox {
                    id: customPairing; objectName: "adminCustomPairing"; visible: advanced.visible && advanced.checked
                    text: "Use a custom pairing password"
                    onCheckedChanged: { pairing.text = ""; repeatPairing.text = "" }
                }
                LogosText {
                    visible: advanced.visible && !customPairing.checked; Layout.fillWidth: true; wrapMode: Text.WordWrap
                    text: "Uses the standard pairing password so compatible apps can pair automatically. Your PIN protects access to the wallet."
                    color: Theme.palette.textSecondary
                }
                LogosText { visible: admin.action === "pair"; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "The app first tries the standard 3.x pairing password automatically. If pairing is still required, enter the password used when this card was set up." }
                LogosTextField { id: pairing; objectName: "adminPairing"; visible: admin.needsPairing; Layout.fillWidth: true; placeholderText: "Pairing password"; echoMode: TextInput.Password }
                LogosTextField { id: repeatPairing; objectName: "adminRepeatPairing"; visible: admin.needsPairing && admin.action !== "pair"; Layout.fillWidth: true; placeholderText: "Repeat pairing password"; echoMode: TextInput.Password }
                LogosText { visible: admin.action === "change_pairing_password"; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Changes the password for future pairings. Existing pairings continue to work; remove their slots to revoke them." }
                LogosTextField { id: slot; objectName: "adminSlot"; visible: admin.action === "unpair"; Layout.fillWidth: true; placeholderText: "Slot index (0–9, if supported by this card)"; validator: RegularExpressionValidator { regularExpression: /[0-9]/ } }
                LogosText { visible: slot.visible; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Read Card status to find this app's slot. Clearing that slot unpairs this app too. Cards do not report which app owns other slots. Unsupported slot indexes are refused by the card." }
                LogosComboBox { id: wordCount; objectName: "adminWordCount"; visible: admin.action === "generate_phrase" && !admin.loadingGenerated; Layout.fillWidth: true; model: ["12 words","15 words","18 words","21 words","24 words"] }
                LogosText { visible: admin.needsPhrase || admin.action === "generate_phrase"; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Recovery words and passphrases pass through this computer. They are not saved by this app. Keep a written backup; anyone with these words can access the wallet." }
                Accounts.PhraseGrid { id: phrase; objectName: "adminPhrase"; visible: admin.needsPhrase; Layout.fillWidth: true }
                GridLayout {
                    visible: admin.generated.length > 0; Layout.fillWidth: true; columns: 2
                    Repeater { model: admin.generated; delegate: LogosText { required property string modelData; required property int index; Layout.fillWidth: true; text: (index+1) + ". " + modelData; textFormat: Text.PlainText } }
                }
                LogosTextField { id: passphrase; visible: admin.needsPhrase || admin.loadingGenerated; Layout.fillWidth: true; placeholderText: "BIP39 passphrase (optional)"; echoMode: TextInput.Password }
                LogosCheckbox { id: backedUp; objectName: "adminBackup"; visible: admin.action === "load_phrase" || admin.loadingGenerated; text: "I have backed up the recovery phrase and any passphrase" }
                LogosComboBox { id: dataType; visible: ["read_data","write_data"].indexOf(admin.action) >= 0; Layout.fillWidth: true; model: ["Public metadata","Cash applet data"] }
                LogosText { visible: admin.action === "write_data"; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Replaces the selected public data area. Read and copy its existing hexadecimal data first. Other apps may use it for wallet metadata." }
                LogosTextField { id: data; objectName: "adminData"; visible: ["set_name","set_ndef","read_data","write_data"].indexOf(admin.action) >= 0; Layout.fillWidth: true; readOnly: admin.action === "read_data"; placeholderText: admin.action === "set_name" ? "Card name (20 ASCII characters)" : admin.action === "set_ndef" ? "Public NFC text (empty clears it)" : "Hexadecimal data" }
                LogosText { visible: admin.action === "set_name" || admin.action === "set_ndef"; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: admin.action === "set_name" ? "This name travels with the physical card. It does not rename the seed wallet on this computer." : "NFC text is public and can be read without a PIN. Do not put secrets here." }
                LogosTextField { id: confirm; objectName: "adminConfirmation"; visible: !!admin.confirmation; Layout.fillWidth: true; placeholderText: "Type " + admin.confirmation + " to confirm" }
                    }
                }
                LogosText { objectName: "adminBusy"; visible: admin.busy; text: "Working with the card…"; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.textSecondary }
                LogosText { objectName: "adminResult"; visible: !!admin.message && !admin.busy; text: admin.message; textFormat: Text.PlainText; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; color: admin.failed ? Theme.palette.error : Theme.palette.text }
                LogosText { objectName: "adminBlocked"; visible: !!admin.blocked && !!admin.action && !admin.busy; text: admin.blocked; Layout.fillWidth: true; wrapMode: Text.WordWrap; horizontalAlignment: Text.AlignRight; font.pixelSize: Theme.typography.secondaryText; color: Theme.palette.textSecondary }
                RowLayout {
                    Layout.fillWidth: true
                    LogosButton { objectName: "adminClose"; text: admin.busy ? "Working…" : "Close"; enabled: !admin.busy; onClicked: opDialog.close() }
                    Item { Layout.fillWidth: true }
                    LogosButton {
                        objectName: "adminSubmit"; visible: !!admin.action; text: admin.loadingGenerated ? "Load backed-up phrase" : admin.action === "generate_phrase" ? "Generate phrase" : admin.action === "factory_reset" ? "Reset card" : admin.action === "remove_key" ? "Erase keys" : "Continue"
                        enabled: !!admin.selected && !admin.changed && !admin.busy && !!admin.action
                            && (!admin.needsPin || pin.text.length === 6)
                            && (!admin.needsNewPin || (newPin.text.length === 6 && newPin.text === repeatPin.text))
                            && (!admin.needsPuk || (puk.text.length === 12 && (admin.action === "unblock_pin" || puk.text === repeatPuk.text)))
                            && (!admin.needsPairing || (pairing.text.length > 0 && (admin.action === "pair" || pairing.text === repeatPairing.text)))
                            && (!alternate.visible || !alternate.text || (alternate.text.length === 6 && alternate.text === repeatAlternate.text))
                            && (!admin.needsPhrase || phrase.text.trim().length > 0)
                            && (!(admin.action === "load_phrase" || admin.loadingGenerated) || backedUp.checked)
                            && (!admin.confirmation || confirm.text === admin.confirmation)
                            && (admin.action !== "unpair" || slot.text.length === 1)
                            && !(admin.loadsKeys && admin.holdsKeys)
                        onClicked: admin.perform()
                    }
                }
            }
        }
        }
    }
}
