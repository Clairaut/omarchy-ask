import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Everything the widget and the panel both need to know, in one place, so the
// bar face and the dropdown can never disagree about what the assistant is doing.
//
// voice-ai runs per keypress and exits, so there is no process to ask. State is
// files: state.json for the current transition, queue/*.json for writes waiting
// on approval, and the plain-text log for what has been said.
Item {
    id: root

    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/voice-ai"
    readonly property string queueDir: runtimeDir + "/queue"
    readonly property string logPath: Quickshell.env("HOME") + "/.local/share/voice-ai/log.txt"
    readonly property string binary: Quickshell.env("HOME") + "/.local/bin/voice-ai"

    property var state: null
    property var pending: []
    property var exchanges: []
    property int now: 0

    // A parked write outranks whatever the script last wrote: it is the thing
    // that actually needs the person.
    readonly property string currentState: pending.length > 0 ? "waiting" : (state ? state.state : "idle")
    readonly property int turns: state ? state.turns : 0
    readonly property int sessionAge: (state && state.sessionStartedAt) ? Math.max(0, now - state.sessionStartedAt) : 0
    readonly property int stateAge: (state && state.at) ? Math.max(0, now - state.at) : 0

    // ---------- current state ----------
    FileView {
        path: root.runtimeDir + "/state.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.state = Model.parseState(text())
        onLoadFailed: root.state = null
    }

    // ---------- conversation ----------
    FileView {
        path: root.logPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.exchanges = Model.parseLog(text(), 6)
        onLoadFailed: root.exchanges = []
    }

    // ---------- approval queue ----------
    // A directory cannot be watched the way a file can, so it is polled. One
    // second is far below the five-minute expiry and costs nothing when empty.
    Process {
        id: queueScan
        running: false
        command: ["sh", "-c", "cat " + root.queueDir + "/*.json 2>/dev/null | tr -d '\\n' | sed 's/}{/}\\n{/g'"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyQueue(text)
        }
    }

    function applyQueue(output) {
        var items = []
        var lines = String(output || "").split("\n")

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (!line) continue
            try {
                var parsed = JSON.parse(line)
                if (parsed && parsed.id) items.push(parsed)
            } catch (e) {
                // A half-written file will parse on the next tick.
            }
        }

        root.pending = items
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root.now = Math.floor(Date.now() / 1000)
            if (!queueScan.running) queueScan.running = true
        }
    }

    // ---------- actions ----------
    Process { id: actionProc; running: false }

    function decide(requestId, approved) {
        actionProc.command = ["sh", "-c",
            "printf '%s' " + (approved ? "approved" : "denied") +
            " > " + root.queueDir + "/" + requestId + ".decision"]
        actionProc.running = true
    }

    function clearSession() {
        actionProc.command = [root.binary, "--clear"]
        actionProc.running = true
    }

    // Typing is sometimes the right input: a word whisper keeps mishearing, or
    // the room is not one to talk out loud in.
    function ask(text) {
        var trimmed = String(text || "").trim()
        if (trimmed === "") return false
        actionProc.command = [root.binary, "--ask", trimmed]
        actionProc.running = true
        return true
    }

    function openLog() {
        actionProc.command = ["sh", "-c", "xdg-open " + root.logPath + " >/dev/null 2>&1 &"]
        actionProc.running = true
    }
}
