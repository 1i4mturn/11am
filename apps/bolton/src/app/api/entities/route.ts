import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { upsertEntity, addRelationship, listEntities } from "@/lib/entities";
import { getPersonContext } from "@/lib/entities";
import { db } from "@/lib/db";
import { boltonSenderProfiles } from "@/lib/db/schema";
import { eq } from "drizzle-orm";
import { resolveUserId } from "@/lib/config";

export async function GET(request: NextRequest) {
  const userId = resolveUserId(request.headers.get("x-user-id"));
  const type = request.nextUrl.searchParams.get("type");
  const query = request.nextUrl.searchParams.get("q");

  if (query) {
    const people = await getPersonContext(query, userId);
    const senders = await db
      .select()
      .from(boltonSenderProfiles)
      .where(eq(boltonSenderProfiles.userId, userId));

    const matchingSenders = senders.filter(
      (s) =>
        s.senderEmail.includes(query.toLowerCase()) ||
        (s.senderName ?? "").toLowerCase().includes(query.toLowerCase())
    );

    return NextResponse.json({ entities: people, sender_profiles: matchingSenders });
  }

  const entities = await listEntities(userId, type ?? undefined);
  return NextResponse.json({ entities });
}

const EntitySchema = z.object({
  entity_type: z.enum(["person", "company", "project", "agent", "tool", "concept", "file"]),
  name: z.string().min(1),
  aliases: z.array(z.string()).optional(),
  summary: z.string().optional(),
  importance_level: z.string().optional(),
  source_entry_id: z.string().uuid().optional(),
});

const RelationshipSchema = z.object({
  entity_a_id: z.string().uuid(),
  entity_b_id: z.string().uuid(),
  relationship_type: z.string().min(1),
  context: z.string().optional(),
});

export async function POST(request: NextRequest) {
  const userId = resolveUserId(request.headers.get("x-user-id"));
  const body = await request.json();

  if (body.entity_a_id && body.entity_b_id) {
    const rel = RelationshipSchema.parse(body);
    const created = await addRelationship(
      rel.entity_a_id,
      rel.entity_b_id,
      rel.relationship_type,
      rel.context,
      userId
    );
    return NextResponse.json({ relationship: created });
  }

  const entity = EntitySchema.parse(body);
  const saved = await upsertEntity(
    {
      entityType: entity.entity_type,
      name: entity.name,
      aliases: entity.aliases,
      summary: entity.summary,
      importanceLevel: entity.importance_level,
      sourceEntryId: entity.source_entry_id,
    },
    userId
  );

  return NextResponse.json({ entity: saved });
}
