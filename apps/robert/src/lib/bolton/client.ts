import type { BrandSystemDoc } from "@/lib/types";
import { BrandSystemDocSchema } from "@/lib/types";
import { MOCK_BRAND_SYSTEM, MOCK_CONNER_STRATEGY, MOCK_JAMES_VISUAL_RESEARCH } from "@/lib/bolton/mock";

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

export async function writeBrandSystemDoc(
  doc: BrandSystemDoc
): Promise<{ id?: string } | null> {
  try {
    const res = await boltonFetch("/api/agent-summaries", {
      method: "POST",
      body: JSON.stringify({
        agent_id: "robert",
        summary: doc,
        session_note: `Brand system ${doc.version}`,
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

export async function persistBrandSystem(doc: BrandSystemDoc): Promise<string[]> {
  const ids: string[] = [];
  const agentWrite = await writeBrandSystemDoc(doc);
  if (agentWrite?.id) ids.push(agentWrite.id);

  const memoryWrite = await writeToBolton({
    source_agent: "Robert",
    entry_type: "reference",
    title: `Living brand system - ${doc.version}`,
    summary: `Brand system v${doc.version} · ${Object.keys(doc.color_tokens).length} colours · ${doc.do_dont_rules.length} rules`,
    full_content: JSON.stringify(doc, null, 2),
    tags: ["brand", "design", "brand_system", "motion_tokens", `version:${doc.version}`],
    importance_score: 0.9,
    force: true,
  });
  if (memoryWrite?.id) ids.push(memoryWrite.id);
  return ids;
}

export async function getBrandSystemFromBolton(): Promise<{
  doc: BrandSystemDoc;
  from_mock: boolean;
}> {
  try {
    const res = await boltonFetch("/api/agent-summaries?agent_id=robert");
    if (res.ok) {
      const data = await res.json();
      const raw = data.summary?.summary ?? data.summary;
      const parsed = BrandSystemDocSchema.safeParse(raw);
      if (parsed.success) return { doc: parsed.data, from_mock: false };
    }
  } catch {
    // fallback
  }

  try {
    const res = await boltonFetch("/api/search", {
      method: "POST",
      body: JSON.stringify({ query: "living brand system Robert motion_tokens" }),
    });
    if (res.ok) {
      const data = await res.json();
      for (const hit of data.results ?? []) {
        if (!hit.full_content) continue;
        try {
          const parsed = BrandSystemDocSchema.safeParse(JSON.parse(hit.full_content));
          if (parsed.success) return { doc: parsed.data, from_mock: false };
        } catch {
          // continue
        }
      }
    }
  } catch {
    // fallback
  }

  return { doc: MOCK_BRAND_SYSTEM, from_mock: true };
}

export async function getConnerContext(): Promise<{
  data: Record<string, unknown>;
  from_mock: boolean;
}> {
  try {
    const res = await boltonFetch("/api/agent-summaries?agent_id=conner");
    if (res.ok) {
      const data = await res.json();
      const raw = data.summary?.summary ?? data.summary;
      if (raw && typeof raw === "object") {
        return { data: raw as Record<string, unknown>, from_mock: false };
      }
    }
  } catch {
    // fallback
  }

  try {
    const res = await boltonFetch("/api/context", {
      method: "POST",
      body: JSON.stringify({
        requesting_agent: "Robert",
        task: "Latest Conner strategy summary - positioning, decisions, target segment",
      }),
    });
    if (res.ok) {
      const pack = await res.json();
      const memories = pack.context_pack?.relevant_memory ?? [];
      for (const mem of memories) {
        if (mem.full_content) {
          try {
            return { data: JSON.parse(mem.full_content), from_mock: false };
          } catch {
            // continue
          }
        }
      }
    }
  } catch {
    // fallback
  }

  return { data: MOCK_CONNER_STRATEGY, from_mock: true };
}

export async function getJamesVisualResearch(): Promise<{
  data: Record<string, unknown>;
  from_mock: boolean;
}> {
  try {
    const res = await boltonFetch("/api/search", {
      method: "POST",
      body: JSON.stringify({
        query: "James competitor visual landscape trend research design",
      }),
    });
    if (res.ok) {
      const data = await res.json();
      const hit = (data.results ?? []).find(
        (r: { source_agent?: string }) => r.source_agent?.toLowerCase() === "james"
      );
      if (hit?.full_content) {
        try {
          return { data: JSON.parse(hit.full_content), from_mock: false };
        } catch {
          return {
            data: { title: hit.title, summary: hit.summary },
            from_mock: false,
          };
        }
      }
    }
  } catch {
    // fallback
  }

  return { data: MOCK_JAMES_VISUAL_RESEARCH, from_mock: true };
}

export async function writeImplementationBrief(
  brief: Record<string, unknown>
): Promise<{ id?: string } | null> {
  const target = String(brief.target_agent ?? "johnny");
  return writeToBolton({
    source_agent: "Robert",
    entry_type: "reference",
    title: `Design brief → ${target}: ${String(brief.project ?? "Untitled").slice(0, 60)}`,
    summary: String(brief.objective ?? brief.summary ?? "").slice(0, 500),
    full_content: JSON.stringify(brief, null, 2),
    tags: ["design_brief", target, "handoff", "robert"],
    importance_score: 0.85,
    force: true,
  });
}

export async function getBoltonContext(task: string) {
  try {
    const res = await boltonFetch("/api/context", {
      method: "POST",
      body: JSON.stringify({ requesting_agent: "Robert", task }),
    });
    if (res.ok) return res.json();
  } catch {
    // fallback
  }
  return null;
}
