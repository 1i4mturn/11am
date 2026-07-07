import type { BrandContext, BrandSystemDoc } from "@/lib/types";
import { BrandSystemDocSchema, MotionTokensSchema } from "@/lib/types";
import { MOCK_BRAND_SYSTEM } from "@/lib/bolton/mock";

const BOLTON_BASE = process.env.BOLTON_API_URL ?? "http://localhost:3002";

async function boltonFetch(path: string, init?: RequestInit) {
  return fetch(`${BOLTON_BASE}${path}`, {
    ...init,
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

function motionTokensReady(doc: BrandSystemDoc): boolean {
  return MotionTokensSchema.safeParse(doc.motion_tokens).success;
}

export async function getBrandContext(): Promise<BrandContext> {
  try {
    const res = await boltonFetch("/api/agent-summaries?agent_id=robert");
    if (res.ok) {
      const data = await res.json();
      const raw = data.summary?.summary ?? data.summary;
      const parsed = BrandSystemDocSchema.safeParse(raw);
      if (parsed.success) {
        return {
          doc: parsed.data,
          from_mock: false,
          motion_tokens_ready: motionTokensReady(parsed.data),
        };
      }
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
      for (const hit of (data.results ?? []) as Array<{ full_content?: string }>) {
        if (!hit.full_content) continue;
        try {
          const parsed = BrandSystemDocSchema.safeParse(JSON.parse(hit.full_content));
          if (parsed.success) {
            return {
              doc: parsed.data,
              from_mock: false,
              motion_tokens_ready: motionTokensReady(parsed.data),
            };
          }
        } catch {
          // continue
        }
      }
    }
  } catch {
    // fallback
  }

  return {
    doc: MOCK_BRAND_SYSTEM,
    from_mock: true,
    motion_tokens_ready: motionTokensReady(MOCK_BRAND_SYSTEM),
  };
}

export function brandContextBlock(ctx: BrandContext): string {
  return JSON.stringify(
    {
      version: ctx.doc.version,
      color_tokens: ctx.doc.color_tokens,
      type_scale: ctx.doc.type_scale,
      motion_tokens: ctx.doc.motion_tokens,
      do_dont_rules: ctx.doc.do_dont_rules,
      from_mock: ctx.from_mock,
    },
    null,
    2
  );
}
