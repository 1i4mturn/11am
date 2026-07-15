import { eq, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import { emailMessages } from "@/lib/db/schema";

const PROTECTED_KEYWORDS = [
  "invoice",
  "receipt",
  "billing",
  "payment",
  "password",
  "security",
  "verify",
  "account",
  "legal",
  "contract",
  "tax",
  "xero",
  "alert",
  "access",
  "login",
  "api",
  "error",
];

export interface CleanupCandidate {
  message_id: string;
  sender: string;
  subject: string;
  category: "newsletter" | "promotion" | "cold_outreach" | "recurring_fyi";
  reason: string;
  has_unsubscribe: boolean;
  list_unsubscribe?: string | null;
  safe_to_archive: boolean;
}

function isProtected(message: {
  subject: string;
  body: string | null;
  snippet: string | null;
  labels: unknown;
}): boolean {
  const text = `${message.subject} ${message.body ?? ""} ${message.snippet ?? ""}`.toLowerCase();
  return PROTECTED_KEYWORDS.some((kw) => text.includes(kw));
}

export async function suggestCleanupCandidates(
  userId = "default",
  limit = 50
): Promise<CleanupCandidate[]> {
  const messages = await db
    .select()
    .from(emailMessages)
    .where(eq(emailMessages.userId, userId))
    .orderBy(sql`${emailMessages.receivedAt} DESC`)
    .limit(200);

  const candidates: CleanupCandidate[] = [];

  for (const msg of messages) {
    if (isProtected(msg)) continue;

    const labels = (msg.labels as string[]) ?? [];
    const text = `${msg.subject} ${msg.snippet ?? ""}`.toLowerCase();

    let category: CleanupCandidate["category"] | null = null;
    let reason = "";

    if (msg.hasUnsubscribe || labels.includes("CATEGORY_PROMOTIONS")) {
      category = msg.hasUnsubscribe ? "newsletter" : "promotion";
      reason = msg.hasUnsubscribe
        ? "Newsletter with list-unsubscribe header"
        : "Gmail classified as promotion";
    } else if (
      text.includes("unsubscribe") ||
      text.includes("marketing") ||
      text.includes("newsletter")
    ) {
      category = "newsletter";
      reason = "Newsletter/promotional language detected";
    } else if (
      text.includes("quick question") ||
      text.includes("partnership opportunity") ||
      text.includes("reaching out")
    ) {
      category = "cold_outreach";
      reason = "Likely cold outreach sequence";
    } else if (labels.includes("CATEGORY_UPDATES") && !msg.isUnread) {
      category = "recurring_fyi";
      reason = "Read FYI/update email - safe to archive";
    }

    if (category) {
      candidates.push({
        message_id: msg.messageId,
        sender: msg.senderName ?? msg.senderEmail,
        subject: msg.subject,
        category,
        reason,
        has_unsubscribe: msg.hasUnsubscribe ?? false,
        list_unsubscribe: msg.listUnsubscribe,
        safe_to_archive: category !== "cold_outreach",
      });
    }

    if (candidates.length >= limit) break;
  }

  return candidates;
}

export async function suggestArchiveRules(userId = "default") {
  const candidates = await suggestCleanupCandidates(userId, 100);
  const senderCounts = new Map<string, number>();

  for (const c of candidates) {
    senderCounts.set(c.sender, (senderCounts.get(c.sender) ?? 0) + 1);
  }

  return Array.from(senderCounts.entries())
    .filter(([, count]) => count >= 3)
    .map(([sender, count]) => ({
      rule_name: `Archive newsletters from ${sender}`,
      trigger: `sender:${sender}`,
      conditions: [`from ${sender}`, "contains newsletter or promotional content"],
      actions: ["archive after reading"],
      exceptions: PROTECTED_KEYWORDS.map((kw) => `do not archive if contains ${kw}`),
      suggested_affected_count: count,
    }));
}
