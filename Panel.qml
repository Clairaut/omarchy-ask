import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
    id: root
    moduleName: "clairaut.voice"
    ipcTarget: "clairaut.voice"
    manageIpc: true

    property var anchorItem: null
    property var hostWidget: null
    property var service: null

    readonly property var barIdentity: hostWidget || root

    // The panel is 693px wide, too narrow to put a list beside a reader, so it
    // drills down instead: now -> list -> reading, with esc walking back out.
    property string view: "now"
    property var openedMeta: null

    // Keyboard cursor. One flat index per view, because the panel never shows
    // two navigable regions at once: a parked write replaces the now view's
    // controls, the list replaces both, and reading replaces the list.
    property int cursor: 0

    readonly property int cursorCount: {
        if (head) return 2                                        // approve, discard
        if (view === "list") return service ? service.conversations.length : 0
        if (view === "reading") return (openedMeta && !openedMeta.live) ? 1 : 0
        return 4                                                  // clear, log, conversations, ask
    }

    function moveCursor(step) {
        if (cursorCount <= 0) return
        cursor = (cursor + step + cursorCount) % cursorCount
        // The ask field is the only item that takes text, so entering it means
        // handing it real focus and letting it swallow keys until Escape.
        if (view === "now" && !head && cursor === 3) askField.forceActiveFocus()
        else if (askField.activeFocus) keyCatcher.forceActiveFocus()
    }

    function activateCursor() {
        if (head) {
            service.decide(head.id, cursor === 0)
            return
        }
        if (view === "list") {
            var items = service ? service.conversations : []
            if (cursor >= 0 && cursor < items.length) showConversation(items[cursor])
            return
        }
        if (view === "reading") {
            if (openedMeta && !openedMeta.live) { service.resume(openedMeta.file); close() }
            return
        }
        if (cursor === 0) { service.clearSession(); close() }
        else if (cursor === 1) { service.logSession(); close() }
        else if (cursor === 2) showList()
        else askField.forceActiveFocus()
    }

    // Only an archived conversation can be forgotten. The live one is ended with
    // clear, which is a different decision about a different thing.
    function forgetUnderCursor() {
        if (view !== "list" || !service) return
        var items = service.conversations
        if (cursor < 0 || cursor >= items.length) return
        if (items[cursor].live) return
        service.forget(items[cursor].file)
        if (cursor >= items.length - 1) cursor = Math.max(0, cursor - 1)
    }

    onViewChanged: cursor = 0

    function showList() {
        service.rescanConversations()
        view = "list"
    }

    function showConversation(entry) {
        openedMeta = entry
        service.openConversation(entry.file, entry.live)
        view = "reading"
    }

    function back() {
        if (view === "reading") view = "list"
        else if (view === "list") view = "now"
        else close()
    }

    onOpenedChanged: if (!opened) view = "now"
    readonly property var pending: service ? service.pending : []
    readonly property var head: pending.length > 0 ? pending[0] : null

    function openFromHotkey() { open() }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        centerOnBar: false
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(520))
        contentHeight: panel.fittedContentHeight(content.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            // While the field has focus it owns every key, so arrows move the
            // caret rather than the cursor and typing reaches the input.
            blocked: askField.activeFocus

            onCloseRequested: root.back()
            onTabRequested: function (direction) { root.switchPanel(direction) }
            onMoveRequested: function (dx, dy) { root.moveCursor(dy !== 0 ? dy : dx) }
            onActivateRequested: root.activateCursor()
            onDeleteRequested: root.forgetUnderCursor()

            // Approve and discard are reachable without the mouse, because the
            // whole point is answering without leaving what you were doing.
            Keys.onPressed: function (event) {
                if (!root.head) return
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    service.decide(root.head.id, true)
                    event.accepted = true
                } else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) {
                    service.decide(root.head.id, false)
                    event.accepted = true
                }
            }

            Column {
                id: content
                width: parent.width
                spacing: 0

                // ---------- header ----------
                Item {
                    width: parent.width
                    height: headerCol.implicitHeight + Style.space(20)

                    Column {
                        id: headerCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Style.space(14)
                        anchors.rightMargin: Style.space(14)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(3)

                        Row {
                            spacing: Style.space(8)

                            // Back arrow, shown only where there is somewhere to go back to.
                            Text {
                                visible: root.view !== "now"
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\uf053"
                                font.family: Style.font.family
                                font.pixelSize: Style.font.bodySmall
                                color: Color.muted
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -Style.space(4)
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.back()
                                }
                            }

                            VoiceGlyph {
                                visible: root.view === "now"
                                anchors.verticalCenter: parent.verticalCenter
                                state: service ? service.currentState : "idle"
                                color: (service && service.currentState === "waiting") ? Color.urgent : Color.popups.text
                                size: Style.font.subtitle
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.view === "list" ? "Conversations"
                                    : root.view === "reading" ? Model.trim(root.openedMeta ? root.openedMeta.title : "", 46)
                                    : Model.describe(service ? service.currentState : "idle").label
                                font.family: Style.font.family
                                font.pixelSize: Style.font.bodySmall
                                color: Color.popups.text
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    if (!service) return ""
                                    if (service.currentState === "waiting") return "nothing has been written yet"
                                    if (service.currentState === "idle") return "super+h to speak, or type below"
                                    return ""
                                }
                                font.family: Style.font.family
                                font.pixelSize: Style.font.caption
                                color: Color.muted
                            }
                        }

                        Text {
                            text: {
                                if (!service) return ""
                                var bits = []
                                if (service.sessionAge > 0) bits.push("session " + Model.humanDuration(service.sessionAge) + " old")
                                bits.push(service.turns + (service.turns === 1 ? " turn" : " turns"))
                                if (service.pending.length === 0) bits.push("nothing pending")
                                return bits.join(" · ")
                            }
                            font.family: Style.font.family
                            font.pixelSize: Style.font.caption
                            font.features: ({ "tnum": 1 })
                            color: Color.muted
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.popups.text, 0.14) }

                // ---------- pending write ----------
                Loader {
                    width: parent.width
                    active: root.view === "now" && root.head !== null
                    visible: active
                    sourceComponent: approvalCard
                }

                // ---------- conversation ----------
                Column {
                    width: parent.width
                    spacing: 0
                    bottomPadding: Style.space(10)
                    visible: root.view === "now"

                    Text {
                        text: "THIS SESSION"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.letterSpacing: 1.4
                        color: Color.muted
                        leftPadding: Style.space(14)
                        topPadding: Style.space(11)
                        bottomPadding: Style.space(4)
                    }

                    Text {
                        visible: !service || service.exchanges.length === 0
                        text: "nothing asked yet in this session"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        color: Color.muted
                        leftPadding: Style.space(14)
                        bottomPadding: Style.space(6)
                    }

                    Repeater {
                        model: service ? service.exchanges : []

                        Item {
                            required property var modelData
                            width: content.width
                            height: exchange.implicitHeight + Style.space(9)

                            Column {
                                id: exchange
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Style.space(14)
                                anchors.rightMargin: Style.space(14)
                                anchors.top: parent.top
                                anchors.topMargin: Style.space(3)
                                spacing: Style.space(2)

                                Row {
                                    spacing: Style.space(8)
                                    Text {
                                        width: Style.space(34)
                                        text: modelData.time
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.caption
                                        font.features: ({ "tnum": 1 })
                                        color: Color.muted
                                    }
                                    Text {
                                        width: exchange.width - Style.space(42)
                                        text: Model.trim(modelData.you, 90)
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.bodySmall
                                        color: Color.popups.text
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                Text {
                                    x: Style.space(42)
                                    width: exchange.width - Style.space(42)
                                    text: Model.trim(modelData.claude, 150)
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.bodySmall
                                    color: Color.muted
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }

                // ---------- conversations ----------
                Column {
                    width: parent.width
                    spacing: 0
                    visible: root.view === "list"
                    bottomPadding: Style.space(10)

                    Repeater {
                        model: root.view === "list" && service ? service.conversations : []

                        Item {
                            required property var modelData
                            required property int index
                            width: content.width
                            height: entry.implicitHeight + Style.space(14)

                            Rectangle {
                                anchors.fill: parent
                                color: index === root.cursor ? Util.alpha(Color.popups.text, 0.10)
                                     : modelData.live ? Util.alpha(Color.popups.text, 0.05)
                                     : "transparent"
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.cursor = index; root.showConversation(modelData) }
                            }

                            Row {
                                id: entry
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Style.space(14)
                                anchors.rightMargin: Style.space(14)
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Style.space(10)

                                Text {
                                    anchors.top: parent.top
                                    anchors.topMargin: Style.space(2)
                                    text: modelData.live ? "\u25cf" : "\u25cb"
                                    font.pixelSize: Style.font.caption
                                    color: modelData.live ? Color.popups.text : Color.muted
                                }

                                Column {
                                    width: entry.width - Style.space(24)
                                    spacing: Style.space(2)

                                    Text {
                                        width: parent.width
                                        text: modelData.title
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.bodySmall
                                        color: Color.popups.text
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        text: Model.conversationMeta(modelData)
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.caption
                                        font.features: ({ "tnum": 1 })
                                        color: Color.muted
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: !service || service.conversations.length === 0
                        text: "nothing stored yet"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        color: Color.muted
                        leftPadding: Style.space(14)
                        topPadding: Style.space(12)
                        bottomPadding: Style.space(6)
                    }
                }

                // ---------- reading one ----------
                Column {
                    width: parent.width
                    spacing: 0
                    visible: root.view === "reading"
                    topPadding: Style.space(11)
                    bottomPadding: Style.space(10)

                    Repeater {
                        model: root.view === "reading" && service ? service.opened : []

                        Item {
                            required property var modelData
                            width: content.width
                            height: turnCol.implicitHeight + Style.space(11)

                            Row {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Style.space(14)
                                anchors.rightMargin: Style.space(14)
                                anchors.top: parent.top
                                spacing: Style.space(10)

                                Text {
                                    width: Style.space(34)
                                    text: modelData.time
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                    font.features: ({ "tnum": 1 })
                                    color: Color.muted
                                }

                                Column {
                                    id: turnCol
                                    width: content.width - Style.space(72)
                                    spacing: Style.space(3)

                                    Text {
                                        width: parent.width
                                        text: Model.trim(modelData.you, 150)
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.bodySmall
                                        color: Color.popups.text
                                        wrapMode: Text.WordWrap
                                    }
                                    Text {
                                        width: parent.width
                                        visible: modelData.claude !== ""
                                        text: Model.trim(modelData.claude, 240)
                                        font.family: Style.font.family
                                        font.pixelSize: Style.font.bodySmall
                                        color: Color.muted
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: !service || service.opened.length === 0
                        text: "reading…"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        color: Color.muted
                        leftPadding: Style.space(14)
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.popups.text, 0.14) }

                // ---------- ask by typing ----------
                Item {
                    width: parent.width
                    visible: root.view === "now"
                    height: visible ? Style.space(44) : 0

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Style.space(14)
                        anchors.rightMargin: Style.space(14)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(8)

                        VoiceGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            state: "typing"
                            color: Color.muted
                            size: Style.font.body
                        }

                        TextField {
                            id: askField
                            width: parent.width - Style.space(30)
                            anchors.verticalCenter: parent.verticalCenter
                            foreground: Color.popups.text
                            placeholderText: "ask without speaking"
                            onAccepted: {
                                if (service.ask(text)) {
                                    text = ""
                                    root.close()
                                }
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Util.alpha(Color.popups.text, 0.14) }

                // ---------- footer ----------
                Item {
                    width: parent.width
                    height: Style.space(48)

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: Style.space(14)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(8)

                        // Order is the order they are reached by the keyboard:
                        // clear, then log to its right, then the list.
                        Button {
                            visible: root.view === "now"
                            bordered: true
                            fontSize: Style.font.bodySmall
                            text: "clear"
                            hasCursor: root.view === "now" && !root.head && root.cursor === 0
                            onClicked: { service.clearSession(); root.close() }
                        }
                        Button {
                            visible: root.view === "now"
                            bordered: true
                            fontSize: Style.font.bodySmall
                            text: "log"
                            hasCursor: root.view === "now" && !root.head && root.cursor === 1
                            onClicked: { service.logSession(); root.close() }
                        }
                        Button {
                            visible: root.view === "now"
                            bordered: true
                            fontSize: Style.font.bodySmall
                            text: "conversations"
                            hasCursor: root.view === "now" && !root.head && root.cursor === 2
                            onClicked: root.showList()
                        }
                        Button {
                            visible: root.view === "reading" && root.openedMeta && !root.openedMeta.live
                            bordered: true
                            fontSize: Style.font.bodySmall
                            text: "resume"
                            hasCursor: root.view === "reading" && root.cursor === 0
                            onClicked: {
                                service.resume(root.openedMeta.file)
                                root.close()
                            }
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: Style.space(14)
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.head ? "enter approve · bksp discard"
                            : root.view === "list" ? "↑↓ move · enter open · del forget · esc back"
                            : root.view === "reading" ? "esc back"
                            : "↑↓ move · enter choose · esc close"
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        color: Color.muted
                    }
                }
            }
        }
    }

    // ---------- the write waiting on a person ----------
    Component {
        id: approvalCard

        Column {
            spacing: 0
            bottomPadding: Style.space(12)

            Text {
                text: "WANTS TO WRITE"
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1.4
                color: Color.urgent
                leftPadding: Style.space(14)
                topPadding: Style.space(11)
                bottomPadding: Style.space(5)
            }

            Row {
                leftPadding: Style.space(14)
                spacing: Style.space(8)
                bottomPadding: Style.space(6)

                Text {
                    text: root.head ? root.head.api + " · " + root.head.tool : ""
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    color: Color.popups.text
                }
                Text {
                    text: root.head ? root.head.method : ""
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Color.urgent
                }
            }

            Repeater {
                model: {
                    if (!root.head || !root.head.arguments) return []
                    var rows = []
                    for (var key in root.head.arguments)
                        rows.push({ key: key, value: String(root.head.arguments[key]) })
                    return rows
                }

                Row {
                    required property var modelData
                    leftPadding: Style.space(14)
                    spacing: Style.space(10)
                    height: Style.space(19)

                    Text {
                        width: Style.space(72)
                        text: modelData.key
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        color: Color.muted
                    }
                    Text {
                        text: modelData.value
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.features: ({ "tnum": 1 })
                        color: Color.popups.text
                    }
                }
            }

            // The transcript is the point: it shows the words that produced the
            // call, which is what you are actually judging.
            Text {
                visible: root.head && root.head.transcript
                leftPadding: Style.space(14)
                rightPadding: Style.space(14)
                topPadding: Style.space(8)
                width: content.width
                text: root.head ? "heard: “" + Model.trim(root.head.transcript, 110) + "”" : ""
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.muted
                wrapMode: Text.WordWrap
            }

            Row {
                leftPadding: Style.space(14)
                topPadding: Style.space(10)
                spacing: Style.space(8)

                Button {
                    bordered: true
                    fontSize: Style.font.bodySmall
                    text: "approve"
                    onClicked: if (root.head) service.decide(root.head.id, true)
                }
                Button {
                    bordered: true
                    fontSize: Style.font.bodySmall
                    text: "discard"
                    onClicked: if (root.head) service.decide(root.head.id, false)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.head ? "expires in " + Model.humanDuration(Math.max(0, root.head.expires_at - service.now)) : ""
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Color.muted
                }
            }
        }
    }
}
