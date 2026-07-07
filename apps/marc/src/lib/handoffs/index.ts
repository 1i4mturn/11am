import { eq, desc } from "drizzle-orm";
import { db } from "@/lib/db";
import { handoffs } from "@/lib/db/schema";
import type { BoltonMemoryUpdate } from "@/lib/types";
import { saveMemory } from "@/lib/bolton";

export type HandoffAgent =
  | "william"
  | "leo"
  | "conner"
  | "george"
  | "james"
  | "bolton";

export async function createHandoff(
  targetAgent: HandoffAgent,
  artifact: Record<string, unknown>,
  sourceMessageId?: string,
  userId = "default"
) {
  const [handoff] = await db
    .insert(handoffs)
    .values({
      userId,
      targetAgent,
      artifact,
      sourceMessageId,
      status: "pending",
    })
    .returning();

  if (targetAgent === "bolton" && artifact.memory_type) {
    await saveMemory(artifact as unknown as BoltonMemoryUpdate, userId);
  }

  return handoff;
}

export async function listHandoffs(userId = "default", limit = 20) {
  return db
    .select()
    .from(handoffs)
    .where(eq(handoffs.userId, userId))
    .orderBy(desc(handoffs.createdAt))
    .limit(limit);
}

export function buildInboxReviewArtifact(item: Record<string, unknown>) {
  return {
    sender: item.sender,
    subject: item.subject,
    why_it_matters: item.why_it_matters,
    priority: item.priority,
    classification: item.classification,
    suggested_action: item.suggested_action,
    suggested_reply: item.suggested_reply,
  };
}

export function buildLeoHandoff(item: {
  subject: string;
  thread_summary?: string;
  suggested_action: string;
  thread_id: string;
}) {
  return {
    source: "marc_inbox",
    task: item.suggested_action,
    subject: item.subject,
    thread_summary: item.thread_summary,
    thread_id: item.thread_id,
    due: "review today",
  };
}

export function buildConnerHandoff(item: {
  sender: string;
  subject: string;
  thread_summary?: string;
  why_it_matters: string;
}) {
  return {
    signal_type: "commercial_email",
    sender: item.sender,
    subject: item.subject,
    summary: item.why_it_matters,
    thread_summary: item.thread_summary,
  };
}

export function buildGeorgeHandoff(item: {
  sender: string;
  subject: string;
  thread_summary?: string;
}) {
  return {
    signal_type: "finance_billing",
    sender: item.sender,
    subject: item.subject,
    summary: item.thread_summary,
  };
}

export function buildJamesHandoff(item: {
  subject: string;
  thread_summary?: string;
  research_question: string;
}) {
  return {
    source: "marc_inbox",
    research_question: item.research_question,
    subject: item.subject,
    context: item.thread_summary,
  };
}
