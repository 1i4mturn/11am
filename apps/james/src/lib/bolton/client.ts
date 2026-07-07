const BOLTON_BASE = process.env.BOLTON_API_URL ?? "http://localhost:3002";

export async function writeToBolton(candidate: {
  source_agent: string;
  entry_type: string;
  title: string;
  summary: string;
  full_content?: string;
  tags?: string[];
  force?: boolean;
}): Promise<{ id?: string } | null> {
  try {
    const res = await fetch(`${BOLTON_BASE}/api/memory`, {
      signal: AbortSignal.timeout(5000),
      method: "POST",
      headers: { "Content-Type": "application/json" },
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

export async function searchBoltonMemory(query: string) {
  try {
    const res = await fetch(`${BOLTON_BASE}/api/search`, {
      signal: AbortSignal.timeout(5000),
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ query }),
    });
    if (res.ok) {
      const data = await res.json();
      return (data.results ?? []) as Array<{
        id: string;
        title: string;
        summary: string;
        source_agent: string;
        entry_type: string;
      }>;
    }
  } catch {
    // fallback
  }
  return [];
}

export async function listJamesResearch(limit = 20) {
  try {
    const res = await fetch(`${BOLTON_BASE}/api/memory?source_agent=James&entry_type=research&status=active`, { signal: AbortSignal.timeout(5000) });
    if (!res.ok) return [];
    const data = await res.json();
    return (data.entries ?? []).slice(0, limit) as Array<Record<string, unknown>>;
  } catch {
    return [];
  }
}
