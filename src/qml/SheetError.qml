import QtQuick 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "errors.js" as Errors

// A sheet's own error line. The backend keeps ONE lastError for every action, and it stays set
// until the next action succeeds, so a sheet never binds to it: it reads it with `take` at the
// moment its own call answers a refusal, and `clear`s on open, on each try and on close. What it
// shows is in words: a machine code ("WrongSecret: ") is dropped.
LogosText {
    id: line
    property string error: ""
    function clear() { line.error = "" }
    // The sheet's call answered a refusal: say why, as the backend gave it then.
    function take(backend, fallback) {
        line.error = Errors.human(backend ? backend.lastError : "") || fallback || "That did not work. Try again."
    }
    // The call itself was lost: no answer came back.
    function lost() { line.error = "The Keycard app did not answer. Try again." }

    Layout.fillWidth: true
    visible: line.error !== ""
    text: line.error
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: Theme.palette.error
}
