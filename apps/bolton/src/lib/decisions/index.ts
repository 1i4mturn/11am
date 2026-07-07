import { eq, desc, and } from "drizzle-orm";
import { db } from "@/lib/db";
import { decisions } from "@/lib/db/schema";
import { saveMemoryEntry } from "@/lib/memory";

export async function logDecision(
  data: {
    decision: string;
    context?: string;
    rationale?: string;
    alternativesConsidered?: string[];
    sourceAgent: string;
    decisionType?: string;
    relatedEntries?: string[];
  },
  userId = "default"
) {
  const [dec] = await db
    .insert(decisions)
    .values({
      userId,
      decision: data.decision,
      context: data.context ?? "",
      rationale: data.rationale ?? "",
      alternativesConsidered: data.alternativesConsidered ?? [],
      sourceAgent: data.sourceAgent,
      decisionType: data.decisionType ?? "product",
      relatedEntries: data.relatedEntries ?? [],
    })
    .returning();

  await saveMemoryEntry(
    {
      source_agent: data.sourceAgent,
      entry_type: "decision",
      title: data.decision.slice(0, 100),
      summary: `${data.context ?? ""} Rationale: ${data.rationale ?? ""}`.trim(),
      tags: ["decision", data.decisionType ?? "product"],
      importance_score: 0.8,
      confidence: "high",
    },
    userId,
    true
  );

  return dec;
}

export async function listDecisions(userId = "default", status = "active") {
  return db
    .select()
    .from(decisions)
    .where(and(eq(decisions.userId, userId), eq(decisions.status, status)))
    .orderBy(desc(decisions.createdAt));
}

export async function supersedeDecision(
  oldId: string,
  newId: string,
  userId = "default"
) {
  await db
    .update(decisions)
    .set({ status: "superseded", supersededById: newId })
    .where(and(eq(decisions.id, oldId), eq(decisions.userId, userId)));
}
