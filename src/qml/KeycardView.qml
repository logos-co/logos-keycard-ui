import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

Item {
    id: root
    objectName: "keycardRoot"
    anchors.fill: parent
    Rectangle { anchors.fill: parent; color: Theme.palette.background }
    readonly property var backend: logos.module("keycard_ui")
    property bool ready: false
    Component.onCompleted: ready = backend !== null && logos.isViewModuleReady("keycard_ui")
    Connections {
        target: logos
        function onViewModuleReadyChanged(name, isReady) {
            if (name === "keycard_ui") root.ready = isReady && root.backend !== null
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
    readonly property var accounts: ready ? j(backend.accountsJson, "[]") : []
    readonly property var unsigned: cards.filter(function(c) { return c.untrusted !== undefined })
    readonly property var exporting: ready ? j(backend.exportJson, "{}") : ({})
    readonly property bool working: exporting.state === "working" || exporting.state === "confirm_on_device"
    property string selectedWalletId: ""
    property var pendingWallet: null
    readonly property var wallet: wallets.find(function(g) { return g.id === selectedWalletId }) || pendingWallet
    property string selectedConnectionId: ""
    readonly property var connections: connectedDevices(wallet)
    function connectedDevices(group) { return group ? (group.connections || [{transport: "shell", serial: group.serial, connected: group.connected}]).filter(function(c) { return c.connected }) : [] }
    function route(c) { return !c ? "" : c.transport === "shell" ? "shell:" + c.serial + ":" : c.id }
    readonly property var connection: connections.find(function(c) { return root.route(c) === root.selectedConnectionId }) || connections[0] || null
    readonly property bool shell: !!connection && connection.transport === "shell"
    readonly property var card: shell || !connection ? null : cards.find(function(c) { return cardId(c) === root.connection.id }) || null
    readonly property string reader: card ? card.reader : ""
    readonly property bool needsPairing: card !== null && card.secureChannel === 1 && !card.paired
    readonly property bool connected: !!connection && connection.connected
    onCardChanged: { pinField.text = ""; pairingField.text = "" }

    function cardId(c) { return c.secureChannel === 2 ? "identity:" + c.identity : "instance:" + c.instanceUid }
    function shortId(id) { var s = (id || "").split(":").pop(); return s.length > 16 ? s.slice(0,8) + "…" + s.slice(-8) : s }
    function shortAddress(a) { return a ? a.slice(0,8) + "…" + a.slice(-6) : "" }
    // A wallet's accounts are sealed until the person unlocks it there.
    function unlockInSigner() {
        logos.request("wallets.unlock", ({}), function (res) { if (res.ok) root.backend.refresh() })
    }
    function groupName(g) {
        if (!g) return "Keycard"
        if (g.id.indexOf("seed:") === 0) return g.name || "Keycard wallet " + shortId(g.id)
        return g.name || (g.legacy ? "Unidentified card" : g.transport === "shell" ? "Keycard via Shell" + (g.fingerprint ? " · " + g.fingerprint : "") : "Keycard " + shortId(g.id))
    }
    function familyWords(f) { return f === "evm" ? "Ethereum" : f === "bitcoin" ? "Bitcoin · Native SegWit" : "Bitcoin · Taproot" }
    function selectWallet(g) { selectedWalletId = g.id; selectedConnectionId = ""; pendingWallet = g.pending ? g : null }
    function openAdd(g) { selectWallet(g); addSheet.open() }
    function grouped(hex) { return (hex || "").replace(/(.{8})/g, "$1 ").trim() }

    CardAdministration { id: adminSheet; backend: root.backend; cards: root.cards }
    LogosScrollView {
        id: scroll
        anchors.fill: parent; anchors.margins: Theme.spacing.medium
        contentWidth: availableWidth
        ColumnLayout {
            width: scroll.availableWidth; spacing: Theme.spacing.medium
            RowLayout {
                Layout.fillWidth: true
                LogosText { text: "Keycard wallets"; font.pixelSize: 22 }
                LogosInfoButton { objectName: "keycardWalletInfo"; title: "One wallet per seed"; Accessible.name: "Help: One wallet per seed"; text: "Wallets are identified by a hash of the full master public key. Cards holding the same seed share one wallet, across readers and USB Shells. A different recovery passphrase creates a different wallet. Identify an older Shell wallet once and confirm its public-key requests to link its saved accounts. Previous wallet and account names are retained. A Shell connection means USB is present, not that this seed is inside. Any connected Shell can be used. The first use of each USB connection asks you to confirm the master public key. Subsequent signatures reuse that verification until the Shell disconnects or the app restarts. Use Manage → Verify wallet to request a fresh check at any time. Every returned signature is checked against the selected account. If the card has a different seed, the result is rejected; insert the correct card and retry. Names are saved on this computer." }
                Item { Layout.fillWidth: true }
                LogosButton { objectName: "cardAdministration"; text: "Card administration…"; enabled: root.ready && !root.working; onClicked: adminSheet.open() }
                LogosButton { objectName: "connectShell"; text: "Open wallet via USB…"; visible: root.shellDevices.length > 0; enabled: !root.working; onClicked: shellSheet.open() }
                LogosButton { text: "Refresh"; enabled: root.ready && !root.working; onClicked: root.backend.refresh() }
            }
            LogosText {
                Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.textSecondary
                text: "Connect a Keycard reader or a Keycard Shell over USB. Your keys stay on the card."
            }
            LogosText { visible: root.ready && root.wallets.length === 0; text: "Connect a Keycard to add your first wallet." }
            LogosButton { visible: root.unsigned.length > 0; text: "Review unverified Keycard…"; onClicked: trustSheet.open() }
            Repeater {
                objectName: "cardGroupRepeater"; model: root.wallets
                delegate: Frame {
                    id: group
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    padding: Theme.spacing.medium
                    background: Rectangle { radius: 6; color: Theme.palette.backgroundMuted }
                    contentItem: ColumnLayout {
                        spacing: Theme.spacing.small
                        RowLayout {
                            Layout.fillWidth: true
                            ColumnLayout {
                                Layout.fillWidth: true
                                LogosText { objectName: "cardName_" + group.index; text: root.groupName(group.modelData); textFormat: Text.PlainText; Layout.fillWidth: true; elide: Text.ElideRight; font.bold: true }
                                LogosText {
                                    Layout.fillWidth: true; elide: Text.ElideRight; color: Theme.palette.textSecondary; textFormat: Text.PlainText
                                    text: root.connectedDevices(group.modelData).map(function(c) { return (c.transport === "shell" ? "Shell USB · " + root.shortId(c.serial) : "Card reader · " + root.shortId(c.id)) + (c.transport === "shell" ? (c.verification === "verified" ? " · USB connected; wallet verified" : c.verification === "different" ? " · USB connected; different wallet" : " · USB connected; verify on first use") : " · Connected") }).join("  /  ") || "No device connected"
                                }
                            }
                            LogosButton { objectName: "addAccounts_" + group.index; text: "Add accounts"; enabled: group.modelData.connected && !root.working && !group.modelData.legacy; onClicked: root.openAdd(group.modelData) }
                            LogosButton { objectName: "manageWallet_" + group.index; text: "Manage…"; enabled: !root.working && !group.modelData.pending; onClicked: { root.selectWallet(group.modelData); manageSheet.open() } }
                        }
                        LogosText { visible: (group.modelData.aliases || []).filter(function(n) { return n !== group.modelData.name }).length > 0; text: "Also named: " + (group.modelData.aliases || []).filter(function(n) { return n !== group.modelData.name }).join(" · "); textFormat: Text.PlainText; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.textSecondary }
                        LogosButton { text: "Identify wallet…"; visible: group.modelData.transport === "shell" && group.modelData.id.indexOf("seed:") !== 0; enabled: group.modelData.connected && !root.working; onClicked: { root.selectWallet(group.modelData); identifySheet.open() } }
                        RowLayout {
                            visible: group.modelData.locked === true
                            Layout.fillWidth: true
                            LogosText { objectName: "walletLocked_" + group.index; Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.PlainText
                                        color: Theme.palette.textSecondary
                                        text: "Locked · its accounts show once you unlock it in the Signer app." }
                            LogosButton { objectName: "unlockWallet_" + group.index; text: "Unlock"; enabled: root.ready; onClicked: root.unlockInSigner() }
                        }
                        LogosText { visible: group.modelData.accounts.length === 0 && group.modelData.locked !== true; text: "No accounts yet."; color: Theme.palette.textSecondary }
                        Repeater {
                            model: group.modelData.accounts
                            delegate: RowLayout {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    LogosText { text: (modelData.aliases || []).length > 1 ? modelData.aliases.join(" · ") : modelData.label || root.familyWords(modelData.family); textFormat: Text.PlainText; Layout.fillWidth: true; elide: Text.ElideRight }
                                    LogosText { objectName: "accountPath_" + group.index + "_" + index; text: "Derivation path: " + (modelData.path || "Unavailable"); textFormat: Text.PlainText; color: Theme.palette.textSecondary }
                                    RowLayout {
                                        readonly property string address: (modelData.preview || {}).address || modelData.address || ""
                                        LogosText { text: modelData.family === "evm" ? "Address:" : modelData.chain === "test" ? "First receiving address (testnet/signet, 0/0):" : "First receiving address (0/0):"; color: Theme.palette.textSecondary }
                                        LogosText { objectName: "accountLine_" + group.index + "_" + index; text: parent.address ? root.shortAddress(parent.address) : (modelData.preview || {}).error || "Address unavailable"; textFormat: Text.PlainText; color: Theme.palette.textSecondary }
                                        LogosCopyButton { objectName: "accountCopy_" + group.index + "_" + index; visible: !!parent.address; value: parent.address }
                                    }
                                }
                                LogosText { text: root.familyWords(modelData.family) + (modelData.chain === "test" ? " · Test" : ""); color: Theme.palette.textSecondary }
                            }
                        }
                    }
                }
            }
            LogosText { visible: root.ready && !!root.backend.lastError; Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.PlainText; color: Theme.palette.error; text: root.ready ? root.backend.lastError : "" }
        }
    }

    LogosDialog {
        id: addSheet; objectName: "addAccountsDialog"
        title: "Add accounts · " + root.groupName(root.wallet)
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 640); height: Math.min(parent.height - 40, 760)
        closePolicy: root.working || submitting ? Popup.NoAutoClose : Popup.CloseOnEscape
        property bool submitting: false
        // 0 · choose accounts, 1 · name them.
        property int step: 0
        property int from: 0
        property var rows: []
        property var selected: []
        // Each selected account's own name, by its row key: kept apart so typing doesn't rebuild the rows.
        property var names: ({})
        property string notice: ""
        // The job under way: "preview", "keep", or none.
        property string asked: ""
        readonly property string family: coin.currentIndex === 0 ? "evm" : script.currentIndex === 0 ? "bitcoin" : "bitcoin_taproot"
        readonly property string chain: network.currentIndex === 0 ? "main" : "test"
        readonly property bool canAsk: root.ready && root.connected && !root.needsPairing && !root.working && !submitting
                                       && (root.shell || pinField.text.length === 6)
        function rowKey(r) { return r.family + ":" + r.chain + ":" + r.index }
        function chosen(key) { return selected.some(function(r) { return r.key === key }) }
        function toggle(r, on) {
            var copy = selected.filter(function(s) { return s.key !== r.key })
            if (on) copy.push(r)
            selected = copy
        }
        function present(a) {
            return ((root.wallet && root.wallet.accounts) || []).some(function(b) {
                return a.id === b.id || (b.sources || []).some(function(o) { return o.id === a.id })
            })
        }
        function entry(family, chain, index, label) {
            var e = { family: family, account: index }
            if (family !== "evm") e.chain = chain
            if (label) e.label = label
            return e
        }
        // Five accounts from `start`, read from the device and kept nowhere yet.
        function show(start) {
            from = Math.max(0, start); firstIndex.text = String(from)
            var entries = []
            for (var i = 0; i < 5; i++) entries.push(entry(family, chain, from + i, ""))
            run("preview", { entries: entries, preview: true }, pinField.text)
        }
        // The picks, each its own name or none, kept from the previews without the device.
        function keep() {
            var entries = selected.map(function(r) { return entry(r.family, r.chain, r.index, (names[r.key] || "").trim()) })
            run("keep", { entries: entries, fromPreview: true }, "")
        }
        function run(what, request, secret) {
            notice = ""; submitting = true; asked = what
            logos.watch(root.backend.addAccounts(root.selectedWalletId, root.route(root.connection), JSON.stringify(request), secret), function(ok) {
                addSheet.submitting = false
                if (!ok) addSheet.asked = ""
            })
        }
        function shown(accounts) {
            return accounts.map(function(a) {
                var r = { family: a.family, chain: a.family === "evm" ? "" : (a.chain || addSheet.chain),
                          index: parseInt((a.path || "").split("/").pop()), path: a.path || "",
                          address: (a.preview || {}).address || a.address || "", present: addSheet.present(a) }
                r.key = addSheet.rowKey(r)
                return r
            })
        }
        onOpened: {
            step = 0; from = 0; rows = []; selected = []; names = ({}); notice = ""; asked = ""; submitting = false
            coin.currentIndex = 0; script.currentIndex = 0; network.currentIndex = 0; firstIndex.text = "0"; pinField.text = ""
        }
        onClosed: { pinField.text = ""; pairingField.text = ""; rows = []; selected = []; names = ({}); asked = "" }
        Connections {
            target: root
            function onExportingChanged() {
                if (!addSheet.opened || !addSheet.asked) return
                var state = root.exporting.state
                if (state === "failed") { addSheet.notice = root.exporting.error || "The device did not answer."; addSheet.asked = ""; return }
                if (state !== "done") return
                var was = addSheet.asked
                addSheet.asked = ""
                if (was === "preview") addSheet.rows = addSheet.shown(root.exporting.accounts || [])
                else addSheet.close()
            }
        }
        contentItem: ColumnLayout {
            spacing: Theme.spacing.small
            LogosText { color: Theme.palette.textSecondary; text: addSheet.step === 0 ? "1 · Choose accounts" : "2 · Name them" }
            LogosScrollView {
                id: addScroll
                Layout.fillWidth: true; Layout.fillHeight: true
                contentWidth: availableWidth
                ColumnLayout {
                    width: addScroll.availableWidth
                    spacing: Theme.spacing.small
                    ColumnLayout {
                        visible: addSheet.step === 0; Layout.fillWidth: true
                        LogosText {
                            Layout.fillWidth: true; wrapMode: Text.WordWrap
                            text: root.shell ? "Unlock the wallet on your Shell. Each address shown is a public-key request to confirm on its screen."
                                             : "Enter the card's PIN to show its accounts. Only public keys leave the card."
                        }
                        LogosComboBox {
                            objectName: "walletConnection"; visible: root.connections.length > 1; Layout.fillWidth: true
                            model: root.connections.map(function(c) { return (c.transport === "shell" ? "Shell USB · " + root.shortId(c.serial) : "Reader · " + root.shortId(c.id)) })
                            currentIndex: root.connections.indexOf(root.connection)
                            enabled: !root.working && !addSheet.submitting
                            onActivated: { root.selectedConnectionId = root.route(root.connections[currentIndex]); addSheet.rows = [] }
                        }
                        LogosText { visible: !root.connected; text: "Connect this wallet to continue."; color: Theme.palette.error }
                        LogosText { visible: root.needsPairing; Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Automatic pairing is unavailable for this card. Enter the pairing password from its setup to pair manually." }
                        RowLayout {
                            visible: root.needsPairing; Layout.fillWidth: true
                            LogosInfoButton { objectName: "pairingInfo"; title: "Pairing password"; Accessible.name: "Help: Pairing password"; text: "Pairing lets this app establish a secure connection to the card. Its password comes from the setup that initialized the card and is separate from the PIN. The app first tries KeycardDefaultPairing, the standard default for 3.x cards. If that does not work, enter your custom pairing password here. The app keeps the resulting pairing, not the password. If you do not know it, check the app or tool used to set up this card." }
                            LogosTextField { id: pairingField; objectName: "pairingField"; Layout.fillWidth: true; echoMode: TextInput.Password; placeholderText: "Pairing password" }
                            LogosButton { objectName: "pairButton"; text: "Pair"; enabled: !!pairingField.text && !addSheet.submitting; onClicked: {
                                var secret = pairingField.text; pairingField.text = ""; addSheet.submitting = true
                                logos.watch(root.backend.pair(root.reader, secret), function(ok) { addSheet.submitting = false })
                            } }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            LogosComboBox { id: coin; objectName: "accountType"; model: ["Ethereum", "Bitcoin"]; enabled: !root.working && !addSheet.submitting; onActivated: addSheet.rows = [] }
                            LogosComboBox { id: script; objectName: "bitcoinType"; visible: coin.currentIndex === 1; Layout.fillWidth: true; model: root.shell || (root.card && root.card.taproot) ? ["Native SegWit", "Taproot"] : ["Native SegWit"]; enabled: !root.working && !addSheet.submitting; onActivated: addSheet.rows = [] }
                            LogosComboBox { id: network; objectName: "accountNetwork"; visible: coin.currentIndex === 1; model: ["Bitcoin", "Test networks"]; enabled: !root.working && !addSheet.submitting; onActivated: addSheet.rows = [] }
                            Item { Layout.fillWidth: coin.currentIndex === 0 }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            LogosText { text: "First index" }
                            LogosTextField { id: firstIndex; objectName: "firstIndex"; Layout.fillWidth: true; text: "0"; enabled: !root.working && !addSheet.submitting; validator: IntValidator { bottom: 0; top: 2147483643 } }
                            LogosInfoButton { objectName: "cardDerivationInfo"; title: "Account indexes"; Accessible.name: "Help: Account indexes"; text: "An index is the last part of the derivation path: each one is a different account from the same recovery seed. Ethereum gives one address per index; a Bitcoin account holds receive and change addresses, and its first receiving address is shown. Adding accounts exports public information so apps can display them; spending still needs the device." }
                        }
                        LogosText {
                            objectName: "derivationPath"; color: Theme.palette.textSecondary
                            text: coin.currentIndex === 0 ? "m/44'/60'/0'/0/index" : "m/" + (script.currentIndex === 0 ? "84" : "86") + "'/" + (network.currentIndex === 0 ? "0" : "1") + "'/index'"
                        }
                        LogosTextField { id: pinField; objectName: "offerPin"; visible: !root.shell && !root.needsPairing; Layout.fillWidth: true; enabled: !root.working && !addSheet.submitting; echoMode: TextInput.Password; placeholderText: "Card PIN"; validator: RegularExpressionValidator { regularExpression: /[0-9]{0,6}/ } }
                        LogosButton {
                            objectName: "showAccounts"; text: "Show accounts"
                            enabled: addSheet.canAsk && firstIndex.acceptableInput
                            onClicked: addSheet.show(Number(firstIndex.text))
                        }
                        Repeater {
                            model: addSheet.rows
                            delegate: Frame {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                RowLayout {
                                    anchors.fill: parent
                                    LogosCheckbox {
                                        objectName: "selectAccount_" + index
                                        checked: addSheet.chosen(modelData.key)
                                        enabled: !root.working && !addSheet.submitting && !modelData.present && (checked || addSheet.selected.length < 20)
                                        onToggled: addSheet.toggle(modelData, checked)
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        LogosText { text: "Index " + modelData.index + (modelData.present ? " · Already added" : "") }
                                        LogosText { Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText; text: modelData.address || "Address unavailable" }
                                        LogosText { Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; color: Theme.palette.textSecondary; text: modelData.path }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            visible: addSheet.rows.length > 0; Layout.fillWidth: true
                            LogosButton { objectName: "previousAccounts"; text: "Previous"; enabled: addSheet.canAsk && addSheet.from > 0; onClicked: addSheet.show(addSheet.from - 5) }
                            LogosText { text: addSheet.from + "–" + (addSheet.from + 4) }
                            LogosButton { objectName: "nextAccounts"; text: "Next"; enabled: addSheet.canAsk && addSheet.from < 2147483639; onClicked: addSheet.show(addSheet.from + 5) }
                            Item { Layout.fillWidth: true }
                        }
                    }
                    ColumnLayout {
                        visible: addSheet.step === 1; Layout.fillWidth: true
                        LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Name each account, or leave it empty: an unnamed account shows as its kind and address." }
                        Repeater {
                            model: addSheet.selected
                            delegate: ColumnLayout {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                LogosText {
                                    Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                                    text: root.familyWords(modelData.family) + (modelData.chain === "test" ? " · Test" : "") + " · " + modelData.path + "\n" + modelData.address
                                }
                                LogosTextField {
                                    objectName: "addAccountName_" + index
                                    Layout.fillWidth: true
                                    placeholderText: "Account name (optional)"; textInput.maximumLength: 80
                                    text: addSheet.names[modelData.key] || ""
                                    onTextChanged: addSheet.names[modelData.key] = text
                                }
                            }
                        }
                    }
                    LogosText {
                        visible: root.working; Layout.fillWidth: true; wrapMode: Text.WordWrap
                        text: addSheet.asked === "keep" ? "Adding the accounts…" : root.shell ? "Confirm each public-key request on the Shell…" : "Reading the card's public accounts…"
                    }
                    LogosText { objectName: "addMessage"; visible: !!addSheet.notice; Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.PlainText; color: Theme.palette.error; text: addSheet.notice }
                    LogosText { visible: root.ready && !!root.backend.lastError; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.error; textFormat: Text.PlainText; text: root.ready ? root.backend.lastError : "" }
                }
            }
            LogosText { objectName: "selectedCount"; visible: addSheet.step === 0 && addSheet.selected.length > 0; text: addSheet.selected.length + " selected across account types (up to 20)" }
            RowLayout {
                Layout.fillWidth: true
                LogosButton { objectName: "addCancel"; text: "Cancel"; enabled: !root.working && !addSheet.submitting; onClicked: addSheet.close() }
                LogosButton { objectName: "addBack"; text: "Back"; visible: addSheet.step === 1; enabled: !root.working && !addSheet.submitting; onClicked: { addSheet.step = 0; addSheet.notice = "" } }
                Item { Layout.fillWidth: true }
                LogosButton {
                    objectName: "nameAccounts"; visible: addSheet.step === 0; text: "Continue"
                    enabled: !root.working && !addSheet.submitting && addSheet.selected.length > 0
                    // The picks are kept from the previews: the PIN isn't needed again.
                    onClicked: { pinField.text = ""; addSheet.notice = ""; addSheet.step = 1 }
                }
                LogosButton {
                    objectName: "keepAccounts"; visible: addSheet.step === 1
                    text: "Add " + addSheet.selected.length + (addSheet.selected.length === 1 ? " account" : " accounts")
                    enabled: root.ready && !root.working && !addSheet.submitting && addSheet.selected.length > 0
                    onClicked: addSheet.keep()
                }
            }
        }
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
        id: verifySheet; objectName: "verifyWalletDialog"; title: "Verify wallet"
        property string walletId: ""
        property bool started: false
        property bool submitting: false
        property string errorText: ""
        anchors.centerIn: parent; width: Math.min(parent.width - 40, 540)
        closePolicy: root.working || submitting ? Popup.NoAutoClose : Popup.CloseOnEscape
        onOpened: {
            started = false; errorText = ""
            var index = root.shellDevices.findIndex(function(d) { return root.connection && d.serial === root.connection.serial })
            verifyDevice.currentIndex = Math.max(0, index)
        }
        contentItem: ColumnLayout {
            LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Choose a Shell and confirm the master public-key request on its screen. This replaces its cached verification and checks that the inserted card holds this wallet. Your accounts and names stay unchanged." }
            LogosComboBox {
                id: verifyDevice; objectName: "verifyWalletDevice"; Layout.fillWidth: true
                model: root.shellDevices.map(function(d) { return "Shell · " + root.shortId(d.serial) })
                enabled: !root.working && !verifySheet.submitting
            }
            LogosText {
                objectName: "verifyWalletResult"; Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.PlainText
                text: verifySheet.errorText || (verifySheet.started ? (root.working || verifySheet.submitting ? "Confirm the public-key request on your Shell…" : root.exporting.state === "done" ? "Wallet verified for this USB connection." : root.exporting.error || "") : "")
            }
            RowLayout {
                LogosButton { text: "Close"; enabled: !root.working && !verifySheet.submitting; onClicked: verifySheet.close() }
                Item { Layout.fillWidth: true }
                LogosButton {
                    objectName: "verifyWalletButton"; text: "Verify wallet"
                    enabled: !root.working && !verifySheet.submitting && verifyDevice.currentIndex >= 0 && verifyDevice.currentIndex < root.shellDevices.length
                    onClicked: {
                        verifySheet.started = true; verifySheet.submitting = true; verifySheet.errorText = ""
                        logos.watch(root.backend.verifyWallet(verifySheet.walletId, root.shellDevices[verifyDevice.currentIndex].serial), function(ok) {
                            verifySheet.submitting = false
                            if (!ok) verifySheet.errorText = root.backend.lastError
                        })
                    }
                }
            }
        }
    }
    LogosDialog {
        id: shellSheet; title: "Open a wallet via USB"
        anchors.centerIn: parent; width: Math.min(parent.width-40, 520)
        contentItem: ColumnLayout {
            LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Open the wallet on your Shell and choose the connected device." }
            Repeater {
                model: root.shellDevices
                delegate: LogosButton { Layout.fillWidth: true; text: "Shell · " + root.shortId(modelData.serial); onClicked: {
                    var wallet = {id: "shell:" + modelData.serial + ":", serial: modelData.serial, pending: true, transport: "shell", accounts: [], connected: true}
                    shellSheet.close(); root.openAdd(wallet)
                } }
            }
            LogosButton { text: "Cancel"; onClicked: shellSheet.close() }
        }
    }
    LogosDialog {
        id: manageSheet; objectName: "manageWalletDialog"; title: "Manage · " + root.groupName(root.wallet)
        anchors.centerIn: parent; width: Math.min(parent.width-40, 620); height: Math.min(parent.height-40, 620)
        onOpened: { walletName.text = root.wallet ? root.wallet.name || "" : "" }
        contentItem: ColumnLayout {
            LogosScrollView {
                id: manageScroll; Layout.fillWidth: true; Layout.fillHeight: true; contentWidth: availableWidth
                ColumnLayout {
                    width: manageScroll.availableWidth; spacing: Theme.spacing.small
                    LogosText { Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText; color: Theme.palette.textSecondary; text: root.selectedWalletId.indexOf("seed:") === 0 ? "Wallet ID: " + root.selectedWalletId.slice(5) : "Wallet identity has not been verified yet." }
                    LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap; text: "Cards and Shells holding this seed share one wallet. A reader asks for the card PIN here; a Shell asks for confirmation on its own screen. Use the connection selector when adding accounts." }
                    RowLayout {
                        Layout.fillWidth: true; visible: root.wallet && !root.wallet.legacy
                        LogosTextField { id: walletName; objectName: "walletName"; Layout.fillWidth: true; placeholderText: "Wallet name"; textInput.maximumLength: 80 }
                        LogosButton { objectName: "saveWalletName"; text: "Save name"; onClicked: logos.watch(root.backend.renameCard(root.selectedWalletId, walletName.text), function(ok) {}) }
                    }
                    LogosButton {
                        objectName: "verifyWalletAction"; text: "Verify wallet…"
                        visible: root.selectedWalletId.indexOf("seed:") === 0 && root.shellDevices.length > 0
                        enabled: !root.working
                        onClicked: { verifySheet.walletId = root.selectedWalletId; verifySheet.open() }
                    }
                    LogosText { visible: !!root.card && root.card.trustedByPerson === true; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.error; text: "You trusted this card although Keycard did not certify it." }
                    LogosButton { visible: !!root.card && root.card.trustedByPerson === true; text: "Stop trusting"; onClicked: logos.watch(root.backend.forgetCard(root.card.identity), function(ok) { if(ok) manageSheet.close() }) }
                    Repeater {
                        model: (root.wallet && root.wallet.accounts) || []
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            LogosText { Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText; text: (modelData.label || root.familyWords(modelData.family)) + "\n" + (modelData.address || modelData.path || modelData.id) }
                            LogosButton {
                                objectName: "renameAccount_" + index; text: "Rename"
                                onClicked: {
                                    renameAccountSheet.walletId = root.selectedWalletId
                                    renameAccountSheet.accountId = modelData.id
                                    renameAccountSheet.accountLabel = modelData.label || ""
                                    renameAccountSheet.accountDetails = modelData.address || modelData.path || modelData.id
                                    renameAccountSheet.open()
                                }
                            }
                            LogosButton { objectName: "removeAccount_" + index; text: "Remove"; onClicked: logos.watch(root.backend.removeWalletAccount(root.selectedWalletId, modelData.id), function(ok) {}) }
                        }
                    }
                    LogosText { visible: !root.shell; Layout.fillWidth: true; wrapMode: Text.WordWrap; color: Theme.palette.textSecondary; text: "Removing an account hides it from apps, including for other cards sharing the same recovery phrase. Nothing on the card changes." }
                    LogosButton { objectName: "administerWalletCard"; text: "Card administration…"; visible: !!root.card; enabled: !root.working; onClicked: { adminSheet.preferredCard = root.card.adminId; manageSheet.close(); adminSheet.open() } }
                    LogosButton { objectName: "forgetWallet"; visible: root.wallet && !root.wallet.legacy; text: "Forget wallet…"; onClicked: { forgetSheet.cardId = root.selectedWalletId; forgetSheet.cardName = root.groupName(root.wallet); forgetSheet.open() } }
                    LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.PlainText; text: root.ready ? root.backend.noticeText : "" }
                    LogosText { Layout.fillWidth: true; wrapMode: Text.WordWrap; textFormat: Text.PlainText; color: Theme.palette.error; text: root.ready ? root.backend.lastError : "" }
                }
            }
            LogosButton { objectName: "manageDone"; text: "Done"; onClicked: manageSheet.close() }
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
    LogosDialog {
        id: trustSheet; title: "Review Keycard identity"
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
                                               function (trusted) { ownCard.checked = false })
                    }
                }
            }
            LogosButton { text: "Close"; onClicked: trustSheet.close() }
        }
    }
    LogosDialog {
        id: forgetSheet
        objectName: "forgetSavedCardDialog"
        title: "Forget Keycard?"
        property string cardId: ""
        property string cardName: ""
        property bool working: false
        readonly property var group: root.wallets.find(function(g) { return g.id === forgetSheet.cardId })
        readonly property bool connected: !!group && (group.connections || []).some(function(c) { return c.transport !== "shell" && c.connected })
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
                text: "Remove this wallet's saved accounts and name from this computer. Nothing on the Keycard or Shell is erased. You can add its accounts again later."
            }
            LogosText {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                visible: forgetSheet.connected
                text: "Remove this Keycard from its reader before forgetting it."
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
                    text: forgetSheet.working ? "Forgetting…" : "Forget Keycard"
                    enabled: !!forgetSheet.group && !forgetSheet.connected && !forgetSheet.working
                    onClicked: {
                        forgetSheet.working = true
                        logos.watch(root.backend.forgetSavedCard(forgetSheet.cardId), function(ok) {
                            forgetSheet.working = false
                            if (ok) { forgetSheet.close(); manageSheet.close() }
                        })
                    }
                }
            }
        }
    }

}
