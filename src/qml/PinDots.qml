import QtQuick 2.15
import QtQuick.Controls 2.15
import Logos.Controls
import Logos.Theme

// Status-style PIN / PUK entry: a row of circles that fill as digits are typed, digit-only and
// fixed length. The text lives in an invisible TextInput that holds focus; the circles are the
// only visual (the value is never shown). Follows the Status `StatusPinInput` pattern (circles,
// `pinLen`, digit-only via validator + ImhDigitsOnly, a `valid` = acceptableInput && full-length)
// and the logos-chat-android PinPad (filled / empty / error dots, controlled value).
//
//   PinDots { count: 6; onCompleted: function(v) { ... } }
//
// Desktop drives it from the physical keyboard; a soft numeric keypad is offered separately for
// touch. Accessibility announces the count entered, never the digits.
FocusScope {
    id: root

    // 6 for a PIN, 12 for a PUK.
    property int count: 6
    property alias value: input.text
    // Tint the dots red for a wrong attempt, without clearing the value.
    property bool error: false
    property bool busy: false
    readonly property bool valid: input.text.length === root.count
    // Fired when the last digit lands, so a flow can auto-advance; and on every edit.
    // Named `entered` (not `completed`) to avoid colliding with Component.onCompleted.
    signal entered(string value)
    signal edited()

    implicitWidth: dots.implicitWidth
    // 44: the touch-target height (no design-system token for it yet).
    implicitHeight: Math.max(dots.implicitHeight, 44)

    function clear() { input.text = "" }
    // Put back a value already entered (Back to a filled step) without firing `entered`.
    property bool restoring: false
    function restore(v) { root.restoring = true; input.text = v; root.restoring = false }
    function forceActive() { input.forceActiveFocus() }

    Accessible.role: Accessible.EditableText
    Accessible.name: (root.error ? "Incorrect, " : "") + input.text.length + " of " + root.count + " digits entered"

    MouseArea { anchors.fill: parent; enabled: !root.busy; onClicked: input.forceActiveFocus() }

    Row {
        id: dots
        anchors.centerIn: parent
        spacing: 16
        Repeater {
            model: root.count
            delegate: Rectangle {
                required property int index
                readonly property bool filled: index < input.text.length
                readonly property bool current: index === input.text.length && input.activeFocus && !root.busy
                width: 16; height: 16; radius: 8
                border.width: 1.5
                color: filled && !root.error ? Theme.palette.text : "transparent"
                border.color: root.error ? Theme.palette.error
                              : filled ? Theme.palette.text
                              : current ? Theme.palette.textSecondary
                              : Theme.palette.textTertiary
                opacity: root.busy ? 0.5 : 1
                Behavior on color { ColorAnimation { duration: 90 } }
                Behavior on border.color { ColorAnimation { duration: 90 } }
            }
        }
    }

    TextInput {
        id: input
        anchors.fill: parent
        focus: true
        enabled: !root.busy
        opacity: 0 // the circles are the visual; never show the digits
        // Masked and unselectable, so select-all + copy can't put the PIN on the clipboard.
        echoMode: TextInput.Password
        selectByMouse: false
        persistentSelection: false
        activeFocusOnTab: true
        maximumLength: root.count
        inputMethodHints: Qt.ImhDigitsOnly | Qt.ImhSensitiveData
        validator: RegularExpressionValidator { regularExpression: /[0-9]*/ }
        onTextChanged: {
            if (root.error) root.error = false
            root.edited()
            if (text.length === root.count && !root.restoring) root.entered(text)
        }
    }
}
