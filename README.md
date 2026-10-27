# herdr-attention-jump

A [Herdr](https://herdr.dev) plugin that steps to the next or previous agent that needs attention, in sidebar order, wrapping around.

An agent is included when it is **working**, **blocked**, **done**, or **idle with a state change since you last focused it**. Herdr's green Done badge is tracked per TUI client and isn't exposed over the API, which reports most finished agents as plain `idle`. The plugin keeps its own record of each agent's `state_change_seq` at the moment it was last focused. It updates that record on every `pane.focused` and `pane.agent_status_changed` event, so visits by click or other navigation count too.

Requires `jq`. `flock` is optional; it serialises concurrent state updates.

## Install

```sh
herdr plugin link ~/Dev/herdr-attention-jump
```

Bind the actions in `~/.config/herdr/config.toml`:

```toml
[[keys.command]]
key = "alt+shift+up"
type = "plugin_action"
command = "twiking.attention-jump.prev"
description = "Previous agent needing attention"

[[keys.command]]
key = "alt+shift+down"
type = "plugin_action"
command = "twiking.attention-jump.next"
description = "Next agent needing attention"
```

Then run `herdr server reload-config`.

## Actions

| Action | |
|---|---|
| `twiking.attention-jump.next` | Focus the next agent needing attention |
| `twiking.attention-jump.prev` | Focus the previous agent needing attention |
| `twiking.attention-jump.reset` | Forget which agents have been seen |

State lives in `$HERDR_PLUGIN_STATE_DIR/seen.json`. Debug with `herdr plugin log list --plugin twiking.attention-jump`.
