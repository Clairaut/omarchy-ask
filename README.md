# clairaut.ask

An [Omarchy](https://omarchy.org) shell plugin: a bar widget and panel for a
keyboard-driven AI assistant. The glyph shows what the assistant is doing, and
the panel holds the conversation, the typed input, and any write waiting on
approval.

The widget is the front end. The assistant itself is a separate script,
`~/.local/bin/ask`, which this drives.

## Install

```bash
omarchy plugin clone https://github.com/Clairaut/omarchy-ask clairaut.ask
```

Then add it to the bar in `~/.config/omarchy/shell.json`:

```json
{ "id": "clairaut.ask" }
```

and restart the shell:

```bash
omarchy restart shell
```

Glyphs render from **JetBrainsMono Nerd Font**. Without it the bar shows boxes
(`omarchy pkg add ttf-jetbrains-mono-nerd`).

## What the glyph means

One glyph per state, read from a JSON file the script writes:

| State | Meaning |
|---|---|
| idle | nothing in flight |
| listening | recording |
| transcribing | turning speech into text |
| thinking | waiting on a reply |
| tool | calling a tool |
| waiting | a write is parked for your approval |
| speaking | reading the answer aloud |
| failed | the last turn did not finish |

## The panel

Click the glyph, or bind a key to it:

```bash
qs -p /usr/share/omarchy/shell ipc call clairaut.ask toggle
```

It opens on the current conversation, newest turn first.

| Key | Does |
|---|---|
| `↑` `↓` / `k` `j` | move the cursor |
| `enter` | expand a turn to its full reply, or press the control under the cursor |
| `m` | mute, so answers are written but not spoken |
| `x` | discard a parked write, or forget an archived conversation |
| `esc` | back, then close |
| `tab` | next panel |

`clear` ends the conversation and keeps nothing. `log` files it away instead, so
it stays readable under `conversations`, where `enter` opens one in place and
`resume` picks it back up.

## What it expects

- `~/.local/bin/ask`, which owns all the state. The panel shells out to it for
  every action rather than duplicating any of its logic.
- `$XDG_RUNTIME_DIR/ask/` for the state file and the approval queue.
- Conversation transcripts in the Claude project directory derived from the
  assistant's session path.

Everything else, including the assistant script, lives in
[Clairaut/dotfiles](https://github.com/Clairaut/dotfiles).
