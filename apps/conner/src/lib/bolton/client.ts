import type { ConnerStrategySummary, GeorgeNumbersSummary } from "@/lib/types";
import { GeorgeNumbersSummarySchema, ConnerStrategySummarySchema } from "@/lib/types";
import {
  MOCK_GEORGE_NUMBERS,
  MOCK_JAMES_MARKET_RESEARCH,
  MOCK_JAMES_PRICING_RESEARCH,
} from "@/lib/bolton/mock";

const BOLTON_BASE = process.env.BOLTON_API_URL ?? "http://localhost:3002";

async function boltonFetch(path: string, init?: RequestInit) {
  return fetch(`${BOLTON_BASE}${path}`, {
    ...init,
    // Fail fast if Bolton is hung rather than stalling the calling agent.
    signal: init?.signal ?? AbortSignal.timeout(5_000),
    headers: { "Content-Type": "application/json", ...init?.headers },
  });
}

export async function writeToBolton(candidate: {
  source_agent: string;
  entry_type: string;
  title: string;
  summary: string;
  full_content?: string;
  tags?: string[];
  importance_score?: number;
  cadence?: "once" | "daily" | "weekly" | "monthly" | "custom";
  custom_schedule?: string;
  force?: boolean;
}): Promise<{ id?: string } | null> {
  try {
    const res = await boltonFetch("/api/memory", {
      method: "POST",
      body: JSON.stringify({ ...candidate, force: candidate.force ?? true }),
    });
    if (res.ok) {
      const data = await res.json();
      return { id: data.id ?? data.entry?.id };
    }
  } catch {
    // non-blocking
  }
  return null;
}

export async function writeLatestStrategy(
  summary: ConnerStrategySummary
): Promise<{ id?: string } | null> {
  try {
    const res = await boltonFetch("/api/agent-summaries", {
      method: "POST",
      body: JSON.stringify({
        agent_id: "conner",
        summary,
        session_note: "Conner latest strategy update",
      }),
    });
    if (res.ok) {
      const data = await res.json();
      return { id: data.id };
    }
  } catch {
    // fallback
  }
  return null;
}

export async function getLatestAgentSummary(
  agentId: string
): Promise<Record<string, unknown> | null> {
  try {
    const res = await boltonFetch(`/api/agent-summaries?agent_id=${agentId}`);
    if (res.ok) {
      const data = await res.json();
      const summary = data.summary?.summary ?? data.summary;
      if (summary && typeof summary === "object") return summary as Record<string, unknown>;
    }
  } catch {
    // fallback
  }
  return null;
}

export async function getGeorgeNumbers(): Promise<{
  data: GeorgeNumbersSummary;
  from_mock: boolean;
}> {
  const raw = await getLatestAgentSummary("george");
  if (raw) {
    const parsed = GeorgeNumbersSummarySchema.safeParse(raw);
    if (parsed.success) return { data: parsed.data, from_mock: false };
  }

  try {
    const res = await boltonFetch("/api/context", {
      method: "POST",
      body: JSON.stringify({
        requesting_agent: "Conner",
        task: "Latest George finance summary - revenue, runway, burn rate, unit economics, flags",
      }),
    });
    if (res.ok) {
      const pack = await res.json();
      const memories = pack.context_pack?.relevant_memory ?? [];
      for (const mem of memories) {
        if (mem.full_content) {
          try {
            const parsed = GeorgeNumbersSummarySchema.safeParse(JSON.parse(mem.full_content));
            if (parsed.success) return { data: parsed.data, from_mock: false };
          } catch {
            // continue
          }
        }
      }
    }
  } catch {
    // fallback
  }

  return { data: MOCK_GEORGE_NUMBERS, from_mock: true };
}

export async function getJamesPricingResearch(): Promise<{
  data: Record<string, unknown>;
  from_mock: boolean;
}> {
  const raw = await searchJamesResearch("pricing competitive landscape unit economics");
  if (raw) return { data: raw, from_mock: false };
  return { data: MOCK_JAMES_PRICING_RESEARCH, from_mock: true };
}

export async function getJamesMarketResearch(): Promise<{
  data: Record<string, unknown>;
  from_mock: boolean;
}> {
  const raw = await searchJamesResearch("market landscape competitive positioning GTM");
  if (raw) return { data: raw, from_mock: false };
  return { data: MOCK_JAMES_MARKET_RESEARCH, from_mock: true };
}

async function searchJamesResearch(query: string): Promise<Record<string, unknown> | null> {
  try {
    const res = await boltonFetch("/api/search", {
      method: "POST",
      body: JSON.stringify({ query }),
    });
    if (!res.ok) return null;
    const data = await res.json();
    const results = (data.results ?? []) as Array<{
      source_agent: string;
      entry_type: string;
      full_content?: string;
      summary: string;
      title: string;
      tags?: string[];
    }>;
    const jamesHit = results.find(
      (r) =>
        r.source_agent?.toLowerCase() === "james" &&
        (r.entry_type === "research" || r.tags?.includes("research"))
    );
    if (!jamesHit) return null;
    if (jamesHit.full_content) {
      try {
        return JSON.parse(jamesHit.full_content) as Record<string, unknown>;
      } catch {
        return { title: jamesHit.title, summary: jamesHit.summary };
      }
    }
    return { title: jamesHit.title, summary: jamesHit.summary };
  } catch {
    return null;
  }
}

export async function getBoltonContext(task: string) {
  try {
    const res = await boltonFetch("/api/context", {
      method: "POST",
      body: JSON.stringify({ requesting_agent: "Conner", task }),
    });
    if (res.ok) return res.json();
  } catch {
    // fallback
  }
  return null;
}

export async function getAvailableAgentSummaries(): Promise<{
  george: GeorgeNumbersSummary | null;
  james: Record<string, unknown> | null;
  conner: ConnerStrategySummary | null;
  george_mock: boolean;
  james_mock: boolean;
}> {
  const georgeResult = await getGeorgeNumbers();
  const jamesResult = await getJamesMarketResearch();

  let conner: ConnerStrategySummary | null = null;
  const connerRaw = await getLatestAgentSummary("conner");
  if (connerRaw) {
    const parsed = ConnerStrategySummarySchema.safeParse(connerRaw);
    if (parsed.success) conner = parsed.data;
  }

  return {
    george: georgeResult.data,
    james: jamesResult.data,
    conner,
    george_mock: georgeResult.from_mock,
    james_mock: jamesResult.from_mock,
  };
}

export async function persistStrategyToBolton(
  summary: ConnerStrategySummary
): Promise<string[]> {
  const ids: string[] = [];

  const agentWrite = await writeLatestStrategy(summary);
  if (agentWrite?.id) ids.push(agentWrite.id);

  const memoryWrite = await writeToBolton({
    source_agent: "Conner",
    entry_type: "other",
    title: `Latest strategy - ${summary.as_of}`,
    summary: `${summary.positioning_update.slice(0, 120)}… · segment: ${summary.target_segment.slice(0, 80)}`,
    full_content: JSON.stringify(summary, null, 2),
    tags: [
      "conner",
      "strategy",
      "positioning_update",
      "target_segment",
      "latest_strategy",
    ],
    force: true,
  });
  if (memoryWrite?.id) ids.push(memoryWrite.id);

  return ids;
}
