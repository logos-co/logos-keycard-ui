import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "accountkit" as Accounts

Item {
    id: root
    objectName: "keycardRoot"
    anchors.fill: parent
    Rectangle { anchors.fill: parent; color: Theme.palette.background }
    readonly property var backend: logos.module("keycard_ui")
    property bool ready: false
    // Startup has stalled if the view module is not ready after a grace window. Turns the
    // silent, timeout-less "Starting" into an honest, actionable state.
    property bool startupStalled: false
    readonly property url iconRefresh: Qt.resolvedUrl("assets/refresh.svg")
    readonly property url iconEdit: Qt.resolvedUrl("assets/edit.svg")
    readonly property url iconTrash: Qt.resolvedUrl("assets/trash.svg")
    Component.onCompleted: ready = backend !== null && logos.isViewModuleReady("keycard_ui")
    Timer { running: !root.ready && !root.startupStalled; interval: 15000; onTriggered: root.startupStalled = true }
    Connections {
        target: logos
        function onViewModuleReadyChanged(name, isReady) {
            if (name === "keycard_ui") { root.ready = isReady && root.backend !== null; if (root.ready) root.startupStalled = false }
        }
        // Opened to manage accounts: being here answers it, and `handoff` keeps the person here.
        function onIntentRequested(requestId, intent, params, requesterName) {
            if (intent !== "evm.accounts.manage") return
            logos.respond(requestId, true, ({}), "")
        }
    }
    function j(t, fb) { try { return JSON.parse(t || fb) } catch(e) { return JSON.parse(fb) } }
    readonly property var cards: ready ? j(backend.cardsJson, "[]") : []
    readonly property var cardGroups: ready ? j(backend.cardGroupsJson, "[]") : []
    readonly property var shellDevices: ready ? j(backend.shellDevicesJson, "[]") : []
    readonly property var shellGroups: ready ? j(backend.shellGroupsJson, "[]") : []
    readonly property var wallets: (ready ? j(backend.walletsJson, "[]") : []).concat(shellDevices.filter(function(d) {
        const identifiedHere = d.verifiedMasterKeyId && j(backend.walletsJson, "[]").some(function(g) { return g.id === "seed:" + d.verifiedMasterKeyId })
        return !identifiedHere && !root.shellGroups.some(function(g) { return (g.connections || []).some(function(c) { return c.serial === d.serial }) })
    }).map(function(d) { return {id: "shell:" + d.serial + ":", serial: d.serial, transport: "shell", connected: true, pending: true, accounts: [], connections: [{transport: "shell", serial: d.serial, connected: true}]} }))
    // A wallet is a keypair, identified by its master key ("seed:<keyUid>"). Everything else in the
    // list is a connected device whose wallet is not known yet (a Shell before its one-tap identify,
    // or a keyless card): shown apart so a device is never mistaken for a wallet.
    readonly property var identifiedWallets: wallets.filter(function(g) { return g.id.indexOf("seed:") === 0 })
    readonly property var unidentified: wallets.filter(function(g) { return g.id.indexOf("seed:") !== 0 })
    // A connected Shell holds a seed the app cannot read without asking the device. Until the person
    // sends an Identify request and approves it on the Shell screen, we do not know which wallet is
    // inside, so no wallet card and no transport strip is touched: the Shell surfaces only as a
    // dismissible notification (below) and a yellow header chip. A keyless card (non-shell) still
    // uses the "Not identified yet" card list.
    // A connected Shell's current connection counts as identified only while the on-device
    // confirmation is live: keycard_shell_module reports that as verifiedMasterKeyId, which is
    // session-scoped and dropped when the Shell disconnects (backend: "Session verification is
    // temporary: never turn USB presence into a saved seed association"). So a re-seated Shell must
    // be identified again, even though the app still remembers which wallet that serial belongs to
    // (its saved shell group). Keying off the saved group instead left a re-plugged Shell
    // green-chipped and unusable, with no prompt to re-identify.
    function shellVerified(d) { return !!(d && d.verifiedMasterKeyId) }
    readonly property var unidentifiedCards: unidentified.filter(function(g) { return g.transport !== "shell" })
    // A wallet record is worth a card when the person has COMMITTED to it (saved accounts, a sealed
    // locked real wallet, or a name they gave it) OR its Keycard is connected right now. A seed
    // record with no accounts, not locked and not present is residue from a past card (e.g. a seed
    // replaced by a factory-reset + re-seed): it has no device and no way to act on it, so it is
    // hidden rather than left as an orphan "Unknown wallet" that can never be removed.
    function committed(g) { return root.hasAccounts(g) || g.locked === true || !!(g && g.name) }
    readonly property var visibleIdentified: identifiedWallets.filter(function(g) { return root.committed(g) || g.connected })
    // A keyless / legacy card's "Not identified yet" card is, by its own copy, about a CONNECTED
    // Keycard: show it only while that card is present, never as a disconnected leftover.
    readonly property var visibleUnidentifiedCards: unidentifiedCards.filter(function(g) { return g.connected })
    readonly property bool nothingToShow: root.ready && root.visibleIdentified.length === 0 && root.visibleUnidentifiedCards.length === 0 && root.pendingShells.length === 0
    property var dismissedShells: ({})
    // The Shell whose identify is in flight. Identify takes several on-device approvals (the wallet
    // key, then one per saved account), and the polled export state dips out of "working" between
    // them, so the notification holds its working state on this flag until the job ends, rather than
    // flicking back to "Identify" after the first approval.
    property string identifyingSerial: ""
    onExportingChanged: {
        var st = (root.exporting && root.exporting.state) || ""
        if (st === "done" || st === "failed") root.identifyingSerial = ""
    }
    readonly property var pendingShells: root.ready ? root.shellDevices.filter(function(d) {
        return !root.shellVerified(d) && !root.dismissedShells[d.serial]
    }) : []
    readonly property bool anyShellUnidentified: root.ready && root.shellDevices.some(function(d) { return !root.shellVerified(d) })
    // A dismissed Shell notification comes back when that Shell is re-seated: prune serials no longer present.
    onShellDevicesChanged: {
        var present = {}; root.shellDevices.forEach(function(d) { present[d.serial] = true })
        var keep = {}, changed = false
        for (var s in root.dismissedShells) { if (present[s]) keep[s] = true; else changed = true }
        if (changed) root.dismissedShells = keep
        if (root.identifyingSerial) {
            var d = root.shellDevices.find(function(x) { return x.serial === root.identifyingSerial })
            if (!d || root.shellVerified(d)) root.identifyingSerial = ""
        }
    }
    readonly property var accounts: ready ? j(backend.accountsJson, "[]") : []
    readonly property var unsigned: cards.filter(function(c) { return c.untrusted !== undefined })
    // Header connection state, from signals the view already has. The finer negative cases
    // (no reader vs empty reader vs reader-present-but-PCSC-rejected) need keycard_module to
    // report bare readers; tracked upstream. Here we honestly show what we can see.
    readonly property bool anyConnected: cards.length > 0 || shellDevices.length > 0
    // card present (green) is reliable. A bare reader cannot be told from no reader at all,
    // since keycard_module.cards() reports only readers that hold a card, so the empty case is
    // one honest "No card detected" (warning) until the module reports bare readers.
    readonly property string connLabel: !ready ? (startupStalled ? "Not responding" : "Starting")
        : cards.length > 0 ? "Card connected"
        : shellDevices.length > 0 ? "Shell connected"
        : "No card detected"
    readonly property color connColor: !ready ? (startupStalled ? Theme.palette.warning : Theme.palette.textSecondary)
        : anyConnected ? Theme.palette.success
        : Theme.palette.warning
    readonly property var exporting: ready ? j(backend.exportJson, "{}") : ({})
    readonly property bool working: exporting.state === "working" || exporting.state === "confirm_on_device"
    property string selectedWalletId: ""
    property var pendingWallet: null
    readonly property var wallet: wallets.find(function(g) { return g.id === selectedWalletId }) || pendingWallet
    property string selectedConnectionId: ""
    readonly property var connections: connectedDevices(wallet)
    // Which devices to list under a group. Under an identified wallet (seed:...), a Shell shows only
    // once it is verified to hold this wallet's seed; an unverified or different Shell is not this
    // wallet's device, it lives in its own "Not identified yet" block. A reader card is identified on
    // connect (its keyUid is in the plain SELECT), so it always shows. The unidentified Shell block
    // itself is a non-seed group, so its own Shell line is kept.
    function connectedDevices(group) {
        if (!group) return []
        var identified = (group.id || "").indexOf("seed:") === 0
        var conns = group.connections || [{transport: "shell", serial: group.serial, connected: group.connected}]
        return conns.filter(function(c) {
            if (!c.connected) return false
            if (identified && c.transport === "shell") return c.verification === "verified"
            return c.verification !== "different"
        })
    }
    function route(c) { return !c ? "" : c.transport === "shell" ? "shell:" + c.serial + ":" : c.id }
    readonly property var connection: connections.find(function(c) { return root.route(c) === root.selectedConnectionId }) || connections[0] || null
    readonly property bool shell: !!connection && connection.transport === "shell"
    readonly property var card: shell || !connection ? null : cards.find(function(c) { return cardId(c) === root.connection.id }) || null
    readonly property string reader: card ? card.reader : ""
    readonly property bool needsPairing: card !== null && card.secureChannel === 1 && !card.paired
    readonly property bool connected: !!connection && connection.connected

    function cardId(c) { return c.secureChannel === 2 ? "identity:" + c.identity : "instance:" + c.instanceUid }
    function shortId(id) { var s = (id || "").split(":").pop(); return s.length > 16 ? s.slice(0,8) + "…" + s.slice(-8) : s }
    // A wallet's accounts are sealed until the person unlocks it there.
    function unlockInSigner() {
        logos.request("wallets.unlock", ({}), function (res) { if (res.ok) root.backend.refresh() })
    }
    function groupName(g) {
        if (!g) return "Keycard"
        if (g.id.indexOf("seed:") === 0)
            return hasAccounts(g) ? (g.name || "Keycard wallet " + (fingerprintOf(g) || shortId(g.id)))
                                  : g.locked === true ? "Locked wallet" : "Unknown wallet"
        return g.name || (g.legacy ? "Unidentified Keycard" : g.transport === "shell" ? "Keycard Shell · not identified yet" : "Keycard · not identified yet")
    }
    // A card's rows, as the kit takes them: an EVM address, or a Bitcoin first receiving address.
    function rowsOf(g) {
        return ((g && g.accounts) || []).map(function(a) {
            var shown = (a.preview || {}).address || a.address || ""
            var aliases = a.aliases || []
            return { key: a.id, id: a.id, family: a.family, chain: a.chain, path: a.path,
                     label: aliases.length > 1 ? aliases.join(" · ") : a.label || "", ownLabel: a.label || "",
                     address: a.family === "evm" ? shown : "", firstAddress: a.family === "evm" ? "" : shown,
                     addressNote: (a.preview || {}).error || "Address unavailable" }
        })
    }
    // The master fingerprint its accounts carry: the Wallet ID the Signer and Keys apps show too.
    function fingerprintOf(g) {
        var a = ((g && g.accounts) || []).find(function(a) { return !!a.fingerprint })
        return a ? a.fingerprint : ""
    }
    // A known wallet has at least one account saved: that is also when its master fingerprint is
    // readable. A connected seed card with none is a Keycard whose wallet we do not know yet.
    function hasAccounts(g) { return (((g && g.accounts) || []).length) > 0 }
    // All of these act on the whole wallet, so they sit together beside its name.
    function walletActions(g) {
        var add = [{ id: "add", label: "Add accounts", enabled: g.connected && !root.working && !g.legacy && g.locked !== true }]
        // An unknown wallet (connected card, no accounts yet) has nothing to rename or forget: only
        // Add accounts (and Card administration, which rides on the connection strip).
        var unknown = g.legacy || g.pending || (g.id.indexOf("seed:") === 0 && !hasAccounts(g))
        return unknown ? add
            : add.concat([{ id: "rename", label: "Rename…" }])
                 .concat([{ id: "forget", label: "Forget wallet…" }])
    }
    function aliasesOf(g) { return (g.aliases || []).filter(function(n) { return n !== g.name }) }
    function cardFor(c) { return root.cards.find(function(k) { return cardId(k) === c.id }) || null }
    // The name stored on each connected card, read with a no-PIN status call and cached by adminId,
    // so the transport line can show it (e.g. "Realify") without a tap. The pending guard keeps the
    // read that triggers a refresh from looping: it fires once per card, then serves from cache.
    property var cardNameCache: ({})
    property var cardNamePending: ({})
    onCardsChanged: root.cards.forEach(function(c) { if (c && c.adminId) root.ensureCardName(c) })
    function ensureCardName(card) {
        if (!card || !card.adminId || !ready) return
        var k = card.adminId
        if (cardNameCache.hasOwnProperty(k) || cardNamePending[k]) return
        cardNamePending[k] = true
        var p = {action: "status", reader: card.reader, cardId: card.adminId, keyUid: card.keyUid || ""}
        logos.watch(backend.administer(JSON.stringify(p)), function(raw) {
            delete cardNamePending[k]
            var r; try { r = JSON.parse(raw) } catch(e) { r = {} }
            var c = cardNameCache; c[k] = (r && r.ok && r.cardName) ? r.cardName : ""; cardNameCache = c
        })
    }
    function cardNameFor(c) {
        var card = cardFor(c)
        return card && card.adminId && cardNameCache[card.adminId] ? cardNameCache[card.adminId] : ""
    }
    // Each device in use, a card trusted without Keycard's certificate, and an older Shell wallet.
    function stripsOf(g) {
        var out = [], trusted = 0
        connectedDevices(g).forEach(function(c, i) {
            var card = c.transport === "shell" ? null : cardFor(c)
            var nm = c.transport === "shell" ? "" : cardNameFor(c)
            // The device-type tag is rendered green, so the connection reads as made at a glance; the
            // rest (serial / name / card id) stays secondary. A Shell strip only shows once verified,
            // so its tail is the verified case.
            var tag = c.transport === "shell" ? "Shell USB" : "Card reader"
            var text = c.transport === "shell"
                ? shortId(c.serial) + (c.verification === "verified" ? " · verified" : c.verification === "different" ? " · different wallet" : " · verify on first use")
                : (nm ? nm + " · " : "") + "card " + shortId(c.id)
            out.push({ id: "device" + i, tag: tag, text: text, card: card,
                       actions: card ? [{ id: "admin", label: "Card administration", enabled: !root.working }] : [] })
            if (card && card.trustedByPerson === true)
                out.push({ id: trusted++ ? "trust" + trusted : "trust", text: "You trusted this card although Keycard did not certify it.",
                           warn: true, card: card, actions: [{ id: "stoptrust", label: "Stop trusting" }] })
        })
        if (out.length === 0) out.push({ id: "nodevice", text: "No device connected" })
        if (g.transport === "shell" && g.id.indexOf("seed:") !== 0)
            out.push({ id: "identify", text: "Identify this Shell wallet once to link its saved accounts.",
                       actions: [{ id: "identify", label: "Identify wallet…", enabled: g.connected && !root.working }] })
        return out
    }
    function familyWords(f) { return f === "evm" ? "Ethereum" : f === "bitcoin" ? "Bitcoin · Native SegWit" : "Bitcoin · Taproot" }
    function selectWallet(g) { selectedWalletId = g.id; selectedConnectionId = ""; pendingWallet = g.pending ? g : null }
    function openAdd(g) { selectWallet(g); addSheet.open() }
    function grouped(hex) { return (hex || "").replace(/(.{8})/g, "$1 ").trim() }

    ColumnLayout {
        id: appHeader
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: Theme.spacing.medium }
        spacing: Theme.spacing.small
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                spacing: 0
                RowLayout {
                    spacing: Theme.spacing.tiny
                    LogosText { text: "Keycard"; color: Theme.palette.text; font.pixelSize: 28; font.weight: Theme.typography.weightBold }
                    LogosInfoButton { objectName: "keycardWalletInfo"; title: "One wallet per seed"; Accessible.name: "Help: One wallet per seed"; text: "Wallets are identified by a hash of the full master public key. Cards holding the same seed share one wallet, across readers and USB Shells. A different recovery passphrase creates a different wallet. A Shell connection means USB is present, not that this seed is readable: the app cannot see which wallet is inside until you approve an Identify request on the Shell screen. Until then the Shell shows only as a notification and a yellow header chip, and no wallet card changes. Identify confirms the master public key on the device; the card then folds into its wallet (keeping saved account names), or opens as a new unknown wallet. That identification is reused for signing until the Shell disconnects or the app restarts. Every returned signature is checked against the selected account; a different seed is rejected. Names are saved on this computer." }
                }
                LogosText { text: "Wallets and card administration"; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
            }
            Item { Layout.fillWidth: true }
            RowLayout {
                spacing: Theme.spacing.tiny
                // One chip per live transport, so a Shell and a reader connected at once read as two
                // green states instead of one that hides the other. Falls back to a single status
                // chip while starting, or when nothing is connected.
                LogosBadge { objectName: "connectionStatus"; visible: !root.ready || (root.cards.length === 0 && root.shellDevices.length === 0); text: root.connLabel; color: root.connColor }
                LogosBadge { objectName: "connectionStatusReader"; visible: root.ready && root.cards.length > 0; text: "Card via reader"; color: Theme.palette.success }
                // Yellow while the Shell's card is not identified yet (we cannot see its seed until the
                // person approves an Identify request on the device); green once identified.
                LogosBadge { objectName: "connectionStatusShell"; visible: root.ready && root.shellDevices.length > 0; text: "Shell via USB"; color: root.anyShellUnidentified ? Theme.palette.warning : Theme.palette.success }
            }
            LogosIconButton { objectName: "refreshButton"; iconSource: root.iconRefresh; enabled: root.ready && !root.working; onClicked: root.backend.refresh() }
        }
        LogosTabBar {
            id: areaTabs; objectName: "areaTabs"; Layout.fillWidth: true
            LogosTabButton { objectName: "areaWallets"; text: "Wallets"; font.pixelSize: Theme.typography.secondaryText }
            LogosTabButton { objectName: "areaAdministration"; text: "Administration"; enabled: root.ready; font.pixelSize: Theme.typography.secondaryText }
        }
        RowLayout {
            objectName: "startupStalledBanner"
            visible: root.startupStalled && !root.ready
            Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small; spacing: Theme.spacing.small
            LogosText {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.warning
                text: "The Keycard service hasn't finished starting. This can happen after a restart. If it persists, fully quit and reopen Basecamp."
            }
            LogosButton { objectName: "startupRetry"; text: "Try again"; onClicked: { root.startupStalled = false; root.ready = root.backend !== null && logos.isViewModuleReady("keycard_ui") } }
        }
    }
    CardAdministration {
        id: adminSheet; backend: root.backend; cards: root.cards; cardGroups: root.cardGroups
        active: areaTabs.currentIndex === 1; visible: areaTabs.currentIndex === 1
        anchors { top: appHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom
                  leftMargin: Theme.spacing.medium; rightMargin: Theme.spacing.medium; bottomMargin: Theme.spacing.medium; topMargin: Theme.spacing.large }
    }
    LogosScrollView {
        id: scroll
        visible: areaTabs.currentIndex === 0
        anchors { top: appHeader.bottom; left: parent.left; right: parent.right; bottom: parent.bottom
                  leftMargin: Theme.spacing.medium; rightMargin: Theme.spacing.medium; bottomMargin: Theme.spacing.medium; topMargin: Theme.spacing.large }
        contentWidth: availableWidth
        ColumnLayout {
            width: Math.min(scroll.availableWidth, 560)
            x: Math.max(0, (scroll.availableWidth - width) / 2)
            spacing: Theme.spacing.medium
            ColumnLayout {
                visible: root.nothingToShow
                Layout.fillWidth: true; Layout.topMargin: Theme.spacing.xxlarge; Layout.alignment: Qt.AlignHCenter; spacing: Theme.spacing.small
                LogosText { Layout.alignment: Qt.AlignHCenter; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Theme.typography.subtitleText; font.weight: Theme.typography.weightBold; color: Theme.palette.text; text: "No Keycard wallets added" }
                LogosText { Layout.alignment: Qt.AlignHCenter; Layout.maximumWidth: 420; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: Theme.palette.textSecondary; text: "Connect a Keycard reader or a Keycard Shell over USB to add your first wallet. Your keys stay on the card." }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter; spacing: Theme.spacing.tiny
                    LogosLink { text: "Get a Keycard"; href: "https://keycard.tech/"; onActivated: function(url) { getKeycardCopy.copy(); Qt.openUrlExternally(url) } }
                    LogosCopyButton { id: getKeycardCopy; value: "https://keycard.tech/"; feedbackText: "URL copied"; size: 24; iconSize: 14 }
                }
            }
            LogosButton { objectName: "reviewUnverified"; visible: root.unsigned.length > 0; text: "Review unverified Keycard…"; onClicked: trustSheet.open() }
            LogosText { objectName: "keycardNotice"; visible: text !== ""; Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.PlainText; text: root.ready ? root.backend.noticeText : "" }
            // A connected Shell whose card is not identified yet: a dismissible notification, styled
            // apart from wallet cards (warning-tinted, not a card background) so it never reads as a
            // wallet. Nothing on the wallet list changes until the person sends Identify and approves
            // the request on the Shell screen; it then folds into its wallet, or opens an unknown one.
            Repeater {
                objectName: "shellIdentifyRepeater"
                model: root.pendingShells
                delegate: Rectangle {
                    id: shellNote
                    required property var modelData
                    // Held from the moment Identify is pressed until the job ends, so the card keeps
                    // its working state across the Shell's several approvals instead of resetting
                    // after the first one.
                    readonly property bool submitting: root.identifyingSerial === shellNote.modelData.serial
                    Layout.fillWidth: true
                    radius: 10
                    color: Qt.rgba(Theme.palette.warning.r, Theme.palette.warning.g, Theme.palette.warning.b, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(Theme.palette.warning.r, Theme.palette.warning.g, Theme.palette.warning.b, 0.45)
                    implicitHeight: noteCol.implicitHeight + 2 * Theme.spacing.medium
                    RowLayout {
                        id: noteRow
                        anchors.fill: parent; anchors.margins: Theme.spacing.medium
                        spacing: Theme.spacing.small
                        Rectangle { Layout.alignment: Qt.AlignTop; Layout.topMargin: 5; implicitWidth: 8; implicitHeight: 8; radius: 4; color: Theme.palette.warning }
                        ColumnLayout {
                            id: noteCol
                            Layout.fillWidth: true
                            spacing: Theme.spacing.tiny
                            RowLayout {
                                spacing: Theme.spacing.tiny
                                LogosText { text: "Shell connected"; font.weight: Theme.typography.weightBold; color: Theme.palette.text }
                                LogosText { text: "· " + root.shortId(shellNote.modelData.serial); color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                            }
                            LogosText {
                                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.textSecondary
                                font.pixelSize: Theme.typography.secondaryText
                                text: shellNote.submitting
                                    ? "Keep approving on your Shell screen until it stops asking. It confirms the wallet key, then checks each saved account, so it may ask several times."
                                    : "The card inside can be identified only after you approve on the Shell screen. The Shell asks for the wallet key and then checks each saved account, so expect more than one approval. Send it with Identify."
                            }
                            RowLayout {
                                Layout.topMargin: Theme.spacing.tiny
                                spacing: Theme.spacing.small
                                LogosButton {
                                    objectName: "shellIdentifyButton"
                                    text: shellNote.submitting ? "Approve on Shell…" : "Identify"
                                    variant: LogosButton.Variant.Primary
                                    enabled: !shellNote.submitting && !root.working
                                    onClicked: { root.identifyingSerial = shellNote.modelData.serial; logos.watch(root.backend.identifyWallet(shellNote.modelData.serial), function(ok) { if (!ok) root.identifyingSerial = "" }) }
                                }
                                LogosButton {
                                    objectName: "shellIdentifyDismiss"
                                    text: "Dismiss"; enabled: !shellNote.submitting && !root.working
                                    onClicked: { var dd = root.dismissedShells; dd[shellNote.modelData.serial] = true; root.dismissedShells = dd }
                                }
                            }
                        }
                    }
                }
            }
            // A keyless card (no keys loaded) connected RIGHT NOW: kept apart so a device is not read
            // as a wallet, and placed above the wallet list because it is the card in hand needing
            // action. Connected Shells are handled by the notification above, not here. Hidden once the
            // card is removed (its copy is about a connected Keycard).
            LogosText {
                visible: root.visibleUnidentifiedCards.length > 0
                Layout.fillWidth: true
                text: "Not identified yet"; font.pixelSize: Theme.typography.subtitleText; font.weight: Theme.typography.weightBold; color: Theme.palette.text
            }
            LogosText {
                visible: root.visibleUnidentifiedCards.length > 0
                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.textSecondary
                text: "A connected Keycard whose wallet is not known yet. A card with no keys loaded has no wallet to show."
            }
            Repeater { objectName: "unidentifiedRepeater"; model: root.visibleUnidentifiedCards; delegate: walletDelegate }
            // Wallets: a keypair, identified by its master key. Same key on any card/Shell = one block.
            Repeater { objectName: "cardGroupRepeater"; model: root.visibleIdentified; delegate: walletDelegate }
            Component {
                id: walletDelegate
                Accounts.WalletCard {
                    id: group
                    required property var modelData
                    required property int index
                    readonly property var g: modelData
                    Layout.fillWidth: true
                    namePrefix: "wallet" + index + "_"
                    title: root.groupName(g)
                    walletId: root.fingerprintOf(g)
                    walletIdFull: (g.id || "").split(":").pop()
                    editIcon: root.iconEdit
                    trashIcon: root.iconTrash
                    emptyText: root.hasAccounts(g) ? "No accounts yet." : ""
                    lines: root.aliasesOf(g).length ? ["Also named: " + root.aliasesOf(g).join(" · ")] : []
                    strips: root.stripsOf(g)
                    locked: g.locked === true
                    // Unlocking goes through the Signer, which asks for THIS card's PIN — so it is
                    // only possible with the card present. Off the reader, Unlock is not actionable:
                    // disable it and say to connect the card first, rather than offer a dead button.
                    lockedText: g.connected
                        ? "Unlock it in the Signer app to show its ID and accounts. The Signer asks for this card's PIN."
                        : "Connect this wallet's Keycard, then unlock it in the Signer app. Unlocking needs the card and its PIN."
                    lockedActions: [{ id: "unlock", label: g.connected ? "Unlock" : "Connect card to unlock", enabled: root.ready && g.connected }]
                    accounts: root.rowsOf(g)
                    actions: root.walletActions(g)
                    accountActions: [{ id: "rename", label: "Rename…", enabled: !root.working },
                                     { id: "remove", label: "Remove", enabled: !root.working,
                                       tip: "Hides it from apps, including for other cards sharing the same recovery phrase. Nothing on the card changes." }]
                    onAction: function (id) {
                        if (id === "add") root.openAdd(group.g)
                        else if (id === "unlock") root.unlockInSigner()
                        else if (id === "rename") { root.selectWallet(group.g); renameWalletSheet.open() }
                        else if (id === "forget") { forgetSheet.cardId = group.g.id; forgetSheet.cardName = root.groupName(group.g); forgetSheet.open() }
                    }
                    onStripAction: function (i, id) {
                        var strip = group.strips[i]
                        if (id === "admin") { adminSheet.preferredCard = strip.card.adminId; areaTabs.currentIndex = 1 }
                        else if (id === "stoptrust") logos.watch(root.backend.forgetCard(strip.card.identity), function(ok) {})
                        else if (id === "identify") { root.selectWallet(group.g); identifySheet.open() }
                    }
                    onAccountAction: function (id, entry) {
                        if (id === "remove") { logos.watch(root.backend.removeWalletAccount(group.g.id, entry.id), function(ok) {}); return }
                        renameAccountSheet.walletId = group.g.id
                        renameAccountSheet.accountId = entry.id
                        renameAccountSheet.accountLabel = entry.ownLabel
                        renameAccountSheet.accountDetails = entry.address || entry.firstAddress || entry.path || entry.id
                        renameAccountSheet.open()
                    }
                }
            }
            LogosText { visible: root.ready && !!root.backend.lastError; Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.PlainText; color: Theme.palette.error; text: root.ready ? root.backend.lastError : "" }
        }
    }

    AddAccountsFlow {
        id: addSheet
        backend: root.backend
        ready: root.ready
        walletId: root.selectedWalletId
        wallet: root.wallet
        walletName: root.groupName(root.wallet)
        connection: root.connection
        connections: root.connections
        shell: root.shell
        card: root.card
        reader: root.reader
        needsPairing: root.needsPairing
        connected: root.connected
        working: root.working
        exporting: root.exporting
    }
    LogosDialog {
        id: identifySheet; objectName: "identifyWalletDialog"; title: "Identify wallet"
        anchors.centerIn: parent; width: Math.min(parent.width - 40, 540)
        closePolicy: root.working ? Popup.NoAutoClose : Popup.CloseOnEscape
        contentItem: ColumnLayout {
            LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Unlock the wallet on the Shell. Confirm the master public-key request and the saved account checks on its screen. Matching accounts will join the same wallet as your readers and other Shells, keeping their names." }
            LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.PlainText; text: root.working ? "Confirm the public-key requests on your Shell…" : root.exporting.state === "done" ? "Wallet identified. Matching accounts are now grouped together." : root.exporting.error || "" }
            RowLayout {
                LogosButton { text: "Close"; enabled: !root.working; onClicked: identifySheet.close() }
                Item { Layout.fillWidth: true }
                LogosButton { objectName: "identifyWalletButton"; text: "Identify wallet"; enabled: root.connected && !root.working; onClicked: logos.watch(root.backend.identifyWallet(root.connection.serial), function(ok) {}) }
            }
        }
    }
    LogosDialog {
        id: renameWalletSheet; objectName: "renameWalletDialog"; title: "Rename wallet"
        anchors.centerIn: parent; width: Math.min(parent.width - 40, 520)
        property bool saving: false
        property string errorText: ""
        closePolicy: saving ? Popup.NoAutoClose : Popup.CloseOnEscape
        onOpened: { walletName.text = root.wallet ? root.wallet.name || "" : ""; errorText = ""; saving = false; walletName.forceActiveFocus() }
        contentItem: ColumnLayout {
            LogosTextField { id: walletName; objectName: "walletName"; Layout.fillWidth: true; placeholderText: "Wallet name"; textInput.maximumLength: 80; enabled: !renameWalletSheet.saving }
            LogosText { text: "Every app shows this name, the Signer app included. Cards and Shells holding this seed share it."; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.textSecondary }
            LogosText { text: renameWalletSheet.errorText; textFormat: Text.PlainText; visible: !!text; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.error }
            RowLayout {
                LogosButton { text: "Cancel"; enabled: !renameWalletSheet.saving; onClicked: renameWalletSheet.close() }
                Item { Layout.fillWidth: true }
                LogosButton {
                    objectName: "saveWalletName"; text: "Save name"; enabled: !renameWalletSheet.saving
                    onClicked: {
                        renameWalletSheet.saving = true
                        logos.watch(root.backend.renameCard(root.selectedWalletId, walletName.text), function(ok) {
                            renameWalletSheet.saving = false
                            if (ok) renameWalletSheet.close()
                            else renameWalletSheet.errorText = root.backend.lastError
                        })
                    }
                }
            }
        }
    }
    LogosDialog {
        id: renameAccountSheet; objectName: "renameAccountDialog"; title: "Rename account"
        anchors.centerIn: parent; width: Math.min(parent.width - 40, 520)
        property string walletId: ""
        property string accountId: ""
        property string accountLabel: ""
        property string accountDetails: ""
        property bool saving: false
        property string errorText: ""
        closePolicy: saving ? Popup.NoAutoClose : Popup.CloseOnEscape
        onOpened: { accountName.text = accountLabel; errorText = ""; saving = false; accountName.forceActiveFocus() }
        contentItem: ColumnLayout {
            LogosText { text: renameAccountSheet.accountDetails; textFormat: Text.PlainText; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }
            LogosTextField { id: accountName; objectName: "accountName"; Layout.fillWidth: true; placeholderText: "Account name"; textInput.maximumLength: 80; enabled: !renameAccountSheet.saving }
            LogosText { text: "This name is saved locally and shown to apps. Leave it blank to use the default label."; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.textSecondary }
            LogosText { text: renameAccountSheet.errorText; textFormat: Text.PlainText; visible: !!text; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.error }
            RowLayout {
                LogosButton { text: "Cancel"; enabled: !renameAccountSheet.saving; onClicked: renameAccountSheet.close() }
                Item { Layout.fillWidth: true }
                LogosButton {
                    objectName: "saveAccountName"; text: "Save name"; enabled: !renameAccountSheet.saving
                    onClicked: {
                        renameAccountSheet.saving = true
                        logos.watch(root.backend.renameAccount(renameAccountSheet.walletId, renameAccountSheet.accountId, accountName.text), function(ok) {
                            renameAccountSheet.saving = false
                            if (ok) renameAccountSheet.close()
                            else renameAccountSheet.errorText = root.backend.lastError
                        })
                    }
                }
            }
        }
    }
    // Trusted, or taken out of its reader: nothing is left to review.
    Connections {
        target: root
        function onUnsignedChanged() { if (root.unsigned.length === 0) trustSheet.close() }
    }
    LogosDialog {
        id: trustSheet; objectName: "trustDialog"; title: "Review Keycard identity"
        anchors.centerIn: parent; width: Math.min(parent.width-40, 680)
        contentItem: ColumnLayout {
            Rectangle {
                objectName: "untrustedPanel"
                visible: root.unsigned.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: untrustedColumn.implicitHeight + 2 * Theme.spacing.medium
                color: "transparent"
                border.color: Theme.palette.error
                border.width: 2
                radius: 6
                ColumnLayout {
                    id: untrustedColumn
                    x: Theme.spacing.medium
                    y: Theme.spacing.medium
                    width: parent.width - 2 * Theme.spacing.medium
                    spacing: Theme.spacing.small
                    LogosText {
                        text: "This card is not certified by Keycard"
                        font.bold: true
                        color: Theme.palette.error
                    }
                    LogosText {
                        objectName: "untrustedWarning"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        wrapMode: Text.WordWrap
                        text: "Keycard didn't sign this card's identity. It may be a card someone loaded "
                              + "the Keycard software onto, or a counterfeit made to look like a Keycard. "
                              + "A counterfeit could keep your PIN or your keys and send them to whoever "
                              + "made it. Trust it only if you put the Keycard applet on this card yourself, "
                              + "and its identity below is the one you gave it."
                    }
                    LogosText {
                        objectName: "untrustedIdentity"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        wrapMode: Text.WrapAnywhere
                        textFormat: Text.PlainText
                        font.family: "monospace"
                        text: root.unsigned.length > 0
                              ? "Its identity: " + root.grouped(root.unsigned[0].untrusted) : ""
                    }
                    LogosCheckbox {
                        id: ownCard
                        objectName: "trustOwnCard"
                        text: "I put the Keycard applet on this card myself"
                    }
                    LogosButton {
                        objectName: "trustButton"
                        text: "Trust this card"
                        enabled: root.ready && ownCard.checked && root.unsigned.length > 0
                        onClicked: logos.watch(root.backend.trustCard(root.unsigned[0].reader,
                                                                      root.unsigned[0].untrusted),
                                               function (trusted) { ownCard.checked = false; if (trusted) trustSheet.close() })
                    }
                }
            }
            LogosButton { text: "Close"; onClicked: trustSheet.close() }
        }
    }
    LogosDialog {
        id: forgetSheet
        objectName: "forgetSavedCardDialog"
        title: "Forget wallet?"
        property string cardId: ""
        property string cardName: ""
        property bool working: false
        readonly property var group: root.wallets.find(function(g) { return g.id === forgetSheet.cardId })
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 580)
        onOpened: working = false
        contentItem: ColumnLayout {
            spacing: Theme.spacing.medium
            LogosText {
                Layout.fillWidth: true
                text: forgetSheet.cardName
                textFormat: Text.PlainText
                wrapMode: Text.WrapAnywhere
                font.bold: true
            }
            LogosText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Remove this wallet's saved accounts and name from this computer. Nothing on the Keycard or Shell is erased. While its Keycard stays connected it returns as an unknown wallet, ready to set up again."
            }
            LogosText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                color: Theme.palette.error
                text: root.ready ? root.backend.lastError : ""
            }
            RowLayout {
                LogosButton {
                    objectName: "cancelForgetSavedCard"
                    text: "Cancel"
                    enabled: !forgetSheet.working
                    onClicked: forgetSheet.close()
                }
                Item { Layout.fillWidth: true }
                LogosButton {
                    objectName: "confirmForgetSavedCard"
                    text: forgetSheet.working ? "Forgetting…" : "Forget wallet"
                    enabled: !!forgetSheet.group && !forgetSheet.working
                    onClicked: {
                        forgetSheet.working = true
                        logos.watch(root.backend.forgetSavedCard(forgetSheet.cardId), function(ok) {
                            forgetSheet.working = false
                            if (ok) forgetSheet.close()
                        })
                    }
                }
            }
        }
    }

}
