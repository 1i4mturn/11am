import { getBoltonContext, writeToBolton } from "@/lib/bolton/client";
import { synthesizeWithClaude } from "@/lib/claude";
import type { AgentInvokeRequest, AgentInvokeResponse } from "@/lib/types";

const JAMES_API = process.env.JAMES_API_URL ?? "http://localhost:3003";
const CONNER_API = process.env.CONNER_API_URL ?? "http://localhost:3005";
const ROBERT_API = process.env.ROBERT_API_URL ?? "http://localhost:3007";
const HARRIS_API = process.env.HARRIS_API_URL ?? "http://localhost:3008";
const COLE_API = process.env.COLE_API_URL ?? "http://localhost:3009";
const JOHNNY_API = process.env.JOHNNY_API_URL ?? "http://localhost:3011";

async function invokeJamesHandoff(
  request: AgentInvokeRequest
): Promise<AgentInvokeResponse> {
  const res = await fetch(`${JAMES_API}/api/handoff`, {
    signal: AbortSignal.timeout(90_000),
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      from_agent: request.from_agent,
      to_agent: request.from_agent,
      research_question: request.task,
      context_ref: request.context_ref,
      priority: request.priority,
    }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error ?? "James handoff failed");
  }

  const handoff = await res.json();
  return {
    from_agent: "james",
    to_agent: request.from_agent,
    summary: handoff.recommendation ?? handoff.what_this_means ?? "Research complete",
    structured_result: handoff,
    memory_ids_written: handoff.memory_id ? [handoff.memory_id] : [],
    follow_up_needed: request.priority === "urgent",
  };
}

async function invokeConnerHandoff(
  request: AgentInvokeRequest
): Promise<AgentInvokeResponse> {
  const res = await fetch(`${CONNER_API}/api/handoff`, {
    signal: AbortSignal.timeout(90_000),
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      from_agent: request.from_agent,
      to_agent: request.from_agent,
      task: request.task,
      context_ref: request.context_ref,
      priority: request.priority,
    }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error ?? "Conner handoff failed");
  }

  const handoff = await res.json();
  return {
    from_agent: "conner",
    to_agent: request.from_agent,
    summary: handoff.summary ?? "Strategy session complete",
    structured_result: handoff.structured_result,
    memory_ids_written: handoff.memory_ids_written ?? [],
    follow_up_needed: request.priority === "urgent",
  };
}

async function invokeRobertHandoff(
  request: AgentInvokeRequest
): Promise<AgentInvokeResponse> {
  const res = await fetch(`${ROBERT_API}/api/handoff`, {
    signal: AbortSignal.timeout(90_000),
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      from_agent: request.from_agent,
      to_agent: request.from_agent,
      task: request.task,
      context_ref: request.context_ref,
      priority: request.priority,
    }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error ?? "Robert handoff failed");
  }

  const handoff = await res.json();
  return {
    from_agent: "robert",
    to_agent: request.from_agent,
    summary: handoff.summary ?? "Design direction complete",
    structured_result: handoff.structured_result,
    memory_ids_written: handoff.memory_ids_written ?? [],
    follow_up_needed: request.priority === "urgent",
  };
}

async function invokeHarrisHandoff(
  request: AgentInvokeRequest
): Promise<AgentInvokeResponse> {
  const res = await fetch(`${HARRIS_API}/api/handoff`, {
    signal: AbortSignal.timeout(90_000),
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      from_agent: request.from_agent,
      task: request.task,
      priority: request.priority,
    }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error ?? "Harris handoff failed");
  }

  const handoff = await res.json();
  return {
    from_agent: "harris",
    to_agent: request.from_agent,
    summary: handoff.summary ?? "Learning plan created",
    structured_result: handoff,
    memory_ids_written: handoff.memory_ids_written ?? [],
    follow_up_needed: request.priority === "urgent",
  };
}

async function invokeColeHandoff(
  request: AgentInvokeRequest
): Promise<AgentInvokeResponse> {
  const res = await fetch(`${COLE_API}/api/handoff`, {
    signal: AbortSignal.timeout(90_000),
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      from_agent: request.from_agent,
      task: request.task,
      priority: request.priority,
    }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error ?? "Cole handoff failed");
  }

  const handoff = await res.json();
  return {
    from_agent: "cole",
    to_agent: request.from_agent,
    summary: handoff.summary ?? "Motion brief complete",
    structured_result: handoff,
    memory_ids_written: handoff.memory_ids_written ?? [],
    follow_up_needed: request.priority === "urgent",
  };
}

async function invokeJohnnyHandoff(
  request: AgentInvokeRequest
): Promise<AgentInvokeResponse> {
  const res = await fetch(`${JOHNNY_API}/api/handoff`, {
    signal: AbortSignal.timeout(90_000),
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      from_agent: request.from_agent,
      task: request.task,
      priority: request.priority,
    }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.error ?? "Johnny handoff failed");
  }

  const handoff = await res.json();
  return {
    from_agent: "johnny",
    to_agent: request.from_agent,
    summary: handoff.summary ?? "Code review complete",
    structured_result: handoff,
    memory_ids_written: handoff.memory_ids_written ?? [],
    follow_up_needed: request.priority === "urgent",
  };
}

const AGENT_PROMPTS: Record<string, string> = {
  james:
    "You are James, the research agent for LiamOS/11am. Ground answers in evidence, cite sources when possible, compare options clearly, and flag confidence levels. Return concise research briefs.",
  george:
    "You are George, the finance agent. Focus on revenue, margins, runway, burn, and financial flags. Be precise with numbers and conservative with projections.",
  conner:
    "You are Conner, the business-building agent. Focus on positioning, offers, go-to-market, and strategic decisions. Be direct and commercially minded.",
  william:
    "You are William, the writing agent. Draft copy in Liam's voice — warm, clear, conversational, no corporate filler.",
  marc: "You are Marc, the inbox agent. Triage communication, draft replies, and flag urgency based on sender context.",
  bolton:
    "You are Bolton, the memory archivist. Summarize what should be stored, linked, or superseded in shared memory.",
  robert:
    "You are Robert, the design agent. Give visual direction using brand tokens — no invented palettes.",
  johnny:
    "You are Johnny, the build agent. Provide technical architecture and implementation guidance.",
  harris: "You are Harris, the learning agent. Explain concepts clearly and suggest practice steps.",
  cole: "You are Cole, the video agent. Structure concepts for reels, YouTube, and short-form video.",
  leo: "You are Leo, chief of staff. Coordinate priorities, calendar, and agent handoffs for Liam.",
};

/**
 * Parallel fan-out — brief several agents at once with the same task.
 * Each invocation is independent and failure-isolated: one agent being down
 * returns an error response for that agent without sinking the others.
 */
export async function invokeAgentsParallel(
  base: Omit<AgentInvokeRequest, "to_agent">,
  toAgents: string[]
): Promise<AgentInvokeResponse[]> {
  const settled = await Promise.allSettled(
    toAgents.map((to_agent) => invokeAgent({ ...base, to_agent }))
  );

  return settled.map((result, i) =>
    result.status === "fulfilled"
      ? result.value
      : {
          from_agent: toAgents[i],
          to_agent: base.from_agent,
          summary: `${toAgents[i]} unavailable: ${
            result.reason instanceof Error ? result.reason.message : "invocation failed"
          }`,
          memory_ids_written: [],
          follow_up_needed: true,
        }
  );
}

export async function invokeAgent(
  request: AgentInvokeRequest
): Promise<AgentInvokeResponse> {
  if (request.response_mode === "async") {
    return {
      from_agent: request.to_agent,
      to_agent: request.from_agent,
      summary: "Async routing not yet supported in v1 — use response_mode: sync",
      memory_ids_written: [],
      follow_up_needed: true,
    };
  }

  const agentKey = request.to_agent.toLowerCase();

  if (agentKey === "james") {
    return invokeJamesHandoff(request);
  }

  if (agentKey === "conner") {
    return invokeConnerHandoff(request);
  }

  if (agentKey === "robert") {
    return invokeRobertHandoff(request);
  }

  if (agentKey === "harris") {
    return invokeHarrisHandoff(request);
  }

  if (agentKey === "cole") {
    return invokeColeHandoff(request);
  }

  if (agentKey === "johnny") {
    return invokeJohnnyHandoff(request);
  }

  const system =
    AGENT_PROMPTS[agentKey] ??
    `You are ${request.to_agent}, an agent in the LiamOS/11am suite. Complete the assigned task concisely.`;

  const contextTask = request.context_ref
    ? `${request.task}\n\nContext reference: ${request.context_ref}`
    : request.task;

  const boltonPack = await getBoltonContext(contextTask, request.to_agent);
  const contextBlock = boltonPack?.context_pack
    ? `\n\nBolton context pack:\n${JSON.stringify(boltonPack.context_pack, null, 2)}`
    : "";

  const urgency =
    request.priority === "urgent"
      ? "This is URGENT — prioritize speed and flag blockers."
      : "";

  const result = await synthesizeWithClaude(
    system,
    `${urgency}\n\nTask from ${request.from_agent}:\n${request.task}${contextBlock}\n\nRespond with:\n1. A short executive summary (2-3 sentences)\n2. A JSON block labeled STRUCTURED_RESULT with key findings as an object`
  );

  const structuredMatch = result.match(/STRUCTURED_RESULT[\s\S]*?(\{[\s\S]*?\})/);
  let structured_result: Record<string, unknown> | undefined;
  if (structuredMatch) {
    try {
      structured_result = JSON.parse(structuredMatch[1]);
    } catch {
      structured_result = { raw: result };
    }
  }

  const summary = result.split("STRUCTURED_RESULT")[0].trim().slice(0, 2000);

  const memoryWrite = await writeToBolton({
    source_agent: request.to_agent.charAt(0).toUpperCase() + request.to_agent.slice(1),
    entry_type: agentKey === "james" ? "research" : "other",
    title: `Routed from ${request.from_agent}: ${request.task.slice(0, 80)}`,
    summary: summary.slice(0, 500) || request.task.slice(0, 500),
    full_content: result,
    tags: ["agent_invoke", request.from_agent.toLowerCase(), agentKey],
    force: true,
  });

  return {
    from_agent: request.to_agent,
    to_agent: request.from_agent,
    summary,
    structured_result,
    memory_ids_written: memoryWrite?.id ? [memoryWrite.id] : [],
    follow_up_needed: request.priority === "urgent",
  };
}
