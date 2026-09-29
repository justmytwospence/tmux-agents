// pi extension: publish this pane's agent state for tmux-agents' window tabs.
// Loaded through the package.json at the repository root (pi.extensions).
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const AGENT_STATE = fileURLToPath(new URL("../../bin/agent-state", import.meta.url));

export default function tmuxAgents(pi: ExtensionAPI) {
  // Outside tmux (herdr, a plain terminal) there is no tab to paint.
  if (!process.env.TMUX) return;
  let last: string | undefined;
  const set = (state: "running" | "waiting" | "done" | "clear") => {
    if (state === last) return;
    last = state;
    // Fire and forget: a status indicator must never slow or fail the agent.
    execFile(AGENT_STATE, [state], { timeout: 4_000 }, () => undefined);
  };
  pi.on("session_start", () => set("clear"));
  pi.on("turn_start", () => set("running"));
  pi.on("agent_settled", () => set("done"));
  pi.on("ui_prompt_start", () => set("waiting"));
  pi.on("ui_prompt_end", (_event, ctx) => set(ctx.isIdle() ? "done" : "running"));
}
