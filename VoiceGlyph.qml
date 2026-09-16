import QtQuick
import qs.Commons
import qs.Ui

// One Nerd Font glyph per state, drawn the way the rest of the bar draws icons:
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
        "idle":         "",  // microphone
        "listening":    "",  // microphone, lit by colour rather than shape
        "transcribing": "",  // signal bars
        "thinking":     "",  // spinner, the one state with no other progress cue
        "tool":         "",  // cog
        "waiting":      "",  // exclamation in a circle
        "speaking":     "",  // speaker with waves
        "failed":       "",  // microphone, struck through
        "typing":       ""   // keyboard
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
