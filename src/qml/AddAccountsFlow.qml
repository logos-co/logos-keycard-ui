import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// Add accounts, as a guided one-step-per-screen flow matching the administration CardFlow: a title
// line that keeps the wallet + connection in view, a centred "Step N of 4" header, one concern per
// screen, a fixed modal size, and a working / success / error phase. It is not an `administer` flow
// (it reads public keys from the device and commits a selection), so it keeps its own small state
// machine rather than riding CardFlow's plan machine, but it reuses the same chrome and PinDots.
//
// Steps: 1 Choose accounts (type + first index) · 2 Authorise (card PIN as circles, or unlock on the
// Shell; pairing folds in here when a 3.x card needs it) · 3 Select (a page read from the device,
// with pagination) · 4 Name. Preview and commit go through backend.addAccounts; the outcome arrives
// on the polled `exporting` state, so a page read / commit shows the working phase and advances when
// the device answers.
LogosDialog {
    id: flow
    objectName: "addAccountsDialog"

    // Live state, bound from the view.
    property var backend: null
    property bool ready: false
    property string walletId: ""
    property var wallet: null
    property string walletName: "Wallet"
    property var connection: null
    property var connections: []
    property bool shell: false
    property var card: null
    property string reader: ""
    property bool needsPairing: false
    property bool connected: false
    property bool working: false
    property var exporting: ({})
    signal finished()

    // 0 choose · 1 authorise · 2 select · 3 name
    property int step: 0
    property string phase: "input"      // input | working | success | error
    property int from: 0
    property var rows: []
    property var selected: []
    property var names: ({})
    property string notice: ""
    property string asked: ""            // "preview" | "keep" | ""
    property string workingText: ""
    property bool pairing: false
    // Choose-accounts config.
    property int coinIdx: 0              // 0 Ethereum · 1 Bitcoin
    property int scriptIdx: 0            // 0 Native SegWit · 1 Taproot
    property int networkIdx: 0           // 0 Bitcoin · 1 Test networks
    property string firstIndexText: "0"

    readonly property int stepCount: 4
    readonly property string family: coinIdx === 0 ? "evm" : scriptIdx === 0 ? "bitcoin" : "bitcoin_taproot"
    readonly property string chain: networkIdx === 0 ? "main" : "test"
    readonly property int pageSize: flow.shell ? 1 : 5
    readonly property bool taprootOk: flow.shell || (flow.card && flow.card.taproot)
    readonly property bool canPreview: flow.ready && flow.connected && !flow.needsPairing && !flow.working
                                       && flow.asked === "" && (flow.shell || pinDots.valid)
    readonly property var stepTitles: ["Choose accounts", "Authorise", "Select accounts", "Name accounts"]
    readonly property var stepDescs: [
        "Pick the account type and where to start. Only public information leaves the device.",
        flow.shell ? "Unlock the wallet on your Shell. It asks you to confirm each public-key request on its screen."
                   : (flow.needsPairing ? "This card needs pairing before it can show accounts."
                                        : "Enter the card's PIN. Only public keys leave the card."),
        "Choose the accounts to add. Already-added accounts are marked.",
        "Name each account, or leave it empty to show its kind and address."
    ]

    function route(c) { return !c ? "" : c.transport === "shell" ? "shell:" + c.serial + ":" : c.id }
    function shortId(id) { var s = (id || "").split(":").pop(); return s.length > 16 ? s.slice(0,8) + "…" + s.slice(-8) : s }
    function familyWords(f) { return f === "evm" ? "Ethereum" : f === "bitcoin" ? "Bitcoin · Native SegWit" : "Bitcoin · Taproot" }
    function connLabel(c) { return !c ? "" : c.transport === "shell" ? "Shell " + shortId(c.serial) : "Reader " + shortId(c.id) }

    function entry(family, chain, index, label) {
        var e = { family: family, account: index }
        if (family !== "evm") e.chain = chain
        if (label) e.label = label
        return e
    }
    function rowKey(r) { return r.family + ":" + r.chain + ":" + r.index }
    function chosen(key) { return flow.selected.some(function (r) { return r.key === key }) }
    function toggle(r, on) {
        var copy = flow.selected.filter(function (s) { return s.key !== r.key })
        if (on) copy.push(r)
        flow.selected = copy
    }
    function present(a) {
        return ((flow.wallet && flow.wallet.accounts) || []).some(function (b) {
            return a.id === b.id || (b.sources || []).some(function (o) { return o.id === a.id })
        })
    }
    function shown(accounts) {
        return accounts.map(function (a) {
            var r = { family: a.family, chain: a.family === "evm" ? "" : (a.chain || flow.chain),
                      index: parseInt((a.path || "").split("/").pop()), path: a.path || "",
                      address: (a.preview || {}).address || a.address || "", present: flow.present(a) }
            r.key = flow.rowKey(r)
            return r
        })
    }
    function preview(start) {
        flow.from = Math.max(0, start)
        var entries = []
        for (var i = 0; i < flow.pageSize; i++) entries.push(flow.entry(flow.family, flow.chain, flow.from + i, ""))
        flow.run("preview", { entries: entries, preview: true }, pinDots.value)
    }
    function keep() {
        var entries = flow.selected.map(function (r) { return flow.entry(r.family, r.chain, r.index, (flow.names[r.key] || "").trim()) })
        flow.run("keep", { entries: entries, fromPreview: true }, "")
    }
    function run(what, request, secret) {
        flow.notice = ""; flow.asked = what
        flow.workingText = what === "keep" ? "Adding the accounts…"
                         : flow.shell ? "Press OK on the Shell to confirm the public-key request…"
                                      : "Reading the card's accounts…"
        flow.phase = "working"
        logos.watch(flow.backend.addAccounts(flow.walletId, flow.route(flow.connection), JSON.stringify(request), secret), function (ok) {
            // The real outcome arrives on the exporting state; a false here is a dispatch failure.
            if (!ok && flow.asked === what) { flow.asked = ""; flow.notice = "The device did not answer."; flow.phase = "input" }
        })
    }
    function doPair(secret) {
        flow.pairing = true
        logos.watch(flow.backend.pair(flow.reader, secret), function (ok) { flow.pairing = false; pairField.text = "" })
    }
    function clearRows() { flow.rows = []; flow.selected = [] }

    onExportingChanged: {
        if (flow.phase !== "working" || flow.asked === "") return
        var st = (flow.exporting && flow.exporting.state) || ""
        if (st === "failed") {
            var wasF = flow.asked; flow.asked = ""
            flow.notice = (flow.exporting && flow.exporting.error) || "The device did not answer."
            flow.phase = "input"
            flow.step = wasF === "preview" ? 1 : 3      // preview fail → back to authorise; commit fail → back to name
            return
        }
        if (st !== "done") return
        var was = flow.asked; flow.asked = ""
        if (was === "preview") { flow.rows = flow.shown((flow.exporting && flow.exporting.accounts) || []); flow.step = 2; flow.phase = "input" }
        else { flow.phase = "success" }
    }

    title: ""
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min((parent ? parent.width : 600) - 40, 480)
    height: Math.min((parent ? parent.height : 640) - 40, 560)
    closePolicy: flow.phase === "working" ? Popup.NoAutoClose : Popup.CloseOnEscape
    onOpened: {
        flow.step = 0; flow.from = 0; flow.rows = []; flow.selected = []; flow.names = ({})
        flow.notice = ""; flow.asked = ""; flow.phase = "input"; flow.pairing = false
        flow.coinIdx = 0; flow.scriptIdx = 0; flow.networkIdx = 0; flow.firstIndexText = "0"
        pinDots.clear(); pairField.text = ""
    }
    onClosed: { pinDots.clear(); pairField.text = ""; flow.rows = []; flow.selected = []; flow.names = ({}); flow.asked = ""; flow.finished() }
    // If the active card is swapped while the dialog is open, drop the entered secret and any read page.
    onCardChanged: if (flow.opened) { pinDots.clear(); pairField.text = ""; flow.clearRows() }

    contentItem: ColumnLayout {
        spacing: Theme.spacing.medium

        // Title line: flow name left, wallet + connection right. Persists across every phase.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            LogosText { text: "Add accounts"; color: Theme.palette.text; font.weight: Theme.typography.weightBold; font.pixelSize: Theme.typography.subtitleText }
            Item { Layout.fillWidth: true }
            LogosText {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: flow.width * 0.55
                elide: Text.ElideRight; textFormat: Text.PlainText
                text: flow.walletName + (flow.connection ? "  ·  " + flow.connLabel(flow.connection) : "")
                color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText
            }
        }

        // One fixed-height body: every phase lives inside it so the modal never changes size.
        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Input phase — a centred step header, then the step's one concern.
            ColumnLayout {
                visible: flow.phase === "input"
                anchors.fill: parent
                spacing: Theme.spacing.medium

                // Step header (step N of M, title, description) — centred, like the admin flows.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.spacing.large
                    spacing: Theme.spacing.tiny
                    LogosText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: "Step " + (flow.step + 1) + " of " + flow.stepCount; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                    LogosText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: flow.stepTitles[flow.step]; color: Theme.palette.text; font.weight: Theme.typography.weightBold; font.pixelSize: Theme.typography.subtitleText }
                    LogosText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: flow.stepDescs[flow.step]; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                }

                // The step body fills the rest; each step's content is centred within it.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // STEP 0 — choose account type + first index.
                    ColumnLayout {
                        visible: flow.step === 0
                        anchors.centerIn: parent
                        width: Math.min(parent.width, 320)
                        spacing: Theme.spacing.small

                        LogosText { text: "Account type"; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                        RowLayout {
                            spacing: Theme.spacing.large
                            LogosRadioButton { objectName: "coinEthereum"; text: "Ethereum"; checked: flow.coinIdx === 0; onClicked: { flow.coinIdx = 0; flow.clearRows() } }
                            LogosRadioButton { objectName: "coinBitcoin"; text: "Bitcoin"; checked: flow.coinIdx === 1; onClicked: { flow.coinIdx = 1; flow.clearRows() } }
                        }

                        // Bitcoin sub-options (script + network), shown only for Bitcoin.
                        ColumnLayout {
                            visible: flow.coinIdx === 1
                            Layout.fillWidth: true; Layout.topMargin: Theme.spacing.tiny
                            spacing: Theme.spacing.tiny
                            LogosText { text: "Address type"; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                            RowLayout {
                                spacing: Theme.spacing.large
                                LogosRadioButton { text: "Native SegWit"; checked: flow.scriptIdx === 0; onClicked: { flow.scriptIdx = 0; flow.clearRows() } }
                                LogosRadioButton { text: "Taproot"; visible: flow.taprootOk; checked: flow.scriptIdx === 1; onClicked: { flow.scriptIdx = 1; flow.clearRows() } }
                            }
                            LogosText { Layout.topMargin: Theme.spacing.tiny; text: "Network"; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                            RowLayout {
                                spacing: Theme.spacing.large
                                LogosRadioButton { text: "Bitcoin"; checked: flow.networkIdx === 0; onClicked: { flow.networkIdx = 0; flow.clearRows() } }
                                LogosRadioButton { text: "Test networks"; checked: flow.networkIdx === 1; onClicked: { flow.networkIdx = 1; flow.clearRows() } }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small
                            LogosText { text: "First index" }
                            LogosTextField {
                                id: firstIndex; objectName: "firstIndex"
                                Layout.fillWidth: true; text: flow.firstIndexText
                                validator: IntValidator { bottom: 0; top: 2147483643 }
                                onTextChanged: { flow.firstIndexText = text; flow.clearRows() }
                            }
                        }
                        LogosText {
                            Layout.fillWidth: true; wrapMode: Text.WrapAnywhere
                            text: flow.coinIdx === 0 ? "m/44'/60'/0'/0/index"
                                                     : "m/" + (flow.scriptIdx === 0 ? "84" : "86") + "'/" + (flow.networkIdx === 0 ? "0" : "1") + "'/index'"
                            color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText
                        }
                    }

                    // STEP 1 — authorise: Shell unlock, card pairing, or card PIN.
                    Item {
                        visible: flow.step === 1
                        anchors.fill: parent

                        // Shell: nothing to type; the footer's "Show accounts" sends the request.
                        ColumnLayout {
                            visible: flow.shell
                            anchors.centerIn: parent; width: Math.min(parent.width, 340)
                            spacing: Theme.spacing.small
                            LogosText {
                                Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
                                text: "Press Show accounts, then confirm each public-key request on the Shell. This page shows one account at a time; use Next for more."
                                color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText
                            }
                        }

                        // Card needing pairing: a pairing password + "use the default" prefill.
                        ColumnLayout {
                            visible: !flow.shell && flow.needsPairing
                            anchors.centerIn: parent; width: Math.min(parent.width, 320)
                            spacing: Theme.spacing.small
                            LogosTextField {
                                id: pairField; objectName: "pairingField"
                                Layout.fillWidth: true
                                echoMode: (pairDefault.checked) ? TextInput.Normal : TextInput.Password
                                readOnly: pairDefault.checked
                                placeholderText: "Pairing password"
                            }
                            LogosCheckbox {
                                id: pairDefault; objectName: "pairingDefault"
                                text: "Use the default Keycard pairing password"
                                onToggled: pairField.text = checked ? "KeycardDefaultPairing" : ""
                            }
                        }

                        // Card, paired: PIN as circles.
                        PinDots {
                            id: pinDots
                            objectName: "addPinDots"
                            visible: !flow.shell && !flow.needsPairing
                            anchors.centerIn: parent
                            count: 6
                            onEntered: function (v) { if (flow.canPreview) flow.preview(Number(flow.firstIndexText)) }
                            onEdited: if (flow.notice) flow.notice = ""
                        }

                        LogosText {
                            visible: !flow.connected
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            text: "Connect this wallet to continue."; color: Theme.palette.error; font.pixelSize: Theme.typography.secondaryText
                        }
                    }

                    // STEP 2 — select accounts (a device-read page, with pagination).
                    ColumnLayout {
                        visible: flow.step === 2
                        anchors.fill: parent
                        spacing: Theme.spacing.small
                        LogosScrollView {
                            id: selectScroll
                            Layout.fillWidth: true; Layout.fillHeight: true
                            contentWidth: availableWidth
                            ColumnLayout {
                                width: selectScroll.availableWidth
                                spacing: Theme.spacing.small
                                Repeater {
                                    model: flow.rows
                                    // One tappable block per account, styled like the wallet-view account rows
                                    // (same background + hover). Tapping anywhere on the block toggles its box.
                                    delegate: Rectangle {
                                        required property var modelData
                                        required property int index
                                        readonly property bool canToggle: !flow.working && !modelData.present && (flow.chosen(modelData.key) || flow.selected.length < 20)
                                        Layout.fillWidth: true
                                        radius: 6
                                        // The dialog itself is backgroundSecondary, so each block uses a
                                        // darker inset fill + a border to read as its own card.
                                        color: modelData.present ? Theme.palette.backgroundMuted
                                               : rowHover.hovered ? Theme.palette.backgroundTertiary : Theme.palette.background
                                        border.width: 1
                                        border.color: rowHover.hovered ? Theme.palette.border : Theme.palette.borderSubtle
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        opacity: modelData.present ? 0.6 : 1.0
                                        implicitHeight: rowInner.implicitHeight + 2 * Theme.spacing.small
                                        HoverHandler { id: rowHover; enabled: parent.canToggle }
                                        TapHandler { enabled: parent.canToggle; onTapped: flow.toggle(modelData, !flow.chosen(modelData.key)) }
                                        RowLayout {
                                            id: rowInner
                                            anchors.left: parent.left; anchors.right: parent.right
                                            anchors.verticalCenter: parent.verticalCenter
                                            anchors.leftMargin: Theme.spacing.medium; anchors.rightMargin: Theme.spacing.medium
                                            spacing: Theme.spacing.small
                                            // The box is a visual indicator; the whole block is the hit area.
                                            LogosCheckbox {
                                                objectName: "selectAccount_" + index
                                                enabled: false; opacity: 1.0
                                                checked: flow.chosen(modelData.key) || modelData.present
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true; spacing: 2
                                                LogosText { text: "Index " + modelData.index + (modelData.present ? "  ·  Already added" : ""); color: modelData.present ? Theme.palette.textSecondary : Theme.palette.text }
                                                LogosText { Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText; text: modelData.address || "Address unavailable"; font.pixelSize: Theme.typography.secondaryText }
                                                LogosText { Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; color: Theme.palette.textTertiary; text: modelData.path; font.pixelSize: Theme.typography.secondaryText }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            LogosButton { objectName: "previousAccounts"; text: "Previous"; enabled: flow.canPreview && flow.from > 0; onClicked: flow.preview(Math.max(0, flow.from - flow.pageSize)) }
                            LogosText { text: flow.pageSize > 1 ? (flow.from + "–" + (flow.from + flow.pageSize - 1)) : ("Index " + flow.from); color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                            Item { Layout.fillWidth: true }
                            LogosText { visible: flow.selected.length > 0; text: flow.selected.length + " selected (up to 20)"; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                            Item { Layout.fillWidth: true }
                            LogosButton { objectName: "nextAccounts"; text: "Next"; enabled: flow.canPreview && flow.from < 2147483639; onClicked: flow.preview(flow.from + flow.pageSize) }
                        }
                    }

                    // STEP 3 — name the picks.
                    LogosScrollView {
                        id: nameScroll
                        visible: flow.step === 3
                        anchors.fill: parent
                        contentWidth: availableWidth
                        ColumnLayout {
                            width: nameScroll.availableWidth
                            spacing: Theme.spacing.medium
                            Repeater {
                                model: flow.selected
                                // One block per picked account, each with its own background.
                                delegate: Rectangle {
                                    required property var modelData
                                    required property int index
                                    Layout.fillWidth: true
                                    radius: 6
                                    // The dialog itself is backgroundSecondary; a darker inset fill + a
                                    // border makes each named account read as its own separated block.
                                    color: Theme.palette.background
                                    border.width: 1
                                    border.color: Theme.palette.borderSubtle
                                    implicitHeight: nameInner.implicitHeight + 2 * Theme.spacing.medium
                                    ColumnLayout {
                                        id: nameInner
                                        anchors.left: parent.left; anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: Theme.spacing.medium; anchors.rightMargin: Theme.spacing.medium
                                        spacing: Theme.spacing.small
                                        LogosText {
                                            Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                                            text: flow.familyWords(modelData.family) + (modelData.chain === "test" ? " · Test" : "") + "  ·  " + modelData.path + "\n" + modelData.address
                                            color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText
                                        }
                                        LogosTextField {
                                            objectName: "addAccountName_" + index
                                            Layout.fillWidth: true
                                            placeholderText: "Account name (optional)"; textInput.maximumLength: 80
                                            text: flow.names[modelData.key] || ""
                                            onTextChanged: flow.names[modelData.key] = text
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // One reserved, fixed-height line for an error / note, so it never resizes the modal.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 20
                    LogosText {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignTop
                        wrapMode: Text.WordWrap; elide: Text.ElideRight
                        text: flow.notice
                        color: Theme.palette.error; font.pixelSize: Theme.typography.secondaryText
                    }
                }
            }

            // Working — centred.
            ColumnLayout {
                visible: flow.phase === "working"
                anchors.centerIn: parent; width: parent.width
                spacing: Theme.spacing.small
                LogosText { Layout.alignment: Qt.AlignHCenter; text: flow.workingText; color: Theme.palette.text; font.weight: Theme.typography.weightBold }
                LogosText { Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: flow.shell ? "Keep the Shell connected and approve on its screen." : "Keep the card on the reader until it finishes."; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
            }

            // Success — centred.
            ColumnLayout {
                visible: flow.phase === "success"
                anchors.centerIn: parent; width: parent.width
                spacing: Theme.spacing.small
                LogosText { Layout.alignment: Qt.AlignHCenter; text: "Done"; color: Theme.palette.success; font.weight: Theme.typography.weightBold; font.pixelSize: Theme.typography.subtitleText }
                LogosText { Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: "The accounts were added. Apps can now use them; spending still needs the device."; color: Theme.palette.text }
            }
        }

        // Footer — per phase / step, pinned to the bottom by the fixed-height body above.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small

            // Left: Cancel on the first step, Back after.
            LogosButton {
                visible: flow.phase === "input"
                text: flow.step === 0 ? "Cancel" : "Back"
                enabled: !flow.working && !flow.pairing
                onClicked: { if (flow.step === 0) flow.close(); else { flow.step = flow.step - 1; flow.notice = "" } }
            }
            Item { Layout.fillWidth: true }

            // Step 0 → continue to authorise.
            LogosButton {
                visible: flow.phase === "input" && flow.step === 0
                text: "Continue"; variant: LogosButton.Variant.Primary
                enabled: firstIndex.textInput.acceptableInput
                onClicked: { flow.clearRows(); flow.step = 1 }
            }
            // Step 1 → pair (card needing it) or read the first page.
            LogosButton {
                visible: flow.phase === "input" && flow.step === 1 && !flow.shell && flow.needsPairing
                text: flow.pairing ? "Pairing…" : "Pair"; variant: LogosButton.Variant.Primary
                enabled: !!pairField.text && !flow.pairing
                onClicked: flow.doPair(pairField.text)
            }
            LogosButton {
                visible: flow.phase === "input" && flow.step === 1 && (flow.shell || !flow.needsPairing)
                text: "Show accounts"; variant: LogosButton.Variant.Primary
                enabled: flow.canPreview
                onClicked: flow.preview(Number(flow.firstIndexText))
            }
            // Step 2 → continue to naming.
            LogosButton {
                visible: flow.phase === "input" && flow.step === 2
                text: "Continue"; variant: LogosButton.Variant.Primary
                enabled: flow.selected.length > 0 && !flow.working
                onClicked: { flow.notice = ""; flow.step = 3 }
            }
            // Step 3 → commit.
            LogosButton {
                visible: flow.phase === "input" && flow.step === 3
                text: "Add " + flow.selected.length + (flow.selected.length === 1 ? " account" : " accounts")
                variant: LogosButton.Variant.Primary
                enabled: flow.selected.length > 0 && !flow.working
                onClicked: flow.keep()
            }
            LogosButton { visible: flow.phase === "success"; text: "Done"; variant: LogosButton.Variant.Primary; onClicked: flow.close() }
        }
    }
}
