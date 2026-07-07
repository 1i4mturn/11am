import { searchBoltonMemory, listJamesResearch } from "@/lib/bolton/client";
import type { PriorResearchEntry } from "@/lib/types";

function normalizeEntry(raw: Record<string, unknown>): PriorResearchEntry | null {
  const id = String(raw.id ?? "");
  const title = String(raw.title ?? "");
  const summary = String(raw.summary ?? "");
  if (!id || !title) return null;
  return {
    id,
    title,
    summary,
    created_at: raw.created_at ? String(raw.created_at) : undefined,
  };
}

function topicTokens(topic: string): string[] {
  return topic
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter((t) => t.length > 3);
}

function relevanceScore(topic: string, entry: PriorResearchEntry): number {
  const tokens = topicTokens(topic);
  const hay = `${entry.title} ${entry.summary}`.toLowerCase();
  return tokens.reduce((score, t) => (hay.includes(t) ? score + 1 : score), 0);
}

/** Query Bolton for prior James research on the same topic before starting new work */
export async function checkPriorResearch(topic: string): Promise<PriorResearchEntry[]> {
  const [searchResults, jamesEntries] = await Promise.all([
    searchBoltonMemory(`James research ${topic}`),
    listJamesResearch(30),
  ]);

  const merged = new Map<string, PriorResearchEntry>();

  for (const r of searchResults) {
    if (r.source_agent?.toLowerCase() !== "james" && r.entry_type !== "research") continue;
    const entry = normalizeEntry(r as unknown as Record<string, unknown>);
    if (entry) merged.set(entry.id, entry);
  }

  for (const raw of jamesEntries) {
    const entry = normalizeEntry(raw);
    if (entry && relevanceScore(topic, entry) > 0) merged.set(entry.id, entry);
  }

  return [...merged.values()]
    .map((e) => ({ entry: e, score: relevanceScore(topic, e) }))
    .filter((x) => x.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, 5)
    .map((x) => x.entry);
}
