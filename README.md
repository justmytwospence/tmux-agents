# tmux-agents

Coding-agent state on tmux window tabs, and desktop notifications for agents
running outside [herdr](https://herdr.dev).

- Each agent pane publishes its state (`running`, `waiting`, `done`) and every
  window tab shows the most urgent one: **waiting** red > **done** yellow >
  **running** green, with a count when several agents share it. `done` only
  shows in a background window, and focusing the pane dismisses it.
- Claude Code background agents (fleet and slash jobs) that belong to no window
  show as a badge in `status-right`, and a finished fleet agent sends a desktop
  notification.
- Claude Code prompts that need you (permissions, questions, a ready plan) send a
  desktop notification: `terminal-notifier` on macOS, and over SSH a reverse
  tunnel back to the Mac, else an OSC 777 escape.
- Inside herdr (`HERDR_ENV=1`) everything stays quiet: herdr tracks agents
  itself.

Requires tmux, `jq`, and on macOS `terminal-notifier` for notifications.

## Install

```tmux
# ~/.tmux.conf
set -g status-interval 5
run-shell /path/to/tmux-agents/tmux-agents.tmux
```

TPM works too (`set -g @plugin 'justmytwospence/tmux-agents'`). Options, set
before loading:

| option | default | |
|---|---|---|
| `@agents-formats` | `on` | `off` leaves `window-status-format`, `window-status-current-format` and `status-right` to you. Render `#{@agent_tab}`, `#{@agent_n}` and `#{E:@agent_badge}`. |
| `@agents-current-bg` | `blue` | background the current-window tab returns to after its state block |
| `@agent_notify` | | `off` silences background-agent notifications |

## Wire up the agents

Each agent reports through its own lifecycle hooks.

**Claude Code** (`~/.claude/settings.json`): run `bin/claude-hook` on
`UserPromptSubmit`, `PostToolUse`, `SessionStart`, `Stop`, `Notification` and
`PreToolUse`:

```json
{ "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "bash /path/to/tmux-agents/bin/claude-hook" } ] } ] } }
```

**Codex** (`~/.codex/hooks.json`): `bin/agent-state running` on
`UserPromptSubmit` and `PostToolUse`, `done` on `Stop`, `clear` on
`SessionStart` and `SessionEnd`.

**pi**: add this checkout to `packages` in `~/.pi/agent/settings.json`; the
extension is `integrations/pi/tmux-agents.ts`.

**opencode**: link `integrations/opencode/tmux-agents.js` into
`~/.config/opencode/plugins/`.

Anything else can call `bin/agent-state <running|waiting|done|clear>` from
inside its pane.

## Remote notifications

Agents on another host over SSH can notify the Mac you are sitting at. On the
Mac, a launchd agent runs `bin/notify-recv` for each connection to a unix socket:

```xml
<key>ProgramArguments</key><array><string>/path/to/tmux-agents/bin/notify-recv</string></array>
<key>Sockets</key><dict><key>Listener</key><dict>
  <key>SockPathName</key><string>/Users/you/.local/state/claude-notify.sock</string>
  <key>SockPathMode</key><integer>384</integer></dict></dict>
<key>inetdCompatibility</key><dict><key>Wait</key><false/></dict>
```

and `~/.ssh/config` forwards the remote port to it:

```
RemoteForward 7877 /Users/you/.local/state/claude-notify.sock
```

`bin/claude-hook` on the remote host writes one JSON line to
`127.0.0.1:7877` (override with `CLAUDE_NOTIFY_PORT`). The payload is data only;
`notify-recv` never executes it.

## Tests

```sh
tests/run.sh    # a private tmux server; needs tmux and jq
```

## License

MIT
