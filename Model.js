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


// Collapse a reply to something that fits a panel row without hiding that it
// was cut. Full text stays in the log and on the clipboard.
function trim(text, max) {
    var flat = String(text || "").replace(/\s+/g, " ").trim()
    return flat.length <= max ? flat : flat.slice(0, max).replace(/\s+\S*$/, "") + "…"
}


// "15 Sep 02:08 · 5 turns · live", the one line under a conversation title.
function conversationMeta(entry) {
    var bits = []

    if (entry.startedAt) {
        var when = new Date(entry.startedAt)
        if (!isNaN(when.getTime())) {
            var months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
            var today = new Date()
            var sameDay = when.toDateString() === today.toDateString()
            var clockPart = ("0" + when.getHours()).slice(-2) + ":" + ("0" + when.getMinutes()).slice(-2)
            bits.push(sameDay ? "today " + clockPart
                              : when.getDate() + " " + months[when.getMonth()] + " " + clockPart)
        }
    }

    bits.push(entry.turns + (entry.turns === 1 ? " turn" : " turns"))
    if (entry.live) bits.push("live")

    return bits.join(" · ")
}
