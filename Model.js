.pragma library

// The states voice-ai writes into state.json, plus "waiting", which the widget
// infers when the approval queue is not empty. Anything unrecognised falls back
// to idle rather than rendering nothing.
var STATES = {
    idle:         { label: "Idle",          tone: "dim"    },
    listening:    { label: "Listening",     tone: "bright" },
    transcribing: { label: "Transcribing",  tone: "mid"    },
    thinking:     { label: "Thinking",      tone: "mid"    },
    tool:         { label: "Calling a tool", tone: "good"  },
    waiting:      { label: "Waiting on you", tone: "urgent" },
    speaking:     { label: "Speaking",      tone: "bright" },
    failed:       { label: "Failed",        tone: "urgent" }
}

function describe(name) {
    return STATES[name] || STATES.idle
}

// Parse state.json. Unreadable or half-written state is treated as idle: the
// script replaces the file atomically, but a reader should never throw.
function parseState(text) {
    try {
        var parsed = JSON.parse(String(text || ""))
        if (!parsed || typeof parsed !== "object") return null
        return {
            state: String(parsed.state || "idle"),
            detail: String(parsed.detail || ""),
            at: Number(parsed.at || 0),
            turns: Number(parsed.turns || 0),
            sessionStartedAt: Number(parsed.session_started_at || 0)
        }
    } catch (e) {
        return null
    }
}

// "2h 38m", "4m", "just now": a duration a person reads at a glance.
function humanDuration(seconds) {
    if (!seconds || seconds < 0) return ""
    if (seconds < 60) return "just now"

    var minutes = Math.floor(seconds / 60)
    if (minutes < 60) return minutes + "m"

    var hours = Math.floor(minutes / 60)
    var rest = minutes % 60
    return rest === 0 ? hours + "h" : hours + "h " + rest + "m"
}

// mm:ss, for an elapsed recording or clip.
function clock(seconds) {
    if (!seconds || seconds < 0) seconds = 0
    var m = Math.floor(seconds / 60)
    var s = Math.floor(seconds % 60)
    return m + ":" + (s < 10 ? "0" : "") + s
}

// Split the plain-text log into exchanges, newest first. The log is the record
// the script already keeps, so the panel reads it rather than inventing a
// second store that could disagree with it.
function parseLog(text, limit) {
    var entries = []
    var blocks = String(text || "").split(/\n===== /)

    for (var i = blocks.length - 1; i >= 0 && entries.length < (limit || 8); i--) {
        var block = blocks[i]
        if (!block) continue

        var stampMatch = block.match(/^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/)
        var youMatch = block.match(/YOU: ([\s\S]*?)\n\nCLAUDE:/)
        var claudeMatch = block.match(/CLAUDE: ([\s\S]*?)(?:\n\[saved:|$)/)
        if (!youMatch || !claudeMatch) continue

        var stamp = stampMatch ? stampMatch[1] : ""
        entries.push({
            time: stamp ? stamp.slice(11, 16) : "",
            you: youMatch[1].trim(),
            claude: claudeMatch[1].trim(),
            saved: /\n\[saved: /.test(block)
        })
    }

    return entries
}

// Collapse a reply to something that fits a panel row without hiding that it
// was cut. Full text stays in the log and on the clipboard.
function trim(text, max) {
    var flat = String(text || "").replace(/\s+/g, " ").trim()
    return flat.length <= max ? flat : flat.slice(0, max).replace(/\s+\S*$/, "") + "…"
}
