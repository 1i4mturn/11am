import Anthropic from "@anthropic-ai/sdk";
import { sql, eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { emailMessages } from "@/lib/db/schema";
import { embedText } from "@/lib/search/embeddings";
import type { SearchResult } from "@/lib/types";
import { summarizeThread } from "@/lib/triage";

function getAnthropic() {
  return new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
}

interface ParsedQuery {
  sender?: string;
  dateFrom?: string;
  dateTo?: string;
  unreadOnly?: boolean;
  keywords?: string[];
  semanticQuery?: string;
}

export async function parseNaturalLanguageQuery(query: string): Promise<ParsedQuery> {
  const response = await getAnthropic().messages.create({
    model: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-20250514",
    max_tokens: 512,
    messages: [
      {
        role: "user",
        content: `Parse this email search query into JSON filters:
{"sender": "optional email or name", "dateFrom": "ISO date or null", "dateTo": "ISO date or null", "unreadOnly": boolean, "keywords": ["exact terms"], "semanticQuery": "fuzzy concept for vector search"}

Query: "${query}"

Return ONLY JSON.`,
      },
    ],
  });

  const textBlock = response.content.find((b) => b.type === "text");
  const text = textBlock?.type === "text" ? textBlock.text : "{}";
  const jsonMatch = text.match(/\{[\s\S]*\}/);
  return jsonMatch ? JSON.parse(jsonMatch[0]) : { semanticQuery: query };
}

export async function hybridSearch(
  query: string,
  userId = "default",
  isPro = false,
  limit = 10
): Promise<SearchResult[]> {
  const parsed = await parseNaturalLanguageQuery(query);
  const results: Array<{
    message_id: string;
    thread_id: string;
    sender_email: string;
    sender_name: string | null;
    subject: string;
    received_at: Date;
    snippet: string | null;
    body: string | null;
    similarity?: number;
    match_reason: string;
  }> = [];

  let metadataResults = await db.execute(sql`
    SELECT message_id, thread_id, sender_email, sender_name, subject,
           received_at, snippet, body
    FROM email_messages
    WHERE user_id = ${userId}
      ${parsed.sender ? sql`AND (sender_email ILIKE ${"%" + parsed.sender + "%"} OR sender_name ILIKE ${"%" + parsed.sender + "%"})` : sql``}
      ${parsed.unreadOnly ? sql`AND is_unread = true` : sql``}
      ${parsed.dateFrom ? sql`AND received_at >= ${parsed.dateFrom}::timestamp` : sql``}
      ${parsed.dateTo ? sql`AND received_at <= ${parsed.dateTo}::timestamp` : sql``}
      ${parsed.keywords?.length ? sql`AND (${sql.join(parsed.keywords.map((k) => sql`(subject ILIKE ${"%" + k + "%"} OR body ILIKE ${"%" + k + "%"} OR snippet ILIKE ${"%" + k + "%"})`), sql` OR `)})` : sql``}
    ORDER BY received_at DESC
    LIMIT ${limit}
  `);

  const metaRows = metadataResults as unknown as typeof results;
  for (const row of metaRows) {
    results.push({ ...row, match_reason: "Metadata/keyword match" });
  }

  if (isPro && (parsed.semanticQuery || query)) {
    const embedding = await embedText(parsed.semanticQuery ?? query);
    const embeddingStr = `[${embedding.join(",")}]`;

    const vectorResults = await db.execute(sql`
      SELECT message_id, thread_id, sender_email, sender_name, subject,
             received_at, snippet, body,
             1 - (embedding <=> ${embeddingStr}::vector) AS similarity
      FROM email_messages
      WHERE user_id = ${userId} AND embedding IS NOT NULL
      ORDER BY embedding <=> ${embeddingStr}::vector
      LIMIT ${limit}
    `);

    for (const row of vectorResults as unknown as typeof results) {
      if (!results.find((r) => r.message_id === row.message_id)) {
        results.push({
          ...row,
          match_reason: `Semantic match (${Math.round((row.similarity ?? 0) * 100)}% similar)`,
        });
      }
    }
  }

  const searchResults: SearchResult[] = [];
  for (const row of results.slice(0, limit)) {
    const threadMsgs = await db
      .select()
      .from(emailMessages)
      .where(
        sql`${emailMessages.userId} = ${userId} AND ${emailMessages.threadId} = ${row.thread_id}`
      )
      .limit(5);

    const threadSummary =
      threadMsgs.length > 1
        ? await summarizeThread(threadMsgs)
        : row.snippet ?? row.body?.slice(0, 200) ?? "";

    searchResults.push({
      message_id: row.message_id,
      thread_id: row.thread_id,
      sender: row.sender_name ?? row.sender_email,
      subject: row.subject,
      date: new Date(row.received_at).toISOString(),
      why_matched: row.match_reason,
      thread_summary: threadSummary,
      suggested_action: row.similarity && row.similarity > 0.8 ? "Review and reply" : "Review thread",
    });
  }

  return searchResults;
}
