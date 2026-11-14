import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import Logos.Controls
import Logos.Theme
import "roster.js" as Roster

// One wallet, as the Signer, Keycard and Keys apps show it: its name and Wallet ID (the master
// fingerprint), the app's lines and strips, then one row per account. Each app brings its own
// actions: beside the title, in a strip, on each row, and at the bottom.
Frame {
    id: card
    property string namePrefix: ""
    property string title: ""
    // The wallet's id, shown once it is a known wallet: its BIP32 master fingerprint. Empty until
    // accounts are added, so the Wallet ID row only appears for a known wallet.
    property string walletId: ""
    // The keyUid this wallet is recognized by, shown in the Wallet ID tooltip.
    property string walletIdFull: ""
    // Icons for the inline edit (rename) and trash (forget) controls beside the title.
    property url editIcon: ""
    property url trashIcon: ""
    // Beside the actions at the top, as "Unlocked".
    property string stateText: ""
    // Who holds it, or how it unlocks.
    property var lines: []
    // A device in use, a phrase kept here, a warning: [{ id, text, warn, actions }].
    property var strips: []
    property bool locked: false
    property string lockedText: "Locked · its ID and accounts show once you unlock it in the Signer app."
    property string emptyText: "No accounts yet."
    // Entries as the roster gives them, plus `firstAddress` for Bitcoin; shown in a fixed order.
    property var accounts: []
    // Labels, or { id, label, enabled, tip }. accountActions may be a function of the entry.
    property var actions: []
    property var lockedActions: []
    property var accountActions: []
    property var leftActions: []
    property var rightActions: []
    // The app's own items, as an inline editor, go above the bottom actions.
    default property alias content: extraArea.data

    signal action(string id)
    signal stripAction(int index, string id)
    signal accountAction(string id, var entry)
    signal copied(string value)

    readonly property var rows: Roster.sortAccounts(accounts)
    readonly property var bottomLeft: Roster.actions(leftActions)
    readonly property var bottomRight: Roster.actions(rightActions)
    // Add accounts becomes a full-width button under the connection; rename/forget become the edit
    // and trash icons beside the name; anything else (e.g. Verify) stays in the top row.
    readonly property var allActions: Roster.actions(card.actions)
    readonly property var addAction: allActions.filter(function (a) { return a.id === "add" })[0] || null
    readonly property var editAction: allActions.filter(function (a) { return a.id === "rename" })[0] || null
    readonly property var trashAction: allActions.filter(function (a) { return a.id === "forget" })[0] || null
    readonly property var otherActions: allActions.filter(function (a) { return ["add", "rename", "forget"].indexOf(a.id) < 0 })

    objectName: namePrefix + "Card"
    padding: Theme.spacing.medium
    background: Rectangle {
        radius: 6
        color: Theme.palette.backgroundMuted
        border.color: Theme.palette.border
        border.width: 1
    }

    component ActionButton: LogosButton {
        required property var spec
        property string prefix: card.namePrefix
        objectName: prefix + "Action_" + Roster.actionName(spec)
        text: spec.label
        enabled: spec.enabled
        ToolTip.text: spec.tip
        ToolTip.visible: hovered && spec.tip.length > 0
        ToolTip.delay: 400
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                spacing: 4
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    LogosText {
                        objectName: card.namePrefix + "Title"
                        Layout.fillWidth: false
                        Layout.maximumWidth: card.width * 0.62
                        text: card.title
                        textFormat: Text.PlainText
                        font.bold: true
                        font.pixelSize: Theme.typography.subtitleText
                        elide: Text.ElideRight
                    }
                    LogosIconButton {
                        objectName: card.namePrefix + "Edit"
                        visible: !!card.editAction && !card.locked
                        enabled: !card.editAction || card.editAction.enabled !== false
                        flat: true; size: 28; iconSize: 16
                        iconSource: card.editIcon
                        iconColor: hovered ? Theme.palette.text : Theme.palette.textTertiary
                        onClicked: if (card.editAction) card.action(card.editAction.id)
                        ToolTip.text: "Edit name"; ToolTip.visible: hovered; ToolTip.delay: 400
                    }
                    Item { Layout.fillWidth: true }
                }
                RowLayout {
                    visible: card.walletId.length > 0 && !card.locked
                    spacing: 6
                    LogosText {
                        Layout.alignment: Qt.AlignBaseline
                        text: "Wallet ID"
                        color: Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    LogosText {
                        objectName: card.namePrefix + "WalletId"
                        Layout.alignment: Qt.AlignBaseline
                        text: card.walletId
                        textFormat: Text.PlainText
                        color: Theme.palette.textSecondary
                        font.family: Theme.typography.mono
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    // The full identity and the cross-check fingerprint, kept off the always-on
                    // line: the keyUid is the wallet's identity; the BIP32 master fingerprint is
                    // the short form the Signer/Keys and hardware wallets show, once accounts load.
                    HoverHandler { id: walletIdHover }
                    ToolTip {
                        text: "The master fingerprint of the wallet's keys, the same ID the Signer and Keys apps show."
                            + (card.walletIdFull.length > 0 ? "\nkeyUid: " + card.walletIdFull : "")
                        visible: walletIdHover.hovered
                        delay: 400
                    }
                }
                Repeater {
                    model: card.lines
                    delegate: LogosText {
                        required property var modelData
                        required property int index
                        objectName: card.namePrefix + "Line_" + index
                        Layout.fillWidth: true
                        text: Roster.text(modelData)
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        color: Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                    }
                }
            }
            LogosText {
                objectName: card.namePrefix + "State"
                visible: text.length > 0
                Layout.alignment: Qt.AlignTop
                text: card.stateText
                textFormat: Text.PlainText
            }
            Repeater {
                model: card.otherActions
                delegate: ActionButton {
                    required property var modelData
                    spec: modelData
                    Layout.alignment: Qt.AlignTop
                    onClicked: card.action(spec.id)
                }
            }
            LogosIconButton {
                objectName: card.namePrefix + "Forget"
                visible: !!card.trashAction && !card.locked
                enabled: !card.trashAction || card.trashAction.enabled !== false
                Layout.alignment: Qt.AlignTop
                flat: true; size: 28; iconSize: 16
                iconSource: card.trashIcon
                iconColor: hovered ? Theme.palette.text : Theme.palette.textTertiary
                onClicked: if (card.trashAction) card.action(card.trashAction.id)
                ToolTip.text: "Forget wallet"; ToolTip.visible: hovered; ToolTip.delay: 400
            }
        }

        Repeater {
            model: card.strips
            delegate: Rectangle {
                id: strip
                required property var modelData
                required property int index
                // Named by its id when it has one, so a strip's name doesn't shift with the others.
                readonly property string key: Roster.text(modelData && modelData.id) || String(index)
                readonly property string prefix: card.namePrefix + "Strip_" + key + "_"
                objectName: card.namePrefix + "Strip_" + key
                Layout.fillWidth: true
                implicitHeight: stripRow.implicitHeight + 2 * Theme.spacing.small
                radius: 6
                color: Theme.palette.backgroundSecondary
                RowLayout {
                    id: stripRow
                    anchors.fill: parent
                    anchors.leftMargin: Theme.spacing.medium
                    anchors.rightMargin: Theme.spacing.small
                    spacing: Theme.spacing.small
                    LogosText {
                        objectName: strip.prefix + "Text"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        text: Roster.text(strip.modelData && strip.modelData.text)
                        textFormat: Text.PlainText
                        wrapMode: Text.WordWrap
                        color: strip.modelData && strip.modelData.warn ? Theme.palette.error : Theme.palette.textSecondary
                        font.pixelSize: Theme.typography.secondaryText
                    }
                    Repeater {
                        model: Roster.actions(strip.modelData && strip.modelData.actions)
                        delegate: ActionButton {
                            required property var modelData
                            spec: modelData
                            prefix: strip.prefix
                            Component.onCompleted: if ("compact" in this) this["compact"] = true
                            onClicked: card.stripAction(strip.index, spec.id)
                        }
                    }
                }
            }
        }

        LogosButton {
            objectName: card.namePrefix + "AddAccounts"
            visible: !!card.addAction && !card.locked
            enabled: !card.addAction || card.addAction.enabled !== false
            Layout.fillWidth: true
            variant: LogosButton.Variant.Primary
            text: card.addAction ? card.addAction.label : "Add accounts"
            onClicked: if (card.addAction) card.action(card.addAction.id)
        }

        RowLayout {
            visible: card.locked
            Layout.fillWidth: true
            LogosText {
                objectName: card.namePrefix + "Locked"
                Layout.fillWidth: true
                text: card.lockedText
                textFormat: Text.PlainText
                wrapMode: Text.WordWrap
                color: Theme.palette.textSecondary
            }
            Repeater {
                model: Roster.actions(card.lockedActions)
                delegate: ActionButton {
                    required property var modelData
                    spec: modelData
                    onClicked: card.action(spec.id)
                }
            }
        }

        LogosText {
            objectName: card.namePrefix + "Empty"
            visible: !card.locked && card.rows.length === 0 && card.emptyText.length > 0
            text: card.emptyText
            color: Theme.palette.textSecondary
        }

        ColumnLayout {
            visible: !card.locked && card.rows.length > 0
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            Repeater {
                model: card.rows
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    radius: 6
                    color: acctHover.hovered ? Theme.palette.backgroundTertiary : Theme.palette.backgroundSecondary
                    Behavior on color { ColorAnimation { duration: 120 } }
                    implicitHeight: acct.implicitHeight + 2 * Theme.spacing.small
                    HoverHandler { id: acctHover }
                    AccountDetails {
                        id: acct
                        objectName: card.namePrefix + "Account_" + index
                        namePrefix: card.namePrefix + "Account_" + index + "_"
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: Theme.spacing.medium
                        anchors.rightMargin: Theme.spacing.small
                        entry: modelData
                        actions: card.accountActions
                        editIcon: card.editIcon
                        trashIcon: card.trashIcon
                        onAction: function (id, entry) { card.accountAction(id, entry) }
                        onCopied: function (v) { card.copied(v) }
                    }
                }
            }
        }

        ColumnLayout {
            id: extraArea
            objectName: card.namePrefix + "Content"
            Layout.fillWidth: true
            spacing: Theme.spacing.small
        }

        RowLayout {
            visible: card.bottomLeft.length + card.bottomRight.length > 0
            Layout.fillWidth: true
            spacing: Theme.spacing.small
            Repeater {
                model: card.bottomLeft
                delegate: ActionButton {
                    required property var modelData
                    spec: modelData
                    onClicked: card.action(spec.id)
                }
            }
            Item { Layout.fillWidth: true }
            Repeater {
                model: card.bottomRight
                delegate: ActionButton {
                    required property var modelData
                    spec: modelData
                    onClicked: card.action(spec.id)
                }
            }
        }
    }
}
