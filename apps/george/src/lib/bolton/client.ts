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

export async function writeLatestNumbers(
  summary: Record<string, unknown>
): Promise<{ id?: string } | null> {
  try {
    const res = await boltonFetch("/api/agent-summaries", {
      method: "POST",
      body: JSON.stringify({
        agent_id: "george",
        summary,
        session_note: "George latest numbers update",
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

export async function getBoltonContext(task: string) {
  try {
    const res = await boltonFetch("/api/context", {
      method: "POST",
      body: JSON.stringify({ requesting_agent: "George", task }),
    });
    if (res.ok) return res.json();
  } catch {
    // fallback
  }
  return null;
}
