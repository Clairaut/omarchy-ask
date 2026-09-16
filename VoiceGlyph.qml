import QtQuick
import qs.Commons
import qs.Ui

// One Nerd Font glyph per state. At rest it is a speech bubble rather than a
// microphone, because the assistant takes typed input too; listening keeps the
// microphone, since while recording that is literally what it is.
//
// Drawn the way the rest of the bar draws icons:
// OpticalGlyph over Style.font.family, so this sits on the same baseline and
// optical centre as the stock widgets rather than looking hand-placed.
//
// Codepoints are Font Awesome, which JetBrainsMono Nerd Font carries in full.
Item {
    id: root

    property string state: "idle"
    property color color: Color.foreground
    property int size: Style.font.icon

    readonly property var glyphs: ({
        "idle":         "\uf075",  // speech bubble: it takes voice or typing now
        "listening":    "\uf130",  // microphone, because while recording it is one
        "transcribing": "\uf012",  // signal bars
        "thinking":     "\uf110",  // spinner, the one state with no other progress cue
        "tool":         "\uf013",  // cog
        "waiting":      "\uf06a",  // exclamation in a circle
        "speaking":     "\uf028",  // speaker with waves
        "failed":       "\uf131",  // microphone, struck through
        "typing":       "\uf11c"   // keyboard
    })

    implicitWidth: size
    implicitHeight: size

    OpticalGlyph {
        id: glyph
        anchors.fill: parent
        text: root.glyphs[root.state] || root.glyphs["idle"]
        fontSize: root.size
        color: root.color

        // Only the spinner turns, and only while thinking. A bar icon that moves
        // the rest of the time is noise.
        transform: Rotation {
            origin.x: glyph.width / 2
            origin.y: glyph.height / 2
            angle: spin.angle
        }
    }

    QtObject {
        id: spin
        property real angle: 0
    }

    NumberAnimation {
        target: spin
        property: "angle"
        from: 0
        to: 360
        duration: 1600
        loops: Animation.Infinite
        running: root.state === "thinking"
        onRunningChanged: if (!running) spin.angle = 0
    }
}
