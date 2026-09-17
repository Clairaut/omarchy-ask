import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Everything the widget and the panel both need to know, in one place, so the
// bar face and the dropdown can never disagree about what the assistant is doing.
//
// ask runs per keypress and exits, so there is no process to ask. State is
// files: state.json for the current transition, queue/*.json for writes waiting
// on approval, and the plain-text log for what has been said.
Item {
    id: root

    readonly property string runtimeDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ask"
    readonly property string queueDir: runtimeDir + "/queue"
    readonly property string logPath: Quickshell.env("HOME") + "/.local/share/ask/log.txt"
    readonly property string binary: Quickshell.env("HOME") + "/.local/bin/ask"

    // claude --continue keys off the working directory, so its transcripts live
    // in a project directory derived from the session path.
    readonly property string projectDir: Quickshell.env("HOME") + "/.claude/projects/"
        + String(Quickshell.env("HOME") + "/.local/share/ask/session").replace(/[/.]/g, "-")

    property var conversations: []
    property var state: null
    property var pending: []
    property bool muted: false
    property var exchanges: []
    property int now: 0

    // A parked write outranks whatever the script last wrote: it is the thing
    // that actually needs the person.
    readonly property string currentState: pending.length > 0 ? "waiting" : (state ? state.state : "idle")
    readonly property int turns: state ? state.turns : 0
    readonly property int sessionAge: (state && state.sessionStartedAt) ? Math.max(0, now - state.sessionStartedAt) : 0
    readonly property int stateAge: (state && state.at) ? Math.max(0, now - state.at) : 0

    // ---------- current state ----------
    // The script writes this file by renaming a temp file over it, so the watch
    // ends up holding an inode that no longer exists and stops firing after the
    // first write. watchChanges is kept for the case where it does fire; the
    // reload on the tick below is what actually keeps this current.
    FileView {
        id: stateFile
        path: root.runtimeDir + "/state.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.state = Model.parseState(text())
        onLoadFailed: root.state = null
    }

    // ---------- muted ----------
    // A flag file rather than a field in state.json, because it is toggled when
    // the script is not running and state.json is only written when it is.
    FileView {
        id: muteFlag
        path: root.runtimeDir + "/muted"
        watchChanges: true
        printErrors: false
        onLoaded: root.muted = true
        onLoadFailed: root.muted = false
    }

    function toggleMute() {
        actionProc.command = [root.binary, "--mute"]
        actionProc.running = true
    }

    // ---------- the current conversation ----------
    // Read from the live transcript, not log.txt: the log is append-only across
    // every session and never cleared, so it mixes conversations together and
    // shows turns from ones that have since been archived.
    Process {
        id: currentScan
        running: false
        command: ["sh", "-c", "cat " + root.projectDir + "/*.jsonl 2>/dev/null | tail -n 600"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                var all = root.parseTranscript(text)
                root.exchanges = all.slice(-6).reverse()
            }
        }
    }

    function refreshCurrent() {
        if (!currentScan.running) currentScan.running = true
    }

    // A completed turn is the only thing that changes the current conversation.
    onTurnsChanged: refreshCurrent()
    Component.onCompleted: refreshCurrent()

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
            stateFile.reload()
            muteFlag.reload()
            if (!queueScan.running) queueScan.running = true
        }
    }

    // ---------- stored conversations ----------
    // One line per transcript: live flag, filename, turn count, first timestamp,
    // and the first thing asked, which makes a better title than any id.
    Process {
        id: listScan
        running: false
        command: ["sh", "-c",
            "for f in " + root.projectDir + "/*.jsonl " + root.projectDir + "/archive/*.jsonl; do " +
            "[ -f \"$f\" ] || continue; " +
            "case \"$f\" in */archive/*) live=0 ;; *) live=1 ;; esac; " +
            // Tool results are recorded as user messages too, so counting every
            // one of them would report a conversation as longer than it reads.
            // A real turn is the one carrying text rather than a result block.
            "turns=$(grep '\"type\":\"user\"' \"$f\" 2>/dev/null | grep -c '\"content\":\"' || echo 0); " +
            "ts=$(grep -o '\"timestamp\":\"[^\"]*\"' \"$f\" 2>/dev/null | head -1 | cut -d'\"' -f4); " +
            // "content":" is eleven characters, so the text starts at twelve; the prompt
            // also carries escaped newlines, and only the first line is a usable title.
            "q=$(grep -o '\"type\":\"user\".*' \"$f\" 2>/dev/null | head -1 | grep -o '\"content\":\"[^\"]*' | head -1 | cut -c12- | sed 's/\\\\n.*//' | cut -c1-90); " +
            "printf '%s\\t%s\\t%s\\t%s\\t%s\\n' \"$live\" \"$(basename \"$f\")\" \"$turns\" \"$ts\" \"$q\"; done"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyConversations(text)
        }
    }

    function rescanConversations() {
        if (!listScan.running) listScan.running = true
    }

    function applyConversations(output) {
        var found = []
        var lines = String(output || "").split("\n")

        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].split("\t")
            if (parts.length < 5) continue
            found.push({
                live: parts[0] === "1",
                file: parts[1],
                turns: parseInt(parts[2]) || 0,
                startedAt: parts[3],
                title: parts[4] || "(no prompt recorded)"
            })
        }

        // Live first, then newest archived.
        found.sort(function (a, b) {
            if (a.live !== b.live) return a.live ? -1 : 1
            return a.startedAt < b.startedAt ? 1 : -1
        })
        root.conversations = found
    }

    // Read one transcript into turns the panel can render. Only user text and
    // assistant text: thinking blocks and tool plumbing are not the record.
    Process {
        id: readScan
        running: false
        property string file: ""
        stdout: StdioCollector {
            waitForEnd: true
            // Newest first, the same way the session reads, since both now render
                // through the one list.
                onStreamFinished: root.opened = root.parseTranscript(text).reverse()
        }
    }

    property var opened: []
    property string openedFile: ""

    function openConversation(file, live) {
        root.openedFile = file
        var path = live ? root.projectDir + "/" + file : root.projectDir + "/archive/" + file
        readScan.command = ["sh", "-c", "cat " + path.replace(/'/g, "") ]
        readScan.running = true
    }

    function parseTranscript(text) {
        var turns = []
        var lines = String(text || "").split("\n")
        var pendingUser = null

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (!line) continue
            var record
            try { record = JSON.parse(line) } catch (e) { continue }

            var message = record.message
            if (!message) continue

            if (record.type === "user" && typeof message.content === "string") {
                pendingUser = { time: String(record.timestamp || "").slice(11, 16), you: message.content, claude: "" }
                turns.push(pendingUser)
            } else if (record.type === "assistant" && pendingUser) {
                var blocks = message.content
                if (!Array.isArray(blocks)) continue
                for (var b = 0; b < blocks.length; b++) {
                    if (blocks[b].type === "text" && blocks[b].text)
                        pendingUser.claude += (pendingUser.claude ? " " : "") + blocks[b].text
                }
            }
        }
        return turns
    }

    // ---------- actions ----------
    Process { id: actionProc; running: false }

    function decide(requestId, approved) {
        actionProc.command = ["sh", "-c",
            "printf '%s' " + (approved ? "approved" : "denied") +
            " > " + root.queueDir + "/" + requestId + ".decision"]
        actionProc.running = true
    }

    // clear ends the conversation without keeping it; log files it away so it
    // stays readable in the conversations list.
    function clearSession() {
        actionProc.command = [root.binary, "--clear"]
        actionProc.running = true
    }

    function logSession() {
        actionProc.command = [root.binary, "--log"]
        actionProc.running = true
    }

    function forget(file) {
        actionProc.command = [root.binary, "--forget", file]
        actionProc.running = true
        rescanConversations()
    }

    // Typing is sometimes the right input: a word whisper keeps mishearing, or
    // the room is not one to talk out loud in.
    function ask(text) {
        var trimmed = String(text || "").trim()
        if (trimmed === "") return false
        actionProc.command = [root.binary, trimmed]
        actionProc.running = true
        return true
    }

    function resume(file) {
        actionProc.command = [root.binary, "--resume", file]
        actionProc.running = true
    }

    function openLog() {
        actionProc.command = ["sh", "-c", "xdg-open " + root.logPath + " >/dev/null 2>&1 &"]
        actionProc.running = true
    }
}
