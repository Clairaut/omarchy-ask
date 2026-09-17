# clairaut.ask

Omarchy shell plugin: the bar widget and panel for the SUPER+H assistant
(`~/.local/bin/ask`). Quickshell/QML. Installed as a chezmoi external, so this is
a real working clone: edit and commit in place.

Reload with `omarchy restart shell`, then read the newest log under
`/run/user/1000/quickshell/by-id/*/log.qslog`. A warning that another handler is
already registered for `clairaut.ask` is normal and every plugin emits it.

## Files

- `Service.qml` - all state and every subprocess. The panel renders, it does not
  fetch.
- `Panel.qml` - two views, `now` and `list`. Reading an archived conversation is
  not a third view: it loads into the session section, which already renders a
  list of turns and can expand them.
- `Model.js` - parsing and formatting helpers, no state.
- `StateGlyph.qml` - one glyph per assistant state.

## Traps that have already cost time

- **`state.json` is replaced by rename**, so a `FileView` watch on it holds an
  unlinked inode and stops firing after the first write. It is reloaded on the
  one-second tick instead. Watching any file the script rewrites has this
  problem.
- **`PanelKeyCatcher` returns before reading any key while `blocked`**, and it is
  blocked exactly while the ask field has focus. Escape and the arrows must be
  handled on the field itself or it is a keyboard trap.
- **Do not declare `Keys.onPressed` on `PanelKeyCatcher`**: it replaces the
  component's own handler rather than adding to it. Use its signals, including
  `textKey` for plain letters. Note `deleteRequested` fires on `x`, not Delete.
- **A tool result is recorded as a `type:"user"` message.** Counting those
  overstates a conversation's length; only messages carrying text are turns.
- The cursor is one flat index per view. When items are added ahead of the
  buttons, every `hasCursor` after them shifts.

## Keep in step with the script

The panel shells out to `ask` for everything that changes state (`--clear`,
`--log`, `--resume`, `--forget`, `--mute`, and a bare argument to ask a
question). If a flag changes there, it changes here. Passing a flag the script
does not know gets a silent "Unknown option" the panel never surfaces.
