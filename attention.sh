#!/bin/sh
# Usage: attention.sh next|prev|seen|reset
#
# next/prev: focus the next/previous agent that needs attention, in sidebar order,
#            wrapping around. Included: working, blocked, done, or idle with a state
#            change since it was last seen.
# seen:      record the focused agent as seen (run from the pane.focused and
#            pane.agent_status_changed event hooks).
# reset:     forget all visits.
#
# The TUI's green Done badge is tracked per client and isn't exposed over the API,
# which reports most finished agents as plain idle. So we keep our own record of the
# state_change_seq each agent had when it was last focused.
herdr="${HERDR_BIN_PATH:-herdr}"
cmd="${1:-next}"
state_dir="${HERDR_PLUGIN_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/herdr/attention-jump}"
state_file="$state_dir/seen.json"

mkdir -p "$state_dir"

if [ "$cmd" = reset ]; then
  rm -f "$state_file"
  exit 0
fi

# Event hooks and key presses can run at the same time; serialise the read-modify-write
exec 9>"$state_dir/lock"
command -v flock >/dev/null 2>&1 && flock -w 5 9

seen=$(jq -c 'objects' "$state_file" 2>/dev/null)
[ -n "$seen" ] || seen='{}'

save() {
  printf '%s\n' "$1" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
}

agents=$("$herdr" agent list) || exit 1

# Forget panes that are gone, and mark the focused agent as seen. state_change_seq
# lives only in server memory and pane ids can be reused after a restart, so a
# stored seq above the current one is from a previous server: drop it.
seen=$(jq -c --argjson a "$agents" '
  . as $seen
  | $a.result.agents
  | (map(.state_change_seq as $s
      | {key: .pane_id, value: ($seen[.pane_id] // -1 | if . > $s then -1 else . end)})
     | from_entries) as $kept
  | (map(select(.focused)) | first) as $f
  | if $f then $kept | .[$f.pane_id] = $f.state_change_seq else $kept end' <<EOF
$seen
EOF
) || exit 1

if [ "$cmd" = seen ]; then
  save "$seen"
  exit 0
fi

workspaces=$("$herdr" workspace list) || exit 1

target=$(jq -rn --arg dir "$cmd" --argjson ws "$workspaces" --argjson a "$agents" --argjson seen "$seen" '
  ($ws.result.workspaces | map({key: .workspace_id, value: .number}) | from_entries) as $num
  | ($ws.result.workspaces | map(select(.focused)) | first | .number // 0) as $curws
  # Sidebar order: workspace number, then the order agent list gives within a workspace
  | [$a.result.agents | to_entries[] | .value + {k: [$num[.value.workspace_id], .key]}]
  | sort_by(.k) as $agents
  # Cursor: the focused agent, or the top of the focused workspace if no agent has focus
  | (($agents | map(select(.focused)) | first | .k) // [$curws, -1]) as $cur
  | [$agents[] | select(
      (.agent_status | IN("working", "blocked", "done"))
      or (.agent_status == "idle" and .state_change_seq > $seen[.pane_id]))] as $hits
  | if $dir == "prev"
    then ([$hits[] | select(.k < $cur)] | last) // ($hits | last)
    else ([$hits[] | select(.k > $cur)] | first) // ($hits | first)
    end
  | .pane_id // empty') || exit 1

if [ -z "$target" ]; then
  save "$seen"
  "$herdr" notification show "Nothing needs attention" --sound none >/dev/null 2>&1
  exit 0
fi

if "$herdr" agent focus "$target" >/dev/null; then
  # Focusing can itself change the state (done -> idle), so record the seq after it
  seq=$("$herdr" agent get "$target" | jq '.result.agent.state_change_seq // empty')
  [ -n "$seq" ] && seen=$(printf '%s' "$seen" | jq -c --arg p "$target" --argjson s "$seq" '.[$p] = $s')
fi

save "$seen"
