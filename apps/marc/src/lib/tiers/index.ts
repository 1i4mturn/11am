import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { users } from "@/lib/db/schema";
import { SINGLE_USER_DEBUG, effectiveTier } from "@/lib/config";

const FREE_ACTION_LIMIT = 20;
const DEFAULT_USER = "default";

export async function getUser(userId = DEFAULT_USER) {
  const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);

  if (!user) {
    await db.insert(users).values({ id: userId, tier: SINGLE_USER_DEBUG ? "pro" : "free" });
    const [created] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
    return { ...created!, tier: effectiveTier(created!.tier) };
  }

  const now = new Date();
  const resetAt = user.monthResetAt ? new Date(user.monthResetAt) : now;
  const monthElapsed =
    now.getMonth() !== resetAt.getMonth() || now.getFullYear() !== resetAt.getFullYear();

  if (monthElapsed && !SINGLE_USER_DEBUG) {
    await db
      .update(users)
      .set({ actionsThisMonth: 0, monthResetAt: now, updatedAt: now })
      .where(eq(users.id, userId));
    return { ...user, actionsThisMonth: 0, monthResetAt: now, tier: effectiveTier(user.tier) };
  }

  return { ...user, tier: effectiveTier(user.tier) };
}

export async function canPerformAction(userId = DEFAULT_USER): Promise<{
  allowed: boolean;
  tier: string;
  remaining: number | null;
  reason?: string;
}> {
  const user = await getUser(userId);

  if (SINGLE_USER_DEBUG || user.tier === "pro") {
    return { allowed: true, tier: user.tier, remaining: null };
  }

  const remaining = FREE_ACTION_LIMIT - user.actionsThisMonth;
  if (remaining <= 0) {
    return {
      allowed: false,
      tier: "free",
      remaining: 0,
      reason: "Free tier limit reached (20 actions/month). Upgrade to Pro.",
    };
  }

  return { allowed: true, tier: "free", remaining };
}

export async function incrementActionCount(userId = DEFAULT_USER) {
  const user = await getUser(userId);
  if (user.tier === "pro") return;

  await db
    .update(users)
    .set({
      actionsThisMonth: user.actionsThisMonth + 1,
      updatedAt: new Date(),
    })
    .where(eq(users.id, userId));
}

export async function setUserTier(tier: "free" | "pro", userId = DEFAULT_USER) {
  await getUser(userId);
  await db
    .update(users)
    .set({ tier, updatedAt: new Date() })
    .where(eq(users.id, userId));
}

export function tierFeatures(tier: string) {
  const pro = SINGLE_USER_DEBUG || tier === "pro";
  return {
    senderMemory: pro,
    williamVoice: pro,
    crossAgentHandoffs: pro,
    semanticSearch: pro,
    bulkCleanup: pro,
    ruleBuilder: pro,
    priorityInbox: pro,
    followUpNudges: false,
    pushSync: pro,
    unlimitedActions: pro,
    basicTriage: true,
    threadSummaries: true,
    simpleReplyDrafting: true,
    basicSearch: true,
    limitedBriefings: true,
  };
}

export async function setFullContentIndexing(enabled: boolean, userId = DEFAULT_USER) {
  await db
    .update(users)
    .set({ fullContentIndexing: enabled, updatedAt: new Date() })
    .where(eq(users.id, userId));
}
