import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "errors.js" as Errors
import "accountkit" as Accounts

ColumnLayout {
    id: admin
    objectName: "cardAdministrationPanel"
    Layout.fillWidth: true
    Layout.fillHeight: true
    spacing: Theme.spacing.small
    // Administration is a top-level area, not a modal. `active` tracks whether the
    // Administration tab is showing, replacing the dialog's open/close lifecycle.
    property bool active: false
    property var backend
    // A card operation ended (done or refused): the card may have changed, so its state is read again.
    signal cardOperationFinished(string adminId)
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
        }, function() { authenticity = "Could not verify" })
    }
    // The card's PIN/PUK retry counts are the AUTHORITATIVE blocked signal: cards() carries a stale
    // pinRetries and no pukRetries (see docs/specs.md), so the block state can't
    // be trusted from cards(). The counts are read with a no-PIN status call when the card is
    // INSERTED (KeycardView does it and passes the cache in here), so by the time this tab opens the
    // state is already known and the action list shows the right set from the first frame, with no
    // "full list, then collapse" flash. This panel's own read only refreshes after an op.
    property var cardStateCache: ({})              // adminId -> { pin, puk }, filled on card insert
    property string onCardName: ""
    property int localPinRetries: -1               // this panel's own refresh; -1 = not read here
    property int localPukRetries: -1
    property bool localRead: false                 // this panel's status read has returned for `selected`
    readonly property var cachedState: (selected && selected.adminId && cardStateCache[selected.adminId]) ? cardStateCache[selected.adminId] : null
    // Local read wins when present (freshest, e.g. right after an unblock); else the insert-time
    // cache; else unknown (-1). An uninitialized card has no PIN, so -1 is normal and NOT "blocked".
    readonly property int cardPinRetries: localPinRetries >= 0 ? localPinRetries : (cachedState ? cachedState.pin : -1)
    readonly property int cardPukRetries: localPukRetries >= 0 ? localPukRetries : (cachedState ? cachedState.puk : -1)
    // Only an initialized, paired card can be blocked, so only it needs the status read to be
    // classified. An uninitialized (e.g. just factory-reset) or unpaired card is classified from
    // cards() alone — don't make it wait on retry counts it will never have.
    readonly property bool needsStatusRead: !!selected && selected.initialized && !(selected.secureChannel === 1 && !selected.paired)
    readonly property bool cacheHasState: !!(selected && selected.adminId && cardStateCache.hasOwnProperty(selected.adminId))
    // The card's state is known once its status read has returned (this panel's or the insert-time
    // cache), or when it needs no read to classify. The action list waits on this, so the user never
    // sees the wrong set first — and an uninitialized card is not stuck on "Reading card…".
    readonly property bool stateKnown: !selected || !needsStatusRead || localRead || cacheHasState
    // `again`: after an operation, keep what is shown until the new answer arrives.
    function readCardName(again) {
        if (!selected) { onCardName = ""; localPinRetries = -1; localPukRetries = -1; localRead = false; return }
        if (!again) { onCardName = "Checking…"; localPinRetries = -1; localPukRetries = -1; localRead = false }
        var p = {action:"status", reader:selected.reader, cardId:selected.adminId, keyUid:selected.keyUid || ""}
        var asked = selected.adminId
        // A reply for a card no longer selected is dropped, so it can't show another card's tries.
        var current = function () { return !!selected && selected.adminId === asked }
        logos.watch(backend.administer(JSON.stringify(p)), function(raw) {
            if (!current()) return
            var r; try { r = JSON.parse(raw) } catch(e) { r = {} }
            onCardName = (r && r.ok && r.cardName) ? r.cardName : ""
            localPinRetries = (r && r.ok && typeof r.pinRetries === "number") ? r.pinRetries : -1
            localPukRetries = (r && r.ok && typeof r.pukRetries === "number") ? r.pukRetries : -1
            localRead = true
        }, function() { if (!current()) return; if (!again) onCardName = ""; localRead = true })
    }
    // Blocked state, from the authoritative retry counts (insert-time cache, or this panel's read).
    readonly property bool blockedPin: cardPinRetries === 0
    readonly property bool blockedPuk: cardPukRetries === 0
    readonly property bool cardBlocked: !!selected && (blockedPin || blockedPuk)
    readonly property var usableCards: cards.filter(function(c) { return !!c.adminId })
    // A long hex id, shortened for display; the full value stays on the copy button.
    function shortHex(s) { return s && s.length > 16 ? s.slice(0, 8) + "…" + s.slice(-8) : (s || "") }
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
    // The answer of a read-only status op (Card details / authenticity), shown in its dialog.
    property string message: ""
    property string infoTitle: ""
    readonly property bool changed: !!selected && !usableCards.some(function(c) { return c.reader === selected.reader && c.adminId === selected.adminId && (c.keyUid || "") === (selected.keyUid || "") })
    // Actions available for the current card state. Gating mirrors the Status desktop
    // Keycard management UI (DetailsView.qml + KeycardStateInfo.qml); see
    // docs/specs.md. status + check_identity are read-only info, not
    // actions (surfaced as buttons in the Card status section via runStatusOp).
    readonly property var choices: {
        if (!selected) return []
        // No PIN yet: the only thing you can do is set the card up.
        if (!selected.initialized) return [{id:"initialize",label:"Set up card"}]
        // A 3.x card that isn't paired: pair before anything else — plus factory reset as the escape
        // when you can't pair (e.g. the pairing password is lost). Factory reset needs no PIN or
        // pairing, so it stays available here.
        if (selected.secureChannel === 1 && !selected.paired) {
            var up = [{id:"pair",label:"Pair this app"}]
            if ((selected.capabilities & 16) !== 0) up.push({id:"factory_reset",label:"Factory reset"})
            return up
        }

        var hasKeys = !!selected.keyUid                      // Status hasKeyPair: a seed is present
        var canReset = (selected.capabilities & 16) !== 0

        // PUK frozen (fully blocked): a factory reset is the only exit. Checked first because a
        // PUK-frozen card is usually also PIN-locked, and unblock_pin cannot help without a PUK.
        if (blockedPuk) return canReset ? [{id:"factory_reset",label:"Factory reset"}] : []
        // PIN locked, PUK still has tries: unblock with the PUK, or reset. Everything that needs
        // the current PIN is hidden.
        if (blockedPin) {
            var r = [{id:"unblock_pin",label:"Unblock PIN"}]
            if (canReset) r.push({id:"factory_reset",label:"Factory reset"})
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
                {id:"remove_key",label:"Erase keys"}])
        }
        // Credential + metadata: any usable card (has PIN, not locked).
        ops = ops.concat([{id:"change_pin",label:"Change PIN"},{id:"change_puk",label:"Change PUK"}])
        if (selected.secureChannel === 1) ops = ops.concat([{id:"change_pairing_password",label:"Change pairing password"},{id:"unpair",label:"Remove a pairing slot"}])
        ops = ops.concat([{id:"set_name",label:"Update name"},{id:"set_ndef",label:"NFC text message"},
            {id:"read_data",label:"Read card data"},{id:"write_data",label:"Write card data"}])
        if (canReset) ops.push({id:"factory_reset",label:"Factory reset"})
        return ops
    }
    // The chosen operation, set ONLY by a choice-button press and cleared when its dialog closes.
    // (It used to be derived from a hidden combo whose index auto-snapped to 0 on model rebuilds,
    // which spuriously set the action and auto-opened a flow.)
    property string action: ""
    readonly property var actionChoice: choices.filter(function (o) { return o.id === admin.action })[0] || null
    // Present the available actions as a visible, risk-grouped list instead of one dropdown.
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
    function selectCard(index) { selected = index >= 0 ? usableCards[index] : null; admin.action = ""; message = ""; detailsDialog.close(); checkAuthenticity(); readCardName() }
    // Card status and authenticity need no PIN; run them directly from the status section
    // without the action/confirm flow. Self-contained so it never touches a pending action.
    function runStatusOp(id) {
        if (!selected || busy || changed) return
        infoTitle = id === "check_identity" ? "Card authenticity" : "Card details"
        detailsDialog.open()
        busy = true; message = "Working with the card…"; failed = false
        var p = {action:id, reader:selected.reader, cardId:selected.adminId, keyUid:selected.keyUid || ""}
        logos.watch(backend.administer(JSON.stringify(p)), function(raw) {
            busy = false
            var r
            try { r = JSON.parse(raw) } catch(e) { r = {ok:false, error:"The card did not return a valid response. Refresh its status before retrying."} }
            failed = !r.ok || r.genuine === false
            message = r.ok ? (r.message || "Done.") : (Errors.human(r.error) || "Operation failed.")
            if (r.ok && id === "status") message = "PIN attempts left: " + r.pinRetries + " · PUK attempts left: " + r.pukRetries + (selected.secureChannel === 1 ? "\nFree pairing slots: " + r.freePairingSlots + " · This app's slot: " + r.pairingSlot : "")
            r = null
        }, function() { busy = false; failed = true; message = "The Keycard app did not answer. Try again." })
    }
    onActiveChanged: {
        if (active) { busy = false; picker.currentIndex = Math.max(0, usableCards.findIndex(function(c) { return c.adminId === admin.preferredCard })); selectCard(usableCards.length ? picker.currentIndex : -1); preferredCard = "" }
        else { selected = null; message = ""; detailsDialog.close() }
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
    onChangedChanged: if (changed) { message = "The card or wallet changed. Select the card again before continuing."; failed = true; detailsDialog.close() }
    // Every operation is a guided flow (CardFlow); Card details and authenticity, which need no
    // PIN, answer in detailsDialog.
    onActionChanged: {
        message = ""
        if (action === "") return
        cardFlow.action = action
        cardFlow.card = admin.selected
        cardFlow.cardName = admin.onCardName === "Checking…" ? "" : admin.onCardName
        cardFlow.walletId = admin.walletIdFor()
        cardFlow.begin()
        cardFlow.open()
    }
    // The master fingerprint (Wallet ID) for the selected card's wallet, read from cardGroups; "" when
    // the card holds no keys or the fingerprint is not yet known.
    function walletIdFor() {
        if (!selected || !selected.keyUid) return ""
        for (var i = 0; i < cardGroups.length; i++) {
            var g = cardGroups[i]
            if ((g.id || "") === "seed:" + selected.keyUid || g.keyUid === selected.keyUid) {
                var accs = g.accounts || []
                for (var j = 0; j < accs.length; j++) if (accs[j].fingerprint) return accs[j].fingerprint
            }
        }
        return ""
    }
    LogosScrollView {
        id: adminScroll
        Layout.fillWidth: true; Layout.fillHeight: true
        contentWidth: availableWidth
        ColumnLayout {
        width: Math.min(adminScroll.availableWidth, 560)
        x: Math.max(0, (adminScroll.availableWidth - width) / 2)
        spacing: Theme.spacing.small
        RowLayout {
            visible: admin.usableCards.length > 1
            Layout.fillWidth: true
            LogosComboBox { id: picker; objectName: "adminCardPicker"; Layout.fillWidth: true; enabled: !admin.busy; model: admin.usableCards.map(function(c) { return (admin.cardName(c) || "No name") + " · " + c.adminId.split(":").pop().slice(0,8) + " · " + c.reader }); onActivated: admin.selectCard(currentIndex) }
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
        // Card name as the section title, above the details card (on the panel background).
        LogosText {
            visible: !!admin.selected && !admin.changed
            Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small
            wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
            color: (admin.selected && !admin.onCardName) ? Theme.palette.textMuted : Theme.palette.text
            font.weight: Theme.typography.weightBold; font.pixelSize: Theme.typography.subtitleText
            // The on-card name, or a muted placeholder when the card carries none (don't default
            // to "Keycard" as if that were its name).
            text: admin.selected ? (admin.onCardName || "Name is empty") : ""
        }
        Rectangle {
            visible: !!admin.selected && !admin.changed
            Layout.topMargin: Theme.spacing.tiny
            Layout.fillWidth: true
            Layout.preferredHeight: detailsCol.implicitHeight + 2 * Theme.spacing.small
            radius: Theme.spacing.radiusLarge
            color: Theme.palette.backgroundSecondary
            border.width: 1; border.color: Theme.palette.borderSubtle
            ColumnLayout {
                id: detailsCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.spacing.small }
                spacing: Theme.spacing.tiny
                // Blocked card: a red flag at the top of the card data. The available actions (Unblock
                // PIN / Factory reset only) carry the way out. cards() can't see a frozen PUK, so this
                // rides on the authoritative status read.
                LogosText {
                    objectName: "cardBlockedFlag"
                    visible: admin.cardBlocked
                    Layout.fillWidth: true; Layout.bottomMargin: Theme.spacing.tiny
                    textFormat: Text.PlainText; color: Theme.palette.error
                    font.weight: Theme.typography.weightBold
                    text: "This card is blocked"
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: Theme.spacing.tiny
                    LogosText { Layout.alignment: Qt.AlignVCenter; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText; color: Theme.palette.textSecondary; text: admin.selected ? "Card fingerprint:  " + admin.shortHex(admin.selected.adminId.split(":").pop()) : "" }
                    LogosCopyButton { Layout.alignment: Qt.AlignVCenter; visible: !!admin.selected; value: admin.selected ? admin.selected.adminId.split(":").pop() : ""; feedbackText: "Card fingerprint copied"; size: 18; iconSize: 12 }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: Theme.spacing.tiny
                    visible: !!(admin.selected && admin.selected.keyUid)
                    LogosText { Layout.alignment: Qt.AlignVCenter; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText; color: Theme.palette.textSecondary; text: admin.selected && admin.selected.keyUid ? "Key id:  " + admin.shortHex(admin.selected.keyUid) : "" }
                    LogosCopyButton { Layout.alignment: Qt.AlignVCenter; visible: !!(admin.selected && admin.selected.keyUid); value: admin.selected && admin.selected.keyUid ? admin.selected.keyUid : ""; feedbackText: "Key id copied"; size: 18; iconSize: 12 }
                    Item { Layout.fillWidth: true }
                }
                LogosText { Layout.fillWidth: true; textFormat: Text.PlainText; color: Theme.palette.textSecondary; text: admin.selected ? "Version:  " + (admin.selected.initialized ? "Keycard " + admin.selected.version : "Not set up") : "" }
                LogosText { Layout.fillWidth: true; textFormat: Text.PlainText; color: Theme.palette.textSecondary; text: admin.selected ? "Private keys:  " + (admin.selected.keyUid ? "present" : "not loaded") : "" }
                LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.PlainText; color: Theme.palette.textSecondary; text: "Authenticity:  " + (admin.authenticity || "—") }
                // More details as a link at the end of the card.
                // More details (PIN/PUK attempts, pairing slots) only has more to show for an
                // initialized, paired card; hide it for an unpaired or uninitialized one.
                LogosLink { objectName: "statusDetails"; visible: admin.needsStatusRead; Layout.topMargin: Theme.spacing.tiny; enabled: !admin.busy; text: "More details"; onActivated: admin.runStatusOp("status") }
            }
        }
        // Until the card's state is known, show a brief placeholder instead of the action list, so
        // the user never sees the full set collapse to the blocked set. The state is usually already
        // cached from card insertion, so this rarely shows.
        LogosText {
            objectName: "adminReadingCard"
            visible: !!admin.selected && !admin.changed && !admin.stateKnown
            Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small
            textFormat: Text.PlainText; color: Theme.palette.textSecondary
            text: "Reading card…"
        }
        Repeater {
            model: admin.actionGroups
            delegate: ColumnLayout {
                id: groupItem
                required property var modelData
                Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small; spacing: Theme.spacing.small
                visible: !!admin.selected && !admin.changed && admin.stateKnown
                LogosText {
                    visible: !!groupItem.modelData.advanced
                    Layout.fillWidth: true
                    text: (admin.advancedOpen ? "▾  " : "▸  ") + groupItem.modelData.name
                    font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                    TapHandler { onTapped: admin.advancedOpen = !admin.advancedOpen }
                }
                Repeater {
                    model: groupItem.modelData.items
                    delegate: LogosButton {
                        id: actBtn
                        required property var modelData
                        objectName: "adminAction_" + modelData.id
                        Layout.fillWidth: true
                        visible: !groupItem.modelData.advanced || admin.advancedOpen
                        enabled: !!admin.selected && !admin.busy && !admin.changed
                        text: modelData.label
                        onClicked: admin.action = modelData.id
                        Component.onCompleted: if (groupItem.modelData.danger) {
                            actBtn.labelItem.color = Qt.binding(function() { return actBtn.enabled ? Theme.palette.error : Theme.palette.textMuted })
                            actBtn.backgroundItem.border.color = Qt.binding(function() { return actBtn.enabled ? Theme.palette.error : Theme.palette.border })
                        }
                    }
                }
            }
        }
        CardFlow {
            id: cardFlow
            objectName: "cardFlowDialog"
            backend: admin.backend
            onFinished: function (ok) {
                var was = admin.action
                admin.action = ""
                // Re-point selected at the refreshed card so attempts/state are current for the next op.
                if (admin.selected) {
                    for (var i = 0; i < admin.usableCards.length; i++) {
                        var c = admin.usableCards[i]
                        if (c.reader === admin.selected.reader && c.adminId === admin.selected.adminId) { admin.selected = c; break }
                    }
                }
                // Any operation can change what the card reports (its name, PIN and PUK attempts, or
                // that it is blocked), done or refused: read it again, here and for the wallet list.
                // A card-identity change (reset/erase) is handled by the `changed` path as well.
                if (admin.selected) {
                    admin.readCardName(true)
                    admin.cardOperationFinished(admin.selected.adminId)
                }
            }
        }
        // Card details and authenticity: read-only answers, no form. Held by a zero-size item so no
        // layout manages the dialog's position and size.
        Item {
        Layout.preferredWidth: 0; Layout.preferredHeight: 0
        LogosDialog {
            id: detailsDialog
            objectName: "adminDetailsDialog"
            title: admin.infoTitle !== "" ? admin.infoTitle : "Card details"
            parent: Overlay.overlay
            x: parent ? Math.round((parent.width - width) / 2) : 0
            y: parent ? Math.round((parent.height - height) / 2) : 0
            width: Math.min((parent ? parent.width : 600) - 40, 560)
            closePolicy: admin.busy ? Popup.NoAutoClose : (Popup.CloseOnEscape | Popup.CloseOnPressOutside)
            onClosed: if (!admin.busy) { admin.infoTitle = ""; admin.message = "" }
            contentItem: ColumnLayout {
                spacing: Theme.spacing.small
                LogosText { objectName: "adminBusy"; visible: admin.busy; text: "Working with the card…"; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.textSecondary }
                LogosText { objectName: "adminResult"; visible: !!admin.message && !admin.busy; text: admin.message; textFormat: Text.PlainText; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; color: admin.failed ? Theme.palette.error : Theme.palette.text }
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    LogosButton { objectName: "adminClose"; text: admin.busy ? "Working…" : "Close"; enabled: !admin.busy; onClicked: detailsDialog.close() }
                }
            }
        }
        }
        }
    }
}
