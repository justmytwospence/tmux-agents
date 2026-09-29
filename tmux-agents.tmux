#!/usr/bin/env bash
# tmux-agents -- coding-agent state on tmux window tabs.
#
# Load from ~/.tmux.conf with `run-shell /path/to/tmux-agents/tmux-agents.tmux`
# (or TPM's `set -g @plugin`). Re-running it on a config reload is safe.
#
# Options (set before loading):
#   @agents-formats      on (default) | off   -- off leaves window-status-format,
#                        window-status-current-format and status-right to you;
#                        use #{@agent_tab}, #{@agent_n} and #{E:@agent_badge}.
#   @agents-current-bg   background of the current-window tab (default blue),
#                        restored after its state block.
set -u

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
opt() { local v; v=$(tmux show-option -gqv "$1" 2>/dev/null); printf '%s' "${v:-$2}"; }

if [ "$(opt @agents-formats on)" != off ]; then
    bg=$(opt @agents-current-bg blue)
    # waiting red > done yellow > running green; " (N)" when several agents share it.
    block() { # block <restore>: a one-cell state marker, then restore the tab style
        printf '#{?#{==:#{@agent_tab},waiting},#[bg=red fg=#fbf3db bold nodim] %s,#{?#{==:#{@agent_tab},done},#[bg=yellow fg=black bold nodim] %s,#{?#{==:#{@agent_tab},running},#[bg=green fg=black bold nodim] %s, }}}' "$1" "$1" "$1"
    }
    count='#{?#{>:#{@agent_n},1}, (#{@agent_n}),}'
    # The current window renders through its own format, so it needs its own
    # marker, or an agent waiting in another pane of this window is invisible.
    tmux set-option -g window-status-current-format "$(block "#[bg=$bg fg=black nobold]")#I:#W$count "
    tmux set-option -g window-status-format "$(block "")#I:#W$count "
    # Detached background agents (Claude fleet/slash jobs) not bound to a window.
    case "$(tmux show-option -gqv status-right)" in
        *@agent_badge*) ;;
        *) tmux set-option -ga status-right '#{E:@agent_badge}' ;;
    esac
fi

# Seeing a finished agent's pane dismisses its "done"; "waiting" stays until it
# works again.
tmux set-hook -g pane-focus-in 'if-shell -F "#{==:#{@agent_state},done}" "set-option -pu @agent_state"'

# The poller runs in its own loop, not a #() in status-right: tmux only expands
# status formats for attached clients, so a #() stops the moment the last client
# detaches, taking the stale-state self-heal and background-agent notifications
# with it. Single instance per server, so a reload is a no-op.
tmux run-shell -b "'$DIR/bin/agg' --daemon"
