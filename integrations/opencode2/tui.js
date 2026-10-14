// OpenCode 2 terminal plugin: publish this pane's agent state for tmux-agents' window tabs.
// Link this directory into ~/.config/opencode/plugins/ (OpenCode loads <dir>/tui.js there).
// It runs in the terminal process, so TMUX is the pane's own.
import { execFile } from "node:child_process";
import { realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const AGENT_STATE = join(dirname(realpathSync(fileURLToPath(import.meta.url))), "../../bin/agent-state");

export default {
  id: "tmux-agents.tui",
  setup(context) {
    if (!process.env.TMUX) return;
    let last = null;
    const shown = () => {
      const route = context.ui.router.current();
      return route.type === "session" ? context.data.session.root(route.sessionID) : undefined;
    };
    const set = (state, sessionID) => {
      const root = shown();
      if (sessionID && root && context.data.session.root(sessionID) !== root) return;
      if (state === last) return;
      last = state;
      execFile(AGENT_STATE, [state], { timeout: 4000 }, () => undefined);
    };
    const id = (e) => e?.data?.sessionID;
    const offs = [
      context.data.on("permission.asked", (e) => set("waiting", id(e))),
      context.data.on("permission.replied", (e) => set("running", id(e))),
      context.data.on("session.execution.started", (e) => set("running", id(e))),
      context.data.on("session.execution.succeeded", (e) => set("done", id(e))),
      context.data.on("session.execution.failed", (e) => set("done", id(e))),
      context.data.on("session.execution.interrupted", (e) => set("done", id(e))),
      context.data.on("session.created", (e) => { if (!e?.data?.info?.parentID) set("clear"); }),
    ];
    return () => offs.forEach((off) => off());
  },
};
