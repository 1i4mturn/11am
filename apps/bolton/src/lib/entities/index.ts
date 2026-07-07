import { eq, desc, and } from "drizzle-orm";
import { db } from "@/lib/db";
import { entities, entityRelationships } from "@/lib/db/schema";

export async function upsertEntity(
  data: {
    entityType: string;
    name: string;
    aliases?: string[];
    summary?: string;
    importanceLevel?: string;
    sourceEntryId?: string;
  },
  userId = "default"
) {
  const existing = await db
    .select()
    .from(entities)
    .where(and(eq(entities.userId, userId), eq(entities.name, data.name)))
    .limit(1);

  if (existing[0]) {
    const sourceEntries = existing[0].sourceEntries as string[];
    const [updated] = await db
      .update(entities)
      .set({
        summary: data.summary ?? existing[0].summary,
        aliases: data.aliases ?? existing[0].aliases,
        importanceLevel: data.importanceLevel ?? existing[0].importanceLevel,
        sourceEntries: data.sourceEntryId
          ? [...new Set([...sourceEntries, data.sourceEntryId])]
          : sourceEntries,
        lastUpdatedAt: new Date(),
      })
      .where(eq(entities.id, existing[0].id))
      .returning();
    return updated;
  }

  const [created] = await db
    .insert(entities)
    .values({
      userId,
      entityType: data.entityType,
      name: data.name,
      aliases: data.aliases ?? [],
      summary: data.summary ?? "",
      importanceLevel: data.importanceLevel ?? "medium",
      sourceEntries: data.sourceEntryId ? [data.sourceEntryId] : [],
    })
    .returning();
  return created;
}

export async function listEntities(userId = "default", entityType?: string) {
  return db
    .select()
    .from(entities)
    .where(
      entityType
        ? and(eq(entities.userId, userId), eq(entities.entityType, entityType))
        : eq(entities.userId, userId)
    )
    .orderBy(desc(entities.lastUpdatedAt));
}

export async function getEntity(id: string, userId = "default") {
  const [entity] = await db
    .select()
    .from(entities)
    .where(and(eq(entities.id, id), eq(entities.userId, userId)))
    .limit(1);
  return entity ?? null;
}

export async function addRelationship(
  entityAId: string,
  entityBId: string,
  relationshipType: string,
  context?: string,
  userId = "default"
) {
  const [rel] = await db
    .insert(entityRelationships)
    .values({ userId, entityAId, entityBId, relationshipType, context })
    .returning();
  return rel;
}

export async function getPersonContext(nameOrEmail: string, userId = "default") {
  const results = await db
    .select()
    .from(entities)
    .where(eq(entities.userId, userId));

  return results.filter(
    (e) =>
      e.name.toLowerCase().includes(nameOrEmail.toLowerCase()) ||
      (e.aliases as string[]).some((a) =>
        a.toLowerCase().includes(nameOrEmail.toLowerCase())
      )
  );
}
