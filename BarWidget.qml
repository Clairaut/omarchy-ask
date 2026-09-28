import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The bar face. The host injects bar/moduleName/settings into this item, probes
// it for open/close/opened, and compares activePopout against it: so the panel
// contract has to live here rather than in a file this loads.
BarWidget {
    id: root
    moduleName: "clairaut.ask"

    // The pollers live in the plugin's service entry point, so one instance serves
    // every screen instead of one per bar. The host injects `bar` on a later tick
    // and creates services on its own schedule, so resolve on both and retry.
    property var service: null
    readonly property string state: service ? service.currentState : "idle"

    function resolveService() {
        var shellApi = root.bar ? root.bar.shell : null
        var next = (shellApi && typeof shellApi.serviceFor === "function")
            ? shellApi.serviceFor(root.moduleName) : null
        if (next === root.service) return
        if (root.service) root.service.detach()
        root.service = next
        if (root.service) root.service.attach()
    }

    onBarChanged: resolveService()
    Component.onCompleted: resolveService()
    Component.onDestruction: if (root.service) root.service.detach()

    Timer {
        interval: 500
        repeat: true
        running: root.service === null
        onTriggered: root.resolveService()
    }
    readonly property var tone: Model.describe(state)

    // One colour rule: only a request that needs a person changes hue. Everything
    // else varies by weight, so a glance distinguishes "busy" from "waiting".
    readonly property color glyphColor: {
        if (tone.tone === "urgent") return Color.urgent
        if (tone.tone === "good") return Color.pick ? Color.pick("bar.text", Color.foreground) : Color.foreground
        if (tone.tone === "dim") return Color.muted
        return root.bar ? root.bar.barForeground : Color.foreground
    }

    // Width is fixed across states so the bar never reflows mid-turn.
    readonly property int slotWidth: Style.space(58)

    readonly property string trailing: {
        if (!service) return ""
        if (state === "waiting") return String(service.pending.length)
        if (state === "listening" || state === "speaking") return Model.clock(service.stateAge)
        if (state === "thinking" || state === "transcribing") return service.stateAge + "s"
        if (state === "failed") return "!"
        return String(service.turns)
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    // ---------- panel contract the bar host probes for ----------
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

    function open() { if (panelLoader.item) panelLoader.item.open() }
    function close() { if (panelLoader.item) panelLoader.item.close() }
    function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
    function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        labelVisible: false
        hasVisualContent: true
        fixedWidth: root.slotWidth
        tooltipText: {
            if (!service) return "AI Assistant"
            if (root.state === "waiting")
                return service.pending.length + " write waiting on you, click to review"
            if (root.state === "idle")
                return "AI Assistant: " + service.turns + " turns" +
                       (service.sessionAge > 0 ? ", " + Model.humanDuration(service.sessionAge) + " old" : "")
            return root.tone.label + (service.state && service.state.detail
                ? ": " + Model.trim(service.state.detail, 60) : "")
        }
        onPressed: root.togglePanel()

        Row {
            anchors.centerIn: parent
            spacing: Style.space(6)

            StateGlyph {
                anchors.verticalCenter: parent.verticalCenter
                state: root.state
                color: root.glyphColor
                // iconFont, not iconCanvas: the stock bar buttons render their
                // glyph at the former and reserve the latter for the canvas.
                size: Style.bar.iconFont
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.trailing
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.features: ({ "tnum": 1 })
                color: root.glyphColor
            }
        }
    }

    Loader {
        id: panelLoader
        source: Qt.resolvedUrl("Panel.qml")
        visible: false
    }

    // injectProps() writes into this file only, and runs again on a later tick,
    // so these bind downward rather than being assigned once.
    Binding { target: panelLoader.item; property: "bar";        value: root.bar;        when: panelLoader.item }
    Binding { target: panelLoader.item; property: "settings";   value: root.settings;   when: panelLoader.item }
    Binding { target: panelLoader.item; property: "anchorItem"; value: root;            when: panelLoader.item }
    Binding { target: panelLoader.item; property: "hostWidget"; value: root;            when: panelLoader.item }
    Binding { target: panelLoader.item; property: "service";    value: root.service;    when: panelLoader.item }
}
