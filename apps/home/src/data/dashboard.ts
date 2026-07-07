import type { AgentId } from "./agents";

/** Grayscale roster status — July 6 spec */
export type BuildStatus = "live" | "build" | "urgent";

export interface GlanceRow {
  who?: string;
  text: string;
  tag?: "urgent" | "ready" | "info";
}

export interface GlanceCard {
  kicker: string;
  agentId: AgentId;
  rows: GlanceRow[];
}

export interface ActivityEntry {
  agentId: AgentId;
  time: string;
  text: string;
}

export interface AgentBuildStatusEntry {
  agentId: AgentId;
  build_status: BuildStatus;
}

/** Sidebar grid order from v13 mockup */
export const SIDEBAR_ORDER: AgentId[] = [
  "marc",
  "william",
  "bolton",
  "leo",
  "johnny",
  "robert",
  "james",
  "george",
  "conner",
  "harris",
  "cole",
];

/**
 * Manual build_status per agent — update as each agent's Definition of Done completes.
 * Cross-check against Full Suite Build Plan (no automated sync in v1).
 */
export const AGENT_BUILD_STATUS: AgentBuildStatusEntry[] = [
  { agentId: "marc", build_status: "live" },
  { agentId: "william", build_status: "live" },
  { agentId: "bolton", build_status: "live" },
  { agentId: "leo", build_status: "live" },
  { agentId: "johnny", build_status: "live" },
  { agentId: "robert", build_status: "live" },
  { agentId: "conner", build_status: "live" },
  { agentId: "harris", build_status: "live" },
  { agentId: "cole", build_status: "live" },
  { agentId: "james", build_status: "build" },
  { agentId: "george", build_status: "build" },
];
