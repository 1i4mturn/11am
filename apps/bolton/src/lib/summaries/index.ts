import { eq, desc, and } from "drizzle-orm";
import { db } from "@/lib/db";
import { boltonAgentSummaries } from "@/lib/db/schema";

export interface GeorgeLatestNumbers {
  source_agent: "George";
  as_of: string;
  revenue: string;
  margin_pct: number;
  runway_months: number;
  burn_rate: string;
  flags: string[];
  confidence: "high" | "medium" | "low";
}

export async function getLatestAgentSummary(agentId: string, userId = "default") {
  const [row] = await db
    .select()
    .from(boltonAgentSummaries)
    .where(and(eq(boltonAgentSummaries.agentId, agentId), eq(boltonAgentSummaries.userId, userId)))
    .orderBy(desc(boltonAgentSummaries.createdAt))
    .limit(1);
  return row ?? null;
}

export async function writeAgentSummary(
  agentId: string,
  summary: Record<string, unknown>,
  userId = "default",
  sessionNote?: string,
  memoryEntryId?: string
) {
  const [row] = await db
    .insert(boltonAgentSummaries)
    .values({
      agentId,
      userId,
      summary,
      sessionNote: sessionNote ?? null,
      memoryEntryId: memoryEntryId ?? null,
    })
    .returning();
  return row;
}
