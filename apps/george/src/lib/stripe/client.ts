import Stripe from "stripe";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { users } from "@/lib/db/schema";

export async function getStripeKey(userId = "default"): Promise<string | null> {
  const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
  return user?.stripeRestrictedKey ?? process.env.STRIPE_RESTRICTED_KEY ?? null;
}

export async function saveStripeKey(key: string, userId = "default") {
  await db
    .update(users)
    .set({ stripeRestrictedKey: key, updatedAt: new Date() })
    .where(eq(users.id, userId));
}

export async function getStripeMetrics(userId = "default") {
  const key = await getStripeKey(userId);
  if (!key) throw new Error("Stripe not configured — set STRIPE_RESTRICTED_KEY");

  const stripe = new Stripe(key);

  const now = Math.floor(Date.now() / 1000);
  const thirtyDaysAgo = now - 30 * 24 * 60 * 60;

  const [balance, subscriptions, charges] = await Promise.all([
    stripe.balance.retrieve(),
    stripe.subscriptions.list({ status: "active", limit: 100 }),
    stripe.charges.list({ created: { gte: thirtyDaysAgo }, limit: 100 }),
  ]);

  const mrrCents = subscriptions.data.reduce((sum, sub) => {
    const item = sub.items.data[0];
    if (!item?.price?.unit_amount) return sum;
    const amount = item.price.unit_amount;
    const interval = item.price.recurring?.interval;
    if (interval === "year") return sum + Math.round(amount / 12);
    if (interval === "month") return sum + amount;
    return sum;
  }, 0);

  const revenue30dCents = charges.data
    .filter((c) => c.paid && !c.refunded)
    .reduce((sum, c) => sum + c.amount, 0);

  const canceled = await stripe.subscriptions.list({
    status: "canceled",
    limit: 100,
    created: { gte: thirtyDaysAgo },
  });
  const activeCount = subscriptions.data.length;
  const churnRate =
    activeCount + canceled.data.length > 0
      ? (canceled.data.length / (activeCount + canceled.data.length)) * 100
      : 0;

  const available = balance.available[0];

  return {
    mrr: mrrCents / 100,
    mrr_currency: available?.currency?.toUpperCase() ?? "AUD",
    revenue_30d: revenue30dCents / 100,
    active_subscriptions: activeCount,
    churn_pct_30d: Math.round(churnRate * 10) / 10,
    balance_available: (available?.amount ?? 0) / 100,
    balance_currency: available?.currency?.toUpperCase() ?? "AUD",
  };
}
