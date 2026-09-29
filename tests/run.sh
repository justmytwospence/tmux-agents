#!/usr/bin/env bash
# Tests against a private tmux server (TMUX_TMPDIR isolates its socket).
# Usage: tests/run.sh    (needs tmux and jq)
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export TMUX_TMPDIR
TMUX_TMPDIR=$(mktemp -d /tmp/tmux-agents-test.XXXXXX)
export TMUX_AGENTS_JOBMAP="$TMUX_TMPDIR/jobmap" TMUX_AGENTS_PREVLIVE="$TMUX_TMPDIR/prevlive"
export TMUX_AGENTS_FLEETPREV="$TMUX_TMPDIR/fleetprev" TMUX_AGENTS_NOTIFIED="$TMUX_TMPDIR/notified"
export TMUX_AGENTS_ROSTER="$TMUX_TMPDIR/roster.json" TMUX_AGENTS_JOBS_DIR="$TMUX_TMPDIR/jobs"
unset TMUX TMUX_PANE HERDR_ENV SSH_CLIENT SSH_CONNECTION
failures=0

cleanup() {
    tmux kill-server 2>/dev/null
    rm -rf "$TMUX_TMPDIR"
}
trap cleanup EXIT

check() { # check <description> <expected> <actual>
    if [ "$2" = "$3" ]; then
        printf 'ok   %s\n' "$1"
    else
        printf 'FAIL %s: expected [%s], got [%s]\n' "$1" "$2" "$3"
        failures=$((failures + 1))
    fi
}
pane_state() { tmux show-options -pqv -t "$1" @agent_state; }
win_tab() { tmux show-options -wqv -t "$1" @agent_tab; }
hook() { # hook <pane> <json>: run claude-hook as if Claude ran it in that pane
    printf '%s' "$2" | TMUX_PANE="$1" TMUX="$(tmux display -p '#{socket_path}'),0,0" "$ROOT/bin/claude-hook"
}

tmux -f /dev/null new-session -d -s t -x 120 -y 30
tmux new-window -t t
tmux select-window -t t:0
w0=$(tmux display -p -t t:0 '#{window_id}'); w1=$(tmux display -p -t t:1 '#{window_id}')
p0=$(tmux display -p -t t:0 '#{pane_id}'); p1=$(tmux display -p -t t:1 '#{pane_id}')

tmux run-shell "$ROOT/tmux-agents.tmux"
case "$(tmux show-option -gv window-status-format)" in *@agent_tab*) r=yes ;; *) r=no ;; esac
check "loading sets the tab formats" yes "$r"
case "$(tmux show-option -gv status-right)" in *@agent_badge*) r=yes ;; *) r=no ;; esac
check "loading adds the badge to status-right" yes "$r"
case "$(tmux show-hooks -g pane-focus-in 2>/dev/null)" in *@agent_state*) r=yes ;; *) r=no ;; esac
check "loading sets the pane-focus-in hook" yes "$r"

# An agent in the background window (t:1) works, then finishes.
hook "$p1" '{"hook_event_name":"UserPromptSubmit","session_id":"s1"}'
check "UserPromptSubmit marks the pane running" running "$(pane_state "$p1")"
check "and its window tab" running "$(win_tab "$w1")"
hook "$p1" '{"hook_event_name":"Stop","session_id":"s1"}'
check "Stop in a background window marks it done" done "$(pane_state "$p1")"
check "done wins the tab" done "$(win_tab "$w1")"
hook "$p1" '{"hook_event_name":"PostToolUse","session_id":"s1"}'
check "PostToolUse re-arms running" running "$(pane_state "$p1")"
hook "$p1" '{"hook_event_name":"SessionStart","session_id":"s1"}'
check "SessionStart clears the pane" "" "$(pane_state "$p1")"
check "and the tab" "" "$(win_tab "$w1")"

# The active window: finishing is "nothing to see", so it clears.
hook "$p0" '{"hook_event_name":"UserPromptSubmit","session_id":"s0"}'
hook "$p0" '{"hook_event_name":"Stop","session_id":"s0"}'
check "Stop in the active window clears" "" "$(pane_state "$p0")"
hook "$p0" '{"hook_event_name":"Notification","notification_type":"idle_prompt","session_id":"s0"}'
check "idle_prompt settles like Stop" "" "$(pane_state "$p0")"

# agent-state for the other agents; waiting only counts in a background window.
TMUX_PANE="$p1" "$ROOT/bin/agent-state" waiting
check "agent-state waiting in a background window" waiting "$(pane_state "$p1")"
check "waiting wins the tab" waiting "$(win_tab "$w1")"
TMUX_PANE="$p0" "$ROOT/bin/agent-state" waiting
check "waiting in the active window is ignored" "" "$(pane_state "$p0")"
TMUX_PANE="$p1" "$ROOT/bin/agent-state" clear
check "agent-state clear" "" "$(pane_state "$p1")"
TMUX_PANE="$p1" "$ROOT/bin/agent-state" bogus
check "unknown states are ignored" "" "$(pane_state "$p1")"

# Inside herdr the hook does nothing.
printf '%s' '{"hook_event_name":"UserPromptSubmit"}' | HERDR_ENV=1 TMUX_PANE="$p1" "$ROOT/bin/claude-hook"
check "HERDR_ENV=1 leaves tmux alone" "" "$(pane_state "$p1")"

# The poller heals a running pane whose agent is gone (no agent process here).
echo '{"workers":{}}' > "$TMUX_AGENTS_ROSTER"
tmux set-option -p -t "$p1" @agent_state running
TMUX="$(tmux display -p '#{socket_path}'),0,0" "$ROOT/bin/agg" --poll >/dev/null
check "the poller clears a stale running pane" "" "$(pane_state "$p1")"

[ "$failures" -eq 0 ] && echo "all passed" || { echo "$failures failed"; exit 1; }
