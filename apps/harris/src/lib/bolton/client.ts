import { LEARNING_HUB_TITLE } from "@/lib/config";
import type { LearningHub } from "@/lib/types";
import { SkillGapSignalSchema } from "@/lib/types";
import { MOCK_SKILL_GAPS } from "@/lib/bolton/mock";

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

/** Short pointer only - full plan detail stays in Learning Hub */
export async function writePlanPointer(hub: LearningHub): Promise<{ id?: string } | null> {
  const active = hub.plans.filter((p) => p.progress.status === "active");
  const summary = `${active.length} active plan(s) · ${hub.plans.length} total · updated ${hub.updated_at.slice(0, 10)}`;

  return writeToBolton({
    source_agent: "Harris",
    entry_type: "reference",
    title: "Harris learning plan active",
    summary,
    tags: ["harris", "learning", "plan_pointer"],
    force: true,
  });
}

export async function loadLearningHubFromBolton(): Promise<{
  hub: LearningHub | null;
  entry_id?: string;
}> {
  try {
    const res = await boltonFetch(
      `/api/memory?source_agent=Harris&entry_type=reference&status=active`
    );
    if (!res.ok) return { hub: null };

    const data = await res.json();
    const entries = (data.entries ?? []) as Array<{
      id: string;
      title: string;
      full_content?: string;
    }>;

    const hubEntry = entries.find((e) => e.title === LEARNING_HUB_TITLE);
    if (!hubEntry?.full_content) return { hub: null };

    const hub = JSON.parse(hubEntry.full_content) as LearningHub;
    return { hub, entry_id: hubEntry.id };
  } catch {
    return { hub: null };
  }
}

export async function saveLearningHubToBolton(
  hub: LearningHub,
  existingEntryId?: string
): Promise<{ id?: string } | null> {
  const summary = `Learning Hub · ${hub.plans.length} plan(s) · ${hub.plans.filter((p) => p.progress.status === "active").length} active`;

  if (existingEntryId || hub.bolton_entry_id) {
    try {
      const res = await boltonFetch("/api/memory", {
        method: "PATCH",
        body: JSON.stringify({
          id: existingEntryId ?? hub.bolton_entry_id,
          summary,
          full_content: JSON.stringify(hub, null, 2),
        }),
      });
      if (res.ok) return { id: existingEntryId ?? hub.bolton_entry_id };
    } catch {
      // fall through to create
    }
  }

  const created = await writeToBolton({
    source_agent: "Harris",
    entry_type: "reference",
    title: LEARNING_HUB_TITLE,
    summary,
    full_content: JSON.stringify(hub, null, 2),
    tags: ["harris", "learning_hub", "reference"],
    importance_score: 0.85,
    force: true,
  });

  await writePlanPointer(hub);
  return created;
}

export async function getSkillGapSignals(): Promise<{
  gaps: Array<import("@/lib/types").SkillGapSignal>;
  from_mock: boolean;
}> {
  const gaps: import("@/lib/types").SkillGapSignal[] = [];

  try {
    const res = await boltonFetch("/api/search", {
      method: "POST",
      body: JSON.stringify({ query: "skill gap suggested_for Harris priority evidence" }),
    });
    if (res.ok) {
      const data = await res.json();
      for (const hit of (data.results ?? []) as Array<{
        source_agent?: string;
        title?: string;
        summary?: string;
        full_content?: string;
        tags?: string[];
      }>) {
        if (!hit.full_content) continue;
        try {
          const parsed = SkillGapSignalSchema.safeParse(JSON.parse(hit.full_content));
          if (parsed.success) gaps.push(parsed.data);
        } catch {
          // try tags
          if (hit.tags?.includes?.("skill_gap")) {
            const loose = SkillGapSignalSchema.safeParse({
              source_agent: hit.source_agent ?? "unknown",
              skill_gap: hit.title,
              evidence: hit.summary,
              suggested_for: "Harris",
              priority: "medium",
            });
            if (loose.success) gaps.push(loose.data);
          }
        }
      }
    }
  } catch {
    // fallback
  }

  if (gaps.length > 0) return { gaps, from_mock: false };
  return { gaps: MOCK_SKILL_GAPS, from_mock: true };
}

export async function getBoltonContext(task: string) {
  try {
    const res = await boltonFetch("/api/context", {
      method: "POST",
      body: JSON.stringify({ requesting_agent: "Harris", task }),
    });
    if (res.ok) return res.json();
  } catch {
    // fallback
  }
  return null;
}
