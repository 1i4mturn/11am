import { eq, desc, and } from "drizzle-orm";
import { db } from "@/lib/db";
import { georgeFinancialModels, georgeCalculators } from "@/lib/db/schema";
import type { ChatMessage } from "@/lib/db/schema";
import type { ModelType } from "@/lib/types";

export async function listModels(userId = "default") {
  return db
    .select()
    .from(georgeFinancialModels)
    .where(eq(georgeFinancialModels.userId, userId))
    .orderBy(desc(georgeFinancialModels.updatedAt));
}

export async function getModel(id: string, userId = "default") {
  const [row] = await db
    .select()
    .from(georgeFinancialModels)
    .where(and(eq(georgeFinancialModels.id, id), eq(georgeFinancialModels.userId, userId)))
    .limit(1);
  return row ?? null;
}

export async function saveModel(input: {
  id?: string;
  name: string;
  modelType: ModelType;
  inputs: Record<string, unknown>;
  assumptions: Record<string, unknown>;
  scenarios: unknown[];
  conversation: ChatMessage[];
  userId?: string;
}) {
  const userId = input.userId ?? "default";
  if (input.id) {
    const [row] = await db
      .update(georgeFinancialModels)
      .set({
        name: input.name,
        modelType: input.modelType,
        inputs: input.inputs,
        assumptions: input.assumptions,
        scenarios: input.scenarios,
        conversation: input.conversation,
        updatedAt: new Date(),
      })
      .where(and(eq(georgeFinancialModels.id, input.id), eq(georgeFinancialModels.userId, userId)))
      .returning();
    return row;
  }

  const [row] = await db
    .insert(georgeFinancialModels)
    .values({
      userId,
      name: input.name,
      modelType: input.modelType,
      inputs: input.inputs,
      assumptions: input.assumptions,
      scenarios: input.scenarios,
      conversation: input.conversation,
    })
    .returning();
  return row;
}

export async function listCalculators(userId = "default") {
  return db
    .select()
    .from(georgeCalculators)
    .where(eq(georgeCalculators.userId, userId))
    .orderBy(desc(georgeCalculators.createdAt));
}

export async function saveCalculator(input: {
  title: string;
  prompt: string;
  storagePath: string;
  publicUrl: string | null;
  memoryEntryId?: string;
  userId?: string;
}) {
  const [row] = await db
    .insert(georgeCalculators)
    .values({
      userId: input.userId ?? "default",
      title: input.title,
      prompt: input.prompt,
      storagePath: input.storagePath,
      publicUrl: input.publicUrl,
      memoryEntryId: input.memoryEntryId ?? null,
    })
    .returning();
  return row;
}
