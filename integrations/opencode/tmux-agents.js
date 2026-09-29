// opencode plugin: publish this pane's agent state for tmux-agents' window tabs.
// Link it into ~/.config/opencode/plugins/ (opencode loads that directory).
import { execFile } from "node:child_process";
import { realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// Resolve through the symlink in ~/.config/opencode/plugins to this checkout.
const AGENT_STATE = join(dirname(realpathSync(fileURLToPath(import.meta.url))), "../../bin/agent-state");

// opencode's events in the tabs' vocabulary; null leaves the tab alone.
function classify(event) {
  switch (event?.type) {
    case "permission.updated":
      return "waiting";
    case "permission.replied":
      return "running";
    case "session.idle":
      return "done";
    // The authoritative busy/idle signal, which also catches a turn that ended
    // without a session.idle (interrupted, or failed).
    case "session.status":
      return event.properties?.status?.type === "idle" ? "done" : "running";
    case "session.created":
      return "clear";
    default:
      return null;
  }
}

export default async () => {
  let last = null;
  return {
    event: async ({ event }) => {
      if (!process.env.TMUX) return;
      const state = classify(event);
      // opencode emits events continuously; fork only when the state changes.
      if (!state || state === last) return;
      last = state;
      execFile(AGENT_STATE, [state], { timeout: 4000 }, () => undefined);
    },
  };
};
