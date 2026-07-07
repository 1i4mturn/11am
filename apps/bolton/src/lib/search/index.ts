import Anthropic from "@anthropic-ai/sdk";
import { sql, eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { memoryEntries } from "@/lib/db/schema";
import { embedText } from "@/lib/search/embeddings";

function getAnthropic() {
  return new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
}

export interface MemorySearchResult {
  id: string;
  title: string;
  entry_type: string;
  source_agent: string;
  date: string;
  why_matched: string;
  summary: string;
  related_entries: string[];
  citation: string;
}

export async function parseMemoryQuery(query: string) {
  const response = await getAnthropic().messages.create({
    model: "claude-sonnet-4-20250514",
    max_tokens: 512,
    messages: [
      {
        role: "user",
        content: `Parse memory search query into JSON:
{"keywords": [], "entry_type": null, "source_agent": null, "semantic_query": "fuzzy concept"}

Query: "${query}"
Return ONLY JSON.`,
      },
    ],
  });

  const textBlock = response.content.find((b) => b.type === "text");
  const text = textBlock?.type === "text" ? textBlock.text : "{}";
  const jsonMatch = text.match(/\{[\s\S]*\}/);
  return jsonMatch ? JSON.parse(jsonMatch[0]) : { semantic_query: query };
}

export async function searchMemory(
  query: string,
  userId = "default",
  isPro = false,
  limit = 10
): Promise<MemorySearchResult[]> {
  const parsed = await parseMemoryQuery(query);
  const results: MemorySearchResult[] = [];

  let keywordResults = await db.execute(sql`
    SELECT id, title, entry_type, source_agent, summary, related_entries, created_at
    FROM memory_entries
    WHERE user_id = ${userId} AND status = 'active'
      ${parsed.source_agent ? sql`AND source_agent ILIKE ${"%" + parsed.source_agent + "%"}` : sql``}
      ${parsed.entry_type ? sql`AND entry_type = ${parsed.entry_type}` : sql``}
      ${parsed.keywords?.length ? sql`AND (${sql.join((parsed.keywords as string[]).map((k: string) => sql`(title ILIKE ${"%" + k + "%"} OR summary ILIKE ${"%" + k + "%"})`), sql` OR `)})` : sql``}
    ORDER BY importance_score DESC, created_at DESC
    LIMIT ${limit}
  `);

  for (const row of keywordResults as unknown as Array<Record<string, unknown>>) {
    results.push({
      id: String(row.id),
      title: String(row.title),
      entry_type: String(row.entry_type),
      source_agent: String(row.source_agent),
      date: new Date(String(row.created_at)).toISOString(),
      why_matched: "Keyword/metadata match",
      summary: String(row.summary),
      related_entries: (row.related_entries as string[]) ?? [],
      citation: `[Bolton:${String(row.id).slice(0, 8)}] ${row.title}`,
    });
  }

  if (isPro) {
    const embedding = await embedText(parsed.semantic_query ?? query);
    const embeddingStr = `[${embedding.join(",")}]`;

    const vectorResults = await db.execute(sql`
      SELECT id, title, entry_type, source_agent, summary, related_entries, created_at,
             1 - (embedding <=> ${embeddingStr}::vector) AS similarity
      FROM memory_entries
      WHERE user_id = ${userId} AND status = 'active' AND embedding IS NOT NULL
      ORDER BY embedding <=> ${embeddingStr}::vector
      LIMIT ${limit}
    `);

    for (const row of vectorResults as unknown as Array<Record<string, unknown>>) {
      if (!results.find((r) => r.id === String(row.id))) {
        results.push({
          id: String(row.id),
          title: String(row.title),
          entry_type: String(row.entry_type),
          source_agent: String(row.source_agent),
          date: new Date(String(row.created_at)).toISOString(),
          why_matched: `Semantic match (${Math.round(Number(row.similarity) * 100)}%)`,
          summary: String(row.summary),
          related_entries: (row.related_entries as string[]) ?? [],
          citation: `[Bolton:${String(row.id).slice(0, 8)}] ${row.title}`,
        });
      }
    }
  }

  return results.slice(0, limit);
}
