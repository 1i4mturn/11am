import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { users } from "@/lib/db/schema";
import { SINGLE_USER_DEBUG, effectiveTier } from "@/lib/config";

const FREE_MEMORY_LIMIT = 50;
const DEFAULT_USER = "default";

export async function getUser(userId = DEFAULT_USER) {
  const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
  if (!user) {
    await db.insert(users).values({ id: userId, tier: SINGLE_USER_DEBUG ? "pro" : "free" });
    const [created] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
    return { ...created!, tier: effectiveTier(created!.tier) };
  }
  return { ...user, tier: effectiveTier(user.tier) };
}

export async function setUserTier(tier: "free" | "pro", userId = DEFAULT_USER) {
  await getUser(userId);
  await db.update(users).set({ tier, updatedAt: new Date() }).where(eq(users.id, userId));
}

export function tierFeatures(tier: string) {
  const pro = SINGLE_USER_DEBUG || tier === "pro";
  return {
    crossAgentMemory: pro,
    autoCapture: pro,
    semanticSearch: pro,
    entityGraph: pro,
    conflictDetection: pro,
    supersedeWorkflows: pro,
    notionSync: pro,
    contextPacks: pro,
    exportMemory: pro,
    unlimitedEntries: pro,
    basicMemorySaving: true,
    manualSearch: true,
    basicDecisionLog: true,
    viewEditDelete: true,
  };
}

export async function canSaveMemory(userId = DEFAULT_USER, currentCount: number) {
  const user = await getUser(userId);
  if (SINGLE_USER_DEBUG || user.tier === "pro") {
    return { allowed: true, remaining: null };
  }
  const remaining = FREE_MEMORY_LIMIT - currentCount;
  return {
    allowed: remaining > 0,
    remaining,
    reason: remaining <= 0 ? "Free tier memory limit reached (50 entries)" : undefined,
  };
}
