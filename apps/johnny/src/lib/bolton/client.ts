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

export async function getBoltonContextBlock(task: string): Promise<string> {
  try {
    const res = await boltonFetch("/api/context", {
      method: "POST",
      body: JSON.stringify({ requesting_agent: "Johnny", task }),
    });
    if (res.ok) {
      const data = await res.json();
      return JSON.stringify(data.context_pack ?? data, null, 2);
    }
  } catch {
    // fallback
  }
  return "{}";
}
