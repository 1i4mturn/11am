import { eq, desc, and, sql, or } from "drizzle-orm";
import { db } from "@/lib/db";
import { memoryEntries, entities, decisions, conflicts } from "@/lib/db/schema";
import { embedText } from "@/lib/search/embeddings";
import { classifyCapture, containsSecrets } from "@/lib/memory/capture";
import { upsertEntity } from "@/lib/entities";
import { syncEntryToNotion } from "@/lib/notion";
import type { CaptureCandidate, ContextPack, CadenceSchema } from "@/lib/types";
import type { z } from "zod";

const DEFAULT_USER = "default";

type Cadence = z.infer<typeof CadenceSchema>;

function extractCadence(candidate: CaptureCandidate): {
  cadence: Cadence | null;
  customSchedule: string | null;
} {
  if (candidate.entry_type !== "task") {
    return { cadence: null, customSchedule: null };
  }

  if (candidate.cadence) {
    return {
      cadence: candidate.cadence,
      customSchedule: candidate.custom_schedule ?? null,
    };
  }

  const tagCadence = candidate.tags?.find((t) => t.startsWith("cadence:"));
  if (tagCadence) {
    const value = tagCadence.replace("cadence:", "") as Cadence;
    return { cadence: value, customSchedule: null };
  }

  try {
    const parsed = JSON.parse(candidate.full_content ?? "{}") as {
      cadence?: Cadence;
      custom_schedule?: string;
    };
    return {
      cadence: parsed.cadence ?? null,
      customSchedule: parsed.custom_schedule ?? null,
    };
  } catch {
    return { cadence: null, customSchedule: null };
  }
}

async function insertMemoryRow(
  candidate: CaptureCandidate,
  userId: string,
  embeddingStr: string
) {
  const { cadence, customSchedule } = extractCadence(candidate);

  const [entry] = await db.execute(sql`
    INSERT INTO memory_entries (
      user_id, source_agent, entry_type, title, summary, full_content,
      tags, related_entities, related_entries, importance_score, confidence,
      cadence, custom_schedule, embedding
    ) VALUES (
      ${userId}, ${candidate.source_agent}, ${candidate.entry_type},
      ${candidate.title}, ${candidate.summary}, ${candidate.full_content ?? null},
      ${JSON.stringify(candidate.tags ?? [])}::jsonb,
      ${JSON.stringify(candidate.related_entities ?? [])}::jsonb,
      ${JSON.stringify(candidate.related_entries ?? [])}::jsonb,
      ${candidate.importance_score ?? 0.5}, ${candidate.confidence ?? "medium"},
      ${cadence}, ${customSchedule},
      ${embeddingStr}::vector
    )
    RETURNING id, title, summary, entry_type, source_agent, status, cadence, created_at
  `);

  return (entry as unknown as Array<Record<string, unknown>>)[0];
}

async function linkEntries(
  entryId: string,
  linkedId: string,
  userId: string
) {
  const [linked] = await db
    .select()
    .from(memoryEntries)
    .where(and(eq(memoryEntries.id, linkedId), eq(memoryEntries.userId, userId)))
    .limit(1);

  if (!linked) return;

  const linkedRelated = [...((linked.relatedEntries as string[]) ?? []), entryId];
  await db
    .update(memoryEntries)
    .set({ relatedEntries: linkedRelated, lastAccessedAt: new Date() })
    .where(eq(memoryEntries.id, linkedId));

  await db
    .update(memoryEntries)
    .set({ relatedEntries: [linkedId], lastAccessedAt: new Date() })
    .where(eq(memoryEntries.id, entryId));
}

async function extractEntitiesFromEntry(
  entryId: string,
  candidate: CaptureCandidate,
  userId: string
) {
  const typeMap: Record<string, string> = {
    person: "person",
    sender_memory: "person",
    project: "project",
    voice: "concept",
    research: "concept",
  };

  const entityType = typeMap[candidate.entry_type];
  if (!entityType) return;

  const entity = await upsertEntity(
    {
      entityType,
      name: candidate.title.replace(/^Sender:\s*/i, "").slice(0, 120),
      summary: candidate.summary,
      sourceEntryId: entryId,
      importanceLevel:
        candidate.importance_score && candidate.importance_score >= 0.8 ? "high" : "medium",
    },
    userId
  );

  await db
    .update(memoryEntries)
    .set({ relatedEntities: [entity.id] })
    .where(eq(memoryEntries.id, entryId));
}

export async function saveMemoryEntry(
  candidate: CaptureCandidate,
  userId = DEFAULT_USER,
  force = false
) {
  const existing = await db
    .select({ title: memoryEntries.title, id: memoryEntries.id })
    .from(memoryEntries)
    .where(and(eq(memoryEntries.userId, userId), eq(memoryEntries.status, "active")));

  const classification = force
    ? { action: "save" as const, reason: "Forced save" }
    : await classifyCapture(candidate, existing);

  if (classification.action === "skip") {
    return { saved: false, action: classification.action, reason: classification.reason };
  }

  if (classification.action === "ask_user") {
    return { saved: false, action: "ask_user", reason: classification.reason, candidate };
  }

  const embedContent = `${candidate.title}\n${candidate.summary}\n${candidate.full_content ?? ""}`;
  const embedding = await embedText(embedContent);
  const embeddingStr = `[${embedding.join(",")}]`;

  const similarId =
    classification.similarTo &&
    existing.find(
      (e) =>
        e.id === classification.similarTo ||
        e.title.toLowerCase() === classification.similarTo?.toLowerCase()
    )?.id;

  if (
    (classification.action === "update" || classification.action === "supersede") &&
    similarId
  ) {
    if (classification.action === "update") {
      await db
        .update(memoryEntries)
        .set({
          summary: candidate.summary,
          fullContent: candidate.full_content,
          tags: candidate.tags ?? [],
          importanceScore: candidate.importance_score ?? 0.5,
          lastAccessedAt: new Date(),
        })
        .where(eq(memoryEntries.id, similarId));
      return { saved: true, action: "update", id: similarId };
    }

    const row = await insertMemoryRow(candidate, userId, embeddingStr);
    await supersedeEntry(similarId, String(row.id), userId);
    await extractEntitiesFromEntry(String(row.id), candidate, userId);
    syncEntryToNotion(String(row.id), candidate).catch(() => {});
    return { saved: true, action: "supersede", id: row.id, superseded: similarId };
  }

  const row = await insertMemoryRow(candidate, userId, embeddingStr);
  const entryId = String(row.id);

  if (classification.action === "link" && similarId) {
    await linkEntries(entryId, similarId, userId);
  }

  await extractEntitiesFromEntry(entryId, candidate, userId);
  syncEntryToNotion(entryId, candidate).catch(() => {});

  return { saved: true, action: classification.action, entry: row };
}

export async function supersedeEntry(
  oldId: string,
  newId: string,
  userId = DEFAULT_USER
) {
  await db
    .update(memoryEntries)
    .set({ status: "superseded", supersededById: newId })
    .where(and(eq(memoryEntries.id, oldId), eq(memoryEntries.userId, userId)));
}

export async function archiveMemoryEntry(id: string, userId = DEFAULT_USER) {
  await db
    .update(memoryEntries)
    .set({ status: "archived", lastAccessedAt: new Date() })
    .where(and(eq(memoryEntries.id, id), eq(memoryEntries.userId, userId)));
}

export async function getMemoryEntry(id: string, userId = DEFAULT_USER) {
  const [entry] = await db
    .select()
    .from(memoryEntries)
    .where(and(eq(memoryEntries.id, id), eq(memoryEntries.userId, userId)))
    .limit(1);

  if (entry) {
    await db
      .update(memoryEntries)
      .set({ lastAccessedAt: new Date() })
      .where(eq(memoryEntries.id, id));
  }
  return entry ?? null;
}

export async function listMemoryEntries(
  userId = DEFAULT_USER,
  filters: { status?: string; sourceAgent?: string; entryType?: string } = {},
  limit = 50
) {
  let query = sql`
    SELECT * FROM memory_entries
    WHERE user_id = ${userId}
  `;
  if (filters.status) query = sql`${query} AND status = ${filters.status}`;
  if (filters.sourceAgent) query = sql`${query} AND source_agent = ${filters.sourceAgent}`;
  if (filters.entryType) query = sql`${query} AND entry_type = ${filters.entryType}`;
  query = sql`${query} ORDER BY created_at DESC LIMIT ${limit}`;

  return db.execute(query);
}

export async function updateMemoryEntry(
  id: string,
  updates: {
    title?: string;
    summary?: string;
    tags?: string[];
    status?: string;
    full_content?: string;
  },
  userId = DEFAULT_USER
) {
  await db
    .update(memoryEntries)
    .set({
      ...(updates.title && { title: updates.title }),
      ...(updates.summary && { summary: updates.summary }),
      ...(updates.tags && { tags: updates.tags }),
      ...(updates.status && { status: updates.status }),
      ...(updates.full_content !== undefined && { fullContent: updates.full_content }),
      lastAccessedAt: new Date(),
    })
    .where(and(eq(memoryEntries.id, id), eq(memoryEntries.userId, userId)));
}

/** Never hard-delete — archive only */
export async function deleteMemoryEntry(id: string, userId = DEFAULT_USER) {
  await archiveMemoryEntry(id, userId);
}

export async function exportAllMemory(userId = DEFAULT_USER) {
  const entries = await db
    .select()
    .from(memoryEntries)
    .where(eq(memoryEntries.userId, userId));
  const ents = await db.select().from(entities).where(eq(entities.userId, userId));
  const decs = await db.select().from(decisions).where(eq(decisions.userId, userId));
  return { exported_at: new Date().toISOString(), entries, entities: ents, decisions: decs };
}

export async function buildContextPack(
  requestingAgent: string,
  task: string,
  userId = DEFAULT_USER
): Promise<ContextPack> {
  const queryEmbedding = await embedText(`${task} ${requestingAgent}`);
  const embeddingStr = `[${queryEmbedding.join(",")}]`;

  const relevant = await db.execute(sql`
    SELECT id, title, summary, entry_type, source_agent,
           1 - (embedding <=> ${embeddingStr}::vector) AS similarity
    FROM memory_entries
    WHERE user_id = ${userId} AND status = 'active' AND embedding IS NOT NULL
    ORDER BY embedding <=> ${embeddingStr}::vector
    LIMIT 8
  `);

  const activeDecisions = await db
    .select({
      decision: decisions.decision,
      sourceAgent: decisions.sourceAgent,
      context: decisions.context,
    })
    .from(decisions)
    .where(and(eq(decisions.userId, userId), eq(decisions.status, "active")))
    .orderBy(desc(decisions.createdAt))
    .limit(5);

  const openConflicts = await db
    .select({ description: conflicts.description })
    .from(conflicts)
    .where(and(eq(conflicts.userId, userId), eq(conflicts.status, "open")))
    .limit(5);

  const memoryRows = relevant as unknown as Array<{
    id: string;
    title: string;
    summary: string;
    entry_type: string;
    source_agent: string;
  }>;

  const entityList = await db
    .select()
    .from(entities)
    .where(eq(entities.userId, userId))
    .orderBy(desc(entities.lastUpdatedAt))
    .limit(5);

  const taskWords = task.toLowerCase().split(/\s+/).filter((w) => w.length > 3);
  const matchedEntities = entityList.filter((e) => {
    const blob = `${e.name} ${e.summary} ${e.entityType}`.toLowerCase();
    return taskWords.some((w) => blob.includes(w));
  });

  return {
    requesting_agent: requestingAgent,
    task,
    relevant_memory: memoryRows.map((r) => ({
      id: r.id,
      title: r.title,
      summary: r.summary,
      entry_type: r.entry_type as ContextPack["relevant_memory"][0]["entry_type"],
      source_agent: r.source_agent,
    })),
    relevant_entities: (matchedEntities.length ? matchedEntities : entityList.slice(0, 3)).map(
      (e) => ({
        id: e.id,
        name: e.name,
        entity_type: e.entityType,
        summary: e.summary,
      })
    ),
    active_decisions: activeDecisions.map(
      (d) => `${d.decision} (${d.sourceAgent})${d.context ? ` — ${d.context}` : ""}`
    ),
    warnings: openConflicts.map((c) => c.description),
  };
}

export async function detectConflicts(userId = DEFAULT_USER) {
  const active = await db
    .select()
    .from(memoryEntries)
    .where(and(eq(memoryEntries.userId, userId), eq(memoryEntries.status, "active")))
    .orderBy(desc(memoryEntries.createdAt))
    .limit(100);

  const openConflicts = await db
    .select()
    .from(conflicts)
    .where(and(eq(conflicts.userId, userId), eq(conflicts.status, "open")));

  const found: Array<{ a: string; b: string; reason: string }> = [];

  for (let i = 0; i < active.length; i++) {
    for (let j = i + 1; j < active.length; j++) {
      const a = active[i];
      const b = active[j];
      if (
        a.entryType === b.entryType &&
        a.title.toLowerCase().slice(0, 12) === b.title.toLowerCase().slice(0, 12) &&
        a.summary !== b.summary
      ) {
        found.push({
          a: a.id,
          b: b.id,
          reason: `Similar titles, different summaries: "${a.title}" vs "${b.title}"`,
        });
      }
    }
  }

  const inserted: typeof found = [];

  for (const f of found.slice(0, 5)) {
    const already = openConflicts.some(
      (c) =>
        (c.entriesInvolved as string[]).includes(f.a) &&
        (c.entriesInvolved as string[]).includes(f.b)
    );
    if (already) continue;

    await db.insert(conflicts).values({
      userId,
      conflictType: "contradictory_memory",
      entriesInvolved: [f.a, f.b],
      description: f.reason,
      recommendedResolution: "Review both entries and supersede the older one",
    });

    await db
      .update(memoryEntries)
      .set({ status: "conflict_review" })
      .where(or(eq(memoryEntries.id, f.a), eq(memoryEntries.id, f.b)));

    inserted.push(f);
  }

  return inserted;
}

export { containsSecrets };
