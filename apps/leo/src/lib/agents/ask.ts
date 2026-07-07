import { invokeAgent } from "@/lib/agents/invoke";
import { synthesizeWithClaude } from "@/lib/claude";
import { getBoltonContext } from "@/lib/bolton/client";
import type { AgentInvokeResponse } from "@/lib/types";

const AGENTS = [
  "leo",
  "marc",
  "william",
  "bolton",
  "johnny",
  "robert",
  "james",
  "george",
  "conner",
  "harris",
  "cole",
] as const;

export interface AskLeoResult {
  mode: "direct" | "routed";
  summary: string;
  routed_to?: string;
  invoke?: AgentInvokeResponse;
}

function extractJson<T>(text: string): T | null {
  try {
    const match = text.match(/\{[\s\S]*\}/);
    if (match) return JSON.parse(match[0]) as T;
  } catch {
    // fall through
  }
  return null;
}

export async function askLeo(query: string): Promise<AskLeoResult> {
  const bolton = await getBoltonContext(query, "Leo");
  const contextSnippet = bolton?.context_pack
    ? JSON.stringify(bolton.context_pack).slice(0, 4000)
    : "";

  const routingRaw = await synthesizeWithClaude(
    `You are Leo, chief of staff for LiamOS/11am. Classify the user's request.
Available agents: ${AGENTS.join(", ")}.
Return ONLY JSON:
{
  "mode": "direct" | "route",
  "to_agent": "agent id lowercase or null if direct",
  "priority": "normal" | "urgent",
  "reason": "one short sentence"
}
Route to a specialist when the task clearly belongs to them (inbox→marc, writing→william, build→johnny, design→robert, research→james, finance→george, strategy→conner, learning→harris, video→cole, memory→bolton).
Answer directly (mode direct) for planning, prioritisation, calendar questions, or vague multi-domain asks you can handle as chief of staff.`,
    `User query: ${query}\n\nBolton context (snippet):\n${contextSnippet}`
  );

  const routing = extractJson<{
    mode: "direct" | "route";
    to_agent?: string | null;
    priority?: "normal" | "urgent";
    reason?: string;
  }>(routingRaw);

  const mode = routing?.mode === "route" && routing.to_agent ? "route" : "direct";
  const toAgent = routing?.to_agent?.toLowerCase();

  if (mode === "route" && toAgent && AGENTS.includes(toAgent as (typeof AGENTS)[number]) && toAgent !== "leo") {
    const invoke = await invokeAgent({
      from_agent: "Liam",
      to_agent: toAgent,
      task: query,
      priority: routing?.priority ?? "normal",
      response_mode: "sync",
    });
    return {
      mode: "routed",
      summary: invoke.summary,
      routed_to: toAgent,
      invoke,
    };
  }

  const direct = await synthesizeWithClaude(
    "You are Leo, chief of staff for LiamOS. Answer Liam directly in 2-4 sentences. Calm, practical, lowercase tone in spirit but use normal sentence case. No corporate filler.",
    `Query: ${query}\n\nBolton context:\n${contextSnippet}`
  );

  return { mode: "direct", summary: direct.trim() };
}
