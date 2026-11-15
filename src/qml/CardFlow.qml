import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme

// A guided, one-input-per-screen flow for the card operations, modelled on the Status Keycard flows:
// a title line that keeps the flow name and the card being operated on, a centred step (step N of M,
// title, description), one input per screen, a fixed modal size, a "writing" state and success /
// in-step error handling. PIN / PUK entry uses circles (PinDots); other steps are a text field, a
// typed confirmation, or an acknowledgement.
//
// Step kinds: pin | puk | text | confirm | info.
// Backend contract (verified against keycard_module): administer returns {ok:false, code, error}; a
// wrong secret is code "WrongSecret" with the count only in the message, so attempts are read back
// from a no-PIN status call. A wrong-length PIN/PUK is rejected before the card counts an attempt.
LogosDialog {
    id: flow

    property var backend: null
    property var card: null          // { reader, adminId, keyUid }
    property string cardName: ""
    property string walletId: ""     // master fingerprint, or "" for a card with no keys
    property string action: ""
    signal finished(bool ok)

    readonly property var plan: {
        var pin = function (t, d) { return {key:"pin", kind:"pin", title:t, desc:d} }
        if (action === "change_pin") return { title:"Change PIN", secret:"pin", retry:"pinRetries", success:"Your PIN has been changed.",
            steps:[ pin("Enter your current PIN", "The 6-digit PIN for this card."),
                    {key:"newPin", kind:"pin", title:"Choose a new PIN", desc:"Six digits you will remember. Avoid 000000 or 123456."},
                    {key:"repeat", kind:"pin", title:"Confirm your new PIN", desc:"Enter the new PIN again.", match:"newPin"} ] }
        if (action === "change_puk") return { title:"Change PUK", secret:"pin", retry:"pinRetries", success:"Your PUK has been changed.",
            steps:[ pin("Enter your current PIN", "The 6-digit PIN for this card."),
                    {key:"puk", kind:"puk", title:"Choose a new PUK", desc:"Twelve digits. Keep it somewhere safe, separate from the card."},
                    {key:"repeat", kind:"puk", title:"Confirm your new PUK", desc:"Enter the new PUK again.", match:"puk"} ] }
        if (action === "unblock_pin") return { title:"Unblock PIN", secret:"puk", retry:"pukRetries", success:"Your PIN is unblocked and set.",
            steps:[ {key:"puk", kind:"puk", title:"Enter your PUK", desc:"The 12-digit PUK unblocks the PIN."},
                    {key:"newPin", kind:"pin", title:"Choose a new PIN", desc:"Six digits you will remember. Avoid 000000 or 123456."},
                    {key:"repeat", kind:"pin", title:"Confirm your new PIN", desc:"Enter the new PIN again.", match:"newPin"} ] }
        if (action === "set_name") return { title:"Update card name", secret:"pin", retry:"pinRetries", success:"The card name has been updated.",
            steps:[ pin("Enter your PIN", "The 6-digit PIN for this card."),
                    {key:"name", kind:"text", title:"Name this card", desc:"Shown on the card itself (up to 20 characters). It does not rename the wallet. Leave empty to clear it.", placeholder:"Card name", maxLen:20, minLen:0} ] }
        if (action === "set_ndef") return { title:"NFC text message", secret:"pin", retry:"pinRetries", success:"The NFC text has been updated.",
            steps:[ pin("Enter your PIN", "The 6-digit PIN for this card."),
                    {key:"ndef", kind:"text", title:"Public NFC text", desc:"Readable over NFC without a PIN. Do not put secrets here. Leave empty to clear it.", placeholder:"NFC text", maxLen:120, minLen:0} ] }
        if (action === "pair") return { title:"Pair this app", secret:"pairing", retry:"", success:"This app is paired with the card.",
            steps:[ {key:"pairing", kind:"text", secret:true, title:"Pairing password", desc:"The app tries the standard password first. If pairing is still required, enter the password set when the card was set up.", placeholder:"Pairing password", minLen:1} ] }
        if (action === "change_pairing_password") return { title:"Change pairing password", secret:"pin", retry:"pinRetries", success:"The pairing password has been changed.",
            steps:[ pin("Enter your PIN", "The 6-digit PIN for this card."),
                    {key:"pairing", kind:"text", secret:true, title:"New pairing password", desc:"Used for future pairings. Existing pairings keep working until their slots are removed.", placeholder:"New pairing password", minLen:1},
                    {key:"repeat", kind:"text", secret:true, title:"Confirm pairing password", desc:"Enter it again.", placeholder:"Repeat password", minLen:1, match:"pairing"} ] }
        if (action === "unpair") return { title:"Remove a pairing slot", secret:"pin", retry:"pinRetries", success:"The pairing slot has been removed.",
            steps:[ pin("Enter your PIN", "The 6-digit PIN for this card."),
                    {key:"slot", kind:"text", digitsOnly:true, title:"Pairing slot", desc:"A slot index from 0 to 9. Read Card status to find this app's slot. Clearing this app's own slot unpairs it too.", placeholder:"Slot (0-9)", minLen:1, maxLen:1} ] }
        if (action === "generate_key") return { title:"Generate keys without backup", secret:"pin", retry:"pinRetries", success:"Keys were generated on the card.",
            steps:[ {key:"warn", kind:"info", warn:true, title:"No recovery backup", desc:"This generates keys with NO recovery phrase. If the card is lost or reset, its wallet cannot be recovered. Use Create recovery phrase for a recoverable wallet."},
                    pin("Enter your PIN", "The 6-digit PIN for this card."),
                    {key:"confirm", kind:"confirm", expect:"NO BACKUP", title:"Type to confirm", desc:"Type NO BACKUP to confirm you understand there is no recovery.", placeholder:"NO BACKUP"} ] }
        if (action === "remove_key") return { title:"Erase keys from card", secret:"pin", retry:"pinRetries", success:"The keys were erased from the card.",
            steps:[ {key:"warn", kind:"info", warn:true, title:"Erase recovery keys", desc:"Erases the recovery keys from this card. You need a backup to restore access to funds. PIN, PUK and pairings remain. Saved accounts on this computer are kept."},
                    pin("Enter your PIN", "The 6-digit PIN for this card."),
                    {key:"confirm", kind:"confirm", expect:"ERASE", title:"Type to confirm", desc:"Type ERASE to confirm.", placeholder:"ERASE"} ] }
        if (action === "factory_reset") return { title:"Factory reset card", secret:"", retry:"", success:"The card has been factory reset.",
            steps:[ {key:"warn", kind:"info", warn:true, title:"Erase everything on the card", desc:"Factory reset erases keys, PIN, PUK, pairings and card metadata. It needs no PIN. You need a backup to restore access to funds. Saved names and accounts on this computer are kept."},
                    {key:"confirm", kind:"confirm", expect:"RESET", title:"Type to confirm", desc:"Type RESET to confirm.", placeholder:"RESET"} ] }
        if (action === "initialize") {
            // A fresh card: no current PIN. 3.x cards need a pairing password set here; 4.0 cards do
            // not (and support an alternate PIN, left to default here).
            var sc = flow.card ? flow.card.secureChannel : 2
            var initSteps = [ {key:"newPin", kind:"pin", title:"Choose a PIN", desc:"Six digits you will remember. Avoid 000000 or 123456."},
                              {key:"repeatPin", kind:"pin", title:"Confirm the PIN", desc:"Enter the PIN again.", match:"newPin"},
                              {key:"puk", kind:"puk", title:"Choose a PUK", desc:"Twelve digits. Keep it somewhere safe, separate from the card."},
                              {key:"repeatPuk", kind:"puk", title:"Confirm the PUK", desc:"Enter the PUK again.", match:"puk"} ]
            if (sc === 1) initSteps.push({key:"pairing", kind:"text", secret:true, title:"Pairing password", desc:"A password apps use to pair with this card (1 to 128 characters).", placeholder:"Pairing password", minLen:1})
            return { title:"Set up card", secret:"", retry:"", success:"The card is set up. Pair it if needed, then create or import its recovery keys.", steps:initSteps }
        }
        if (action === "read_data") return { title:"Read card data", secret:"", retry:"", success:"Card data read.", result:true,
            steps:[ {key:"dataType", kind:"choice", title:"Which data", desc:"Read the public metadata area, or the Cash applet data, as hexadecimal.", options:["Public metadata","Cash applet data"]} ] }
        if (action === "write_data") return { title:"Write card data", secret:"pin", retry:"pinRetries", success:"The card data was written.",
            steps:[ {key:"warn", kind:"info", warn:true, title:"Replace card data", desc:"Replaces the selected public data area. Read and back up its current hex first. Other apps may use it for wallet metadata."},
                    {key:"dataType", kind:"choice", title:"Which data", desc:"The public metadata area, or the Cash applet data.", options:["Public metadata","Cash applet data"]},
                    {key:"hex", kind:"text", hexOnly:true, title:"Hexadecimal data", desc:"Up to 127 bytes, as hexadecimal.", placeholder:"Hexadecimal data", minLen:2, maxLen:254},
                    {key:"pin", kind:"pin", title:"Enter your PIN", desc:"The 6-digit PIN for this card."},
                    {key:"confirm", kind:"confirm", expect:"WRITE", title:"Type to confirm", desc:"Type WRITE to confirm.", placeholder:"WRITE"} ] }
        return { title:"", secret:"", retry:"", success:"", steps:[] }
    }
    readonly property var steps: plan.steps
    property int idx: 0
    property var vals: ({})
    property string phase: "input"   // input | working | success | error
    property string errorMsg: ""
    property string noteMsg: ""
    property int attempts: -1
    property bool pinBlocked: false
    property bool pukBlocked: false
    readonly property var step: steps[idx] || null
    readonly property bool isPin: step && (step.kind === "pin" || step.kind === "puk")
    readonly property bool isText: step && (step.kind === "text" || step.kind === "confirm")
    readonly property bool isChoice: step && step.kind === "choice"
    readonly property int count: step && step.kind === "puk" ? 12 : 6
    readonly property bool lastStep: idx === steps.length - 1
    property string resultText: "" // data returned by a read operation, shown on the success screen
    readonly property bool stepValid: {
        if (!step) return false
        if (step.kind === "info" || step.kind === "choice") return true
        if (flow.isPin) return pinDots.valid
        if (step.kind === "confirm") return txt.text === step.expect
        if (step.digitsOnly && !/^[0-9]*$/.test(txt.text)) return false
        if (step.hexOnly && (!/^[0-9a-fA-F]*$/.test(txt.text) || txt.text.length % 2 !== 0)) return false
        var n = txt.text.length
        return n >= (step.minLen === undefined ? 1 : step.minLen) && (!step.maxLen || n <= step.maxLen)
    }

    title: "" // custom header row below puts the card context on the title line
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min((parent ? parent.width : 600) - 40, 460)
    // Fixed height so the modal is the same size through input, working, success and failure, and a
    // tip or an error never resizes it. The body fills this and each phase is centred inside it.
    height: 404
    closePolicy: phase === "working" ? Popup.NoAutoClose : Popup.CloseOnEscape
    onClosed: { clearSecrets(); flow.finished(flow.phase === "success") }
    onOpened: enterStep(false)

    function shortId(id) { var s = (id || "").split(":").pop(); return s.length > 16 ? s.slice(0,8) + "…" + s.slice(-8) : s }
    function clearSecrets() { flow.vals = ({}); pinDots.clear(); txt.text = "" }
    function isWeak(s) {
        if (s.length < 6) return false
        var weak = ["000000","111111","222222","333333","444444","555555","666666","777777","888888","999999","123456","654321","012345","121212","123123"]
        return weak.indexOf(s) >= 0
    }
    function enterStep(err) {
        flow.noteMsg = ""
        if (flow.isPin) { pinDots.value = flow.step ? (flow.vals[flow.step.key] || "") : ""; pinDots.error = !!err; pinDots.forceActive() }
        else if (flow.isText) {
            txt.textInput.maximumLength = (flow.step && flow.step.maxLen) ? flow.step.maxLen : 128
            txt.text = flow.step ? (flow.vals[flow.step.key] || "") : ""
            txt.textInput.forceActiveFocus()
        }
        else if (flow.isChoice) { combo.currentIndex = (flow.step && flow.vals[flow.step.key] !== undefined) ? flow.vals[flow.step.key] : 0 }
    }
    function begin() {
        flow.idx = 0; flow.vals = ({}); flow.phase = "input"; flow.errorMsg = ""; flow.noteMsg = ""
        flow.attempts = -1; flow.pinBlocked = false; flow.pukBlocked = false; flow.resultText = ""
        enterStep(false)
    }
    function currentValue() {
        if (!flow.step) return ""
        if (flow.step.kind === "info") return "ack"
        if (flow.isChoice) return combo.currentIndex
        return flow.isPin ? pinDots.value : txt.text
    }
    function clearCurrent() { if (flow.isPin) pinDots.clear(); else if (flow.isText) txt.text = ""; }
    function continueStep() {
        if (!flow.step || !flow.stepValid) return
        var v = flow.currentValue()
        var d = flow.vals; d[flow.step.key] = v; flow.vals = d
        if (flow.step.match && v !== flow.vals[flow.step.match]) {
            var d2 = flow.vals; d2[flow.step.key] = ""; flow.vals = d2
            flow.clearCurrent(); enterStep(false)
            flow.errorMsg = flow.count === 12 && flow.step.kind === "puk" ? "The PUKs do not match. Enter it again."
                           : flow.isPin ? "The PINs do not match. Enter it again." : "They do not match. Enter it again."
            return
        }
        if (flow.action === "change_pin" && flow.step.key === "newPin" && flow.vals.pin && v === flow.vals.pin) {
            var d3 = flow.vals; d3[flow.step.key] = ""; flow.vals = d3
            flow.clearCurrent(); enterStep(false)
            flow.errorMsg = "Choose a PIN different from your current one."
            return
        }
        flow.errorMsg = ""
        if (flow.lastStep) { flow.submit(); return }
        flow.idx = flow.idx + 1
        enterStep(false)
    }
    function goBack() {
        if (flow.idx === 0) { flow.close(); return }
        flow.idx = flow.idx - 1; flow.errorMsg = ""
        enterStep(false)
    }
    function submit() {
        var p = { action: flow.action, reader: flow.card.reader, cardId: flow.card.adminId, keyUid: flow.card.keyUid || "" }
        if (flow.action === "change_pin") { p.pin = flow.vals.pin; p.newPin = flow.vals.newPin }
        else if (flow.action === "change_puk") { p.pin = flow.vals.pin; p.puk = flow.vals.puk }
        else if (flow.action === "unblock_pin") { p.puk = flow.vals.puk; p.newPin = flow.vals.newPin }
        else if (flow.action === "set_name") { p.pin = flow.vals.pin; p.text = flow.vals.name || "" }
        else if (flow.action === "set_ndef") { p.pin = flow.vals.pin; p.text = flow.vals.ndef || "" }
        else if (flow.action === "pair") { p.pairingPassword = flow.vals.pairing }
        else if (flow.action === "change_pairing_password") { p.pin = flow.vals.pin; p.pairingPassword = flow.vals.pairing }
        else if (flow.action === "unpair") { p.pin = flow.vals.pin; p.slot = Number(flow.vals.slot) }
        else if (flow.action === "generate_key") { p.pin = flow.vals.pin; p.confirmation = flow.vals.confirm }
        else if (flow.action === "remove_key") { p.pin = flow.vals.pin; p.confirmation = flow.vals.confirm }
        else if (flow.action === "factory_reset") { p.confirmation = flow.vals.confirm }
        else if (flow.action === "initialize") { p.newPin = flow.vals.newPin; p.puk = flow.vals.puk; if (flow.vals.pairing) p.pairingPassword = flow.vals.pairing }
        else if (flow.action === "read_data") { p.dataType = flow.vals.dataType === 0 ? 0 : 2 }
        else if (flow.action === "write_data") { p.pin = flow.vals.pin; p.dataType = flow.vals.dataType === 0 ? 0 : 2; p.text = flow.vals.hex; p.confirmation = flow.vals.confirm }
        flow.phase = "working"; flow.errorMsg = ""
        logos.watch(flow.backend.administer(JSON.stringify(p)), function (raw) { flow.handleReply(raw) })
    }
    function readAttempts(cb) {
        var p = { action: "status", reader: flow.card.reader, cardId: flow.card.adminId, keyUid: flow.card.keyUid || "" }
        logos.watch(flow.backend.administer(JSON.stringify(p)), function (raw) {
            var r; try { r = JSON.parse(raw) } catch (e) { r = {} }
            var att = r && r.ok ? (flow.plan.retry === "pukRetries" ? r.pukRetries : r.pinRetries) : -1
            cb(typeof att === "number" ? att : -1)
        })
    }
    function goToSecretStep() {
        for (var i = 0; i < flow.steps.length; i++) if (flow.steps[i].key === flow.plan.secret) { flow.idx = i; break }
        var d = flow.vals; d[flow.plan.secret] = ""; flow.vals = d
        flow.phase = "input"
        enterStep(true)
    }
    function handleReply(raw) {
        var r; try { r = JSON.parse(raw) } catch (e) { r = { ok:false, error:"The card did not return a valid response. Reconnect it and try again." } }
        if (r.ok) { if (flow.plan.result && r.data !== undefined) flow.resultText = r.data; flow.phase = "success"; flow.clearSecrets(); return }
        var msg = r.error || "The operation failed."
        var wrongSecret = r.code === "WrongSecret" || /wrong (pin|puk|pairing)/i.test(msg)
        var blocked = /block/i.test(msg)
        // PIN-counted flows: wrong PIN / block routing with attempts.
        if (flow.plan.retry && (wrongSecret || blocked)) {
            flow.readAttempts(function (att) {
                flow.attempts = att
                if (att === 0) {
                    flow.phase = "error"
                    if (flow.plan.retry === "pukRetries") { flow.pukBlocked = true; flow.errorMsg = "The PUK is blocked. This card can only be factory reset to recover it." }
                    else { flow.pinBlocked = true; flow.errorMsg = "The PIN is blocked. Unblock it with your PUK." }
                    return
                }
                flow.goToSecretStep()
                var noun = flow.plan.secret === "puk" ? "PUK" : "PIN"
                flow.errorMsg = att > 0 ? ("Incorrect " + noun + ". " + att + " attempt" + (att === 1 ? "" : "s") + " left.")
                                        : ("Incorrect " + noun + ". Try again.")
            })
            return
        }
        // Non-counted wrong secret (e.g. pairing password): retry the step, no attempt count.
        if (wrongSecret && flow.plan.secret) { flow.goToSecretStep(); flow.errorMsg = msg; return }
        flow.phase = "error"; flow.errorMsg = msg
    }
    function startUnblock() { flow.action = "unblock_pin"; flow.begin() }

    contentItem: ColumnLayout {
        spacing: Theme.spacing.medium

        // Title line: the flow name on the left, the card being operated on on the right. Persists.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            LogosText { text: flow.plan.title; color: Theme.palette.text; font.weight: Theme.typography.weightBold; font.pixelSize: Theme.typography.subtitleText }
            Item { Layout.fillWidth: true }
            LogosText {
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: flow.width * 0.5
                elide: Text.ElideRight; textFormat: Text.PlainText
                text: (flow.cardName ? flow.cardName : (flow.card ? flow.shortId(flow.card.adminId) : ""))
                      + (flow.walletId ? "  ·  Wallet " + flow.walletId : "")
                color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText
            }
        }

        // One body of fixed height: every phase lives inside it so the modal never changes size.
        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Input: step + description (centred), the one input for this step, and a reserved line.
            ColumnLayout {
                visible: flow.phase === "input"
                anchors.centerIn: parent; width: parent.width
                spacing: Theme.spacing.medium
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacing.tiny
                    LogosText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: "Step " + (flow.idx + 1) + " of " + flow.steps.length; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                    LogosText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: flow.step ? flow.step.title : ""; color: Theme.palette.text; font.weight: Theme.typography.weightBold; font.pixelSize: Theme.typography.subtitleText }
                    LogosText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: flow.step ? flow.step.desc : ""; color: (flow.step && flow.step.warn) ? Theme.palette.error : Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
                }

                // PIN / PUK dots.
                PinDots {
                    id: pinDots
                    visible: flow.isPin
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Theme.spacing.large
                    Layout.bottomMargin: Theme.spacing.large
                    count: flow.count
                    onEntered: function (v) { if (!flow.lastStep) flow.continueStep() }
                    onEdited: {
                        if (flow.errorMsg) flow.errorMsg = ""
                        flow.noteMsg = (flow.step && flow.step.key === "newPin" && flow.isWeak(pinDots.value)) ? "That PIN is easy to guess. A less common one is safer." : ""
                    }
                }

                // Text / confirmation field.
                LogosTextField {
                    id: txt
                    objectName: "cardFlowText"
                    visible: flow.isText
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Theme.spacing.medium
                    Layout.bottomMargin: Theme.spacing.medium
                    Layout.preferredWidth: 280
                    placeholderText: flow.step && flow.step.placeholder ? flow.step.placeholder : ""
                    echoMode: (flow.step && flow.step.secret) ? TextInput.Password : TextInput.Normal
                    onTextChanged: if (flow.errorMsg) flow.errorMsg = ""
                }

                // Choice field.
                LogosComboBox {
                    id: combo
                    objectName: "cardFlowChoice"
                    visible: flow.isChoice
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Theme.spacing.medium
                    Layout.bottomMargin: Theme.spacing.medium
                    Layout.preferredWidth: 280
                    model: flow.step && flow.step.options ? flow.step.options : []
                }

                // One reserved, fixed-height line for an error or a tip, so it never resizes the modal.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    LogosText {
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignTop
                        wrapMode: Text.WordWrap
                        text: flow.errorMsg !== "" ? flow.errorMsg : flow.noteMsg
                        color: flow.errorMsg !== "" ? Theme.palette.error : Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                    }
                }
            }

            // Writing to the card — centred.
            ColumnLayout {
                visible: flow.phase === "working"
                anchors.centerIn: parent; width: parent.width
                spacing: Theme.spacing.small
                LogosText { Layout.alignment: Qt.AlignHCenter; text: "Writing to the card…"; color: Theme.palette.text; font.weight: Theme.typography.weightBold }
                LogosText { Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: "Keep the card on the reader until it finishes."; color: Theme.palette.textSecondary; font.pixelSize: Theme.typography.secondaryText }
            }

            // Success — centred.
            ColumnLayout {
                visible: flow.phase === "success"
                anchors.centerIn: parent; width: parent.width
                spacing: Theme.spacing.small
                LogosText { Layout.alignment: Qt.AlignHCenter; text: "Done"; color: Theme.palette.success; font.weight: Theme.typography.weightBold; font.pixelSize: Theme.typography.subtitleText }
                LogosText { Layout.alignment: Qt.AlignHCenter; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: flow.plan.success; color: Theme.palette.text }
                // Data returned by a read operation, as selectable hexadecimal.
                LogosText {
                    visible: flow.resultText !== ""
                    Layout.fillWidth: true; Layout.topMargin: Theme.spacing.small
                    horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WrapAnywhere
                    text: flow.resultText; textFormat: Text.PlainText
                    font.family: Theme.typography.mono; font.pixelSize: Theme.typography.secondaryText
                    color: Theme.palette.textSecondary
                }
            }

            // Terminal error — centred.
            ColumnLayout {
                visible: flow.phase === "error"
                anchors.centerIn: parent; width: parent.width
                spacing: Theme.spacing.small
                LogosText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: flow.errorMsg; color: Theme.palette.error }
            }
        }

        // Footer — per phase, pinned to the bottom by the fixed-height body above.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            LogosButton { visible: flow.phase === "input"; text: flow.idx === 0 ? "Cancel" : "Back"; onClicked: flow.goBack() }
            Item { Layout.fillWidth: true }
            LogosButton {
                visible: flow.phase === "input"
                text: flow.lastStep ? flow.plan.title : "Continue"
                variant: LogosButton.Variant.Primary
                enabled: flow.stepValid
                onClicked: flow.continueStep()
            }
            LogosButton { visible: flow.phase === "success"; text: "Done"; variant: LogosButton.Variant.Primary; onClicked: flow.close() }
            LogosButton { visible: flow.phase === "error" && flow.pinBlocked; text: "Unblock PIN"; variant: LogosButton.Variant.Primary; onClicked: flow.startUnblock() }
            LogosButton { visible: flow.phase === "error"; text: "Close"; onClicked: flow.close() }
        }
    }
}
