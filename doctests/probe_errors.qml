// The Keycard view LOADED and DRIVEN offscreen, with a fabricated shell and backend: one backend
// error, one place. The backend keeps a single lastError for every action; a dialog shows the
// error its own call answered with, in words, and the page line shows only what the page did.
// The fake backend's members are the .rep's PROPs and SLOTs, one for one.
import QtQuick

Item {
    id: probe
    width: 1000
    height: 900

    property int failures: 0
    function check(label, got, want) {
        var ok = String(got) === String(want)
        if (!ok) probe.failures++
        console.log((ok ? "  PASS  " : "  FAIL  ") + label + "   got=" + got + (ok ? "" : "  want=" + want))
    }
    // Popups keep their items under contentItem, not under data.
    function kids(o) {
        var out = []
        if (o.data !== undefined) for (var i = 0; i < o.data.length; ++i) out.push(o.data[i])
        if (o.contentItem !== undefined && o.contentItem !== null && out.indexOf(o.contentItem) < 0) out.push(o.contentItem)
        return out
    }
    function find(o, name) {
        if (!o) return null
        if (o.objectName === name) return o
        var k = probe.kids(o)
        for (var i = 0; i < k.length; ++i) { var hit = probe.find(k[i], name); if (hit) return hit }
        return null
    }
    function shown(name) { var o = probe.find(view.item, name); return o !== null && o.visible ? o.text : "" }
    function sheet(name) { return probe.find(view.item, name) }

    QtObject {
        id: shell
        signal intentRequested(string requestId, string intent, var params, string requesterName)
        signal viewModuleReadyChanged(string moduleName, bool isReady)
        function module(n) { return fake }
        function isViewModuleReady(n) { return true }
        // `lose` makes the next call fail as a lost QtRO call would: the error callback, not the answer.
        property bool lose: false
        function watch(value, cb, err) {
            if (shell.lose) { shell.lose = false; if (err) err("call failed"); return }
            if (cb) cb(value)
        }
        function request(intent, params, cb) {}
        function respond(requestId, ok, data, error) {}
    }
    property var logos: shell

    readonly property string seed: "seed:0f1e2d3c4b5a69788796a5b4c3d2e1f0"
    QtObject {
        id: fake
        // A SLOT answers replies[name] when set, else its type's default; errors[name] is what it
        // leaves in lastError ("" on success, as the backend clears it).
        property var replies: ({})
        property var errors: ({})
        function answer(name, args, dflt) {
            fake.lastError = fake.errors[name] || ""
            return fake.replies[name] !== undefined ? fake.replies[name] : dflt
        }
        property string statusText: "Ready"
        property string lastError: ""
        property string cardsJson: "[]"
        property string readersJson: "[]"
        property string accountsJson: "[]"
        property string cardGroupsJson: "[]"
        property string walletsJson: JSON.stringify([{ id: probe.seed, name: "Savings", connected: false,
            connections: [], accounts: [{ id: "a0", family: "evm", path: "m/44'/60'/0'/0/0",
                                          address: "0x9858EfFD232B4033E47d90003D41EC34EcaEda94", fingerprint: "0f1e2d3c" }] }])
        property string exportJson: "{}"
        property string noticeText: ""
        property string shellDevicesJson: "[]"
        property string shellGroupsJson: "[]"
        function identifyWallet(serial) { return fake.answer("identifyWallet", [serial], true) }
        function verifyWallet(walletId, serial) { return fake.answer("verifyWallet", [walletId, serial], true) }
        function addAccounts(walletId, connectionId, requestJson, pin) { return fake.answer("addAccounts", [walletId, connectionId, requestJson, pin], true) }
        function renameAccount(walletId, accountId, name) { return fake.answer("renameAccount", [walletId, accountId, name], true) }
        function removeWalletAccount(walletId, accountId) { return fake.answer("removeWalletAccount", [walletId, accountId], true) }
        function refresh() { return fake.answer("refresh", [], true) }
        function administer(paramsJson) { return fake.answer("administer", [paramsJson], "{}") }
        function offer(reader, familiesJson, chain, account, label, pin) { return fake.answer("offer", [reader, familiesJson, chain, account, label, pin], true) }
        function removeAccount(id) { return fake.answer("removeAccount", [id], true) }
        function renameCard(id, name) { return fake.answer("renameCard", [id, name], true) }
        function forgetSavedCard(id) { return fake.answer("forgetSavedCard", [id], true) }
        function pair(reader, pairingPassword) { return fake.answer("pair", [reader, pairingPassword], true) }
        function changePin(reader, pin, newPin) { return fake.answer("changePin", [reader, pin, newPin], true) }
        function unblockPin(reader, puk, newPin) { return fake.answer("unblockPin", [reader, puk, newPin], true) }
        function trustCard(reader, identity) { return fake.answer("trustCard", [reader, identity], true) }
        function forgetCard(identity) { return fake.answer("forgetCard", [identity], true) }
    }
    function reset() { fake.replies = ({}); fake.errors = ({}); fake.lastError = "" }

    function assertARenameErrorStaysInItsDialog() {
        console.log("")
        console.log("a refused rename shows in its dialog only, in words, and is gone once it closes")
        view.item.selectedWalletId = probe.seed
        var s = probe.sheet("renameWalletDialog")
        s.open()
        check("the dialog is up", s.visible, true)
        check("it opens with no error", probe.shown("renameWalletError"), "")
        fake.replies = { renameCard: false }
        fake.errors = { renameCard: "StorageFailed: the name could not be saved" }
        probe.find(view.item, "walletName").text = "Spending"
        probe.find(view.item, "saveWalletName").clicked()
        check("refused: the reason in the dialog, without its code", probe.shown("renameWalletError"), "The name could not be saved")
        check("...and not on the page behind it", probe.shown("errorLabel"), "")
        s.close()
        check("the dialog is closed", s.visible, false)
        check("closed: not on the page either", probe.shown("errorLabel"), "")
        s.open()
        check("reopened: the dialog starts clean", probe.shown("renameWalletError"), "")
        shell.lose = true
        probe.find(view.item, "saveWalletName").clicked()
        check("a call lost on the way: the dialog is usable again", probe.find(view.item, "saveWalletName").enabled, true)
        check("...and says so", probe.shown("renameWalletError"), "The Keycard app did not answer. Try again.")
        s.close()
    }

    function assertForgetOpensClean() {
        console.log("")
        console.log("the Forget dialog shows no other action's error, and its own only while up")
        fake.lastError = "StorageFailed: the name could not be saved"   // left by the rename above
        var f = probe.sheet("forgetSavedCardDialog")
        f.cardId = probe.seed
        f.cardName = "Savings"
        f.open()
        check("opened after a refused rename: nothing stale", probe.shown("forgetSavedCardError"), "")
        fake.replies = { forgetSavedCard: false }
        fake.errors = { forgetSavedCard: "Busy: a card operation is still running" }
        probe.find(view.item, "confirmForgetSavedCard").clicked()
        check("refused: said in the dialog", probe.shown("forgetSavedCardError"), "A card operation is still running")
        check("...not on the page", probe.shown("errorLabel"), "")
        check("...and the button is free again", probe.find(view.item, "confirmForgetSavedCard").enabled, true)
        f.close()
        check("closed: gone everywhere", probe.shown("forgetSavedCardError") + probe.shown("errorLabel"), "")
        probe.reset()
    }

    function assertThePageShowsOnlyItsOwnError() {
        console.log("")
        console.log("the page line shows the page's own error, hides while a dialog or the other tab is up, and stays gone after")
        fake.lastError = "NotFound: that account is not saved"
        check("a page error, in words", probe.shown("errorLabel"), "That account is not saved")
        var t = probe.sheet("trustDialog")
        t.open()
        check("...not while a dialog is up", probe.shown("errorLabel"), "")
        t.close()
        check("...nor once it closes", probe.shown("errorLabel"), "")
        fake.lastError = ""
        fake.lastError = "NotFound: that account is not saved"
        check("the same words after a success: shown again", probe.shown("errorLabel"), "That account is not saved")
        var tabs = probe.find(view.item, "areaTabs")
        tabs.currentIndex = 1
        tabs.currentIndex = 0
        check("back from Administration: not shown again", probe.shown("errorLabel"), "")
        fake.lastError = ""
        check("a success clears it", probe.shown("errorLabel"), "")
        probe.reset()
    }

    function assertAddAccountsSaysWhyHere() {
        console.log("")
        console.log("Add accounts: a refused pairing is said in the dialog, a short PIN is named, nothing stays")
        var a = probe.sheet("addAccountsDialog")
        a.ready = true; a.connected = true; a.shell = false; a.reader = "Reader 0"; a.needsPairing = true
        a.open()
        a.step = 1
        check("opens with nothing said", probe.shown("addAccountsNotice"), "")
        fake.replies = { pair: false }
        fake.errors = { pair: "WrongSecret: the pairing password is not correct" }
        a.doPair("wrong")
        check("refused: said in the dialog, without its code", probe.shown("addAccountsNotice"), "The pairing password is not correct")
        check("...not on the page behind it", probe.shown("errorLabel"), "")
        a.close()
        check("closed: not on the page either", probe.shown("errorLabel"), "")
        a.needsPairing = false
        a.open()
        a.step = 1
        check("reopened: nothing stale", probe.shown("addAccountsNotice"), "")
        probe.find(view.item, "addPinDots").value = "12"
        check("a short PIN: the hint says why Show accounts is off", probe.shown("addAccountsNotice"), "Type all 6 digits of the PIN.")
        probe.find(view.item, "addPinDots").value = ""
        a.step = 0
        probe.find(view.item, "firstIndex").text = ""
        check("an empty first index: named too", probe.shown("addAccountsNotice"), "Type the first index as a whole number, 0 or more.")
        a.close()
        probe.reset()
    }

    function assertIdentifyOpensClean() {
        console.log("")
        console.log("Identify wallet shows only its own result, never an earlier export's failure")
        fake.exportJson = JSON.stringify({ state: "failed", error: "Timeout: the Shell did not answer" })
        var d = probe.sheet("identifyWalletDialog")
        d.open()
        check("an earlier failure is not shown on open", probe.shown("identifyWalletError") + probe.shown("identifyWalletState"), "")
        d.close()
        fake.exportJson = "{}"
        probe.reset()
    }

    Loader {
        id: view
        anchors.fill: parent
        onStatusChanged: {
            if (status === Loader.Error) { console.log("  FAIL  the view did not load"); Qt.exit(1) }
            if (status !== Loader.Ready) return
            // Popups open only in a window, and the window comes after this load: run on the next turn.
            run.start()
        }
    }
    Timer {
        id: run
        interval: 50
        onTriggered: {
            probe.check("the view is ready", view.item.ready, true)
            probe.assertARenameErrorStaysInItsDialog()
            probe.assertForgetOpensClean()
            probe.assertThePageShowsOnlyItsOwnError()
            probe.assertAddAccountsSaysWhyHere()
            probe.assertIdentifyOpensClean()
            console.log("")
            console.log(probe.failures ? "RESULT: FAILURES" : "RESULT: ALL PASS")
            Qt.exit(probe.failures ? 1 : 0)
        }
    }
    Component.onCompleted: view.source = Qt.resolvedUrl("../src/qml/KeycardView.qml")
}
