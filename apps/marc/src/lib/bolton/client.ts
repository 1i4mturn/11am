/** Write memory candidates to shared Bolton layer */
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
}) {
  const baseUrl = process.env.BOLTON_API_URL ?? "http://localhost:3002";
  try {
    await fetch(`${baseUrl}/api/memory`, {
      signal: AbortSignal.timeout(5_000),
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...candidate, force: candidate.force ?? true }),
    });
  } catch {
    // Bolton may be offline during dev — non-blocking
  }
}

export async function getPersonContextFromBolton(query: string) {
  const baseUrl = process.env.BOLTON_API_URL ?? "http://localhost:3002";
  try {
    const res = await fetch(`${baseUrl}/api/entities?q=${encodeURIComponent(query)}`, { signal: AbortSignal.timeout(5_000) });
    if (res.ok) return res.json();
  } catch {
    // fallback to direct DB in bolton/index.ts
  }
  return null;
}

export async function getBoltonContext(task: string) {
  const baseUrl = process.env.BOLTON_API_URL ?? "http://localhost:3002";
  try {
    const res = await fetch(`${baseUrl}/api/context`, {
      signal: AbortSignal.timeout(5_000),
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ requesting_agent: "Marc", task }),
    });
    if (res.ok) return res.json();
  } catch {}
  return null;
}
