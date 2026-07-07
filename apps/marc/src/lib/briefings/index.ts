import Anthropic from "@anthropic-ai/sdk";
import { triageInbox } from "@/lib/triage";
import { getRecentMessages } from "@/lib/gmail/sync";
import { suggestCleanupCandidates, suggestArchiveRules } from "@/lib/cleanup";
import { listSenderProfiles } from "@/lib/bolton";

function getAnthropic() {
  return new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
}

export async function generateDailyBriefing(userId = "default", isPro = false) {
  const messages = await getRecentMessages(userId, 30);
  const unread = messages.filter((m) => m.isUnread);
  const triaged = await triageInbox(unread.length ? unread : messages.slice(0, 15), isPro, 15);

  const needsAttention = triaged.filter(
    (t) => t.priority === "high" || t.classification === "needs_reply"
  );
  const waiting = triaged.filter((t) => t.classification === "waiting_on_other");
  const archiveable = triaged.filter((t) => t.classification === "archive" || t.classification === "newsletter");
  const draftReplies = triaged.filter((t) => t.suggested_reply);

  return {
    type: "daily" as const,
    generated_at: new Date().toISOString(),
    needs_attention: needsAttention,
    waiting_on_you: waiting,
    can_archive: archiveable.slice(0, 5),
    draft_replies_ready: draftReplies.slice(0, 3),
    summary: buildBriefingSummary("daily", needsAttention.length, waiting.length, archiveable.length),
  };
}

export async function generateWeeklyBriefing(userId = "default", isPro = false) {
  const messages = await getRecentMessages(userId, 100);
  const triaged = await triageInbox(messages.slice(0, 25), isPro, 25);

  const unanswered = triaged.filter((t) => t.classification === "needs_reply");
  const commercial = triaged.filter((t) => t.handoff_agent === "conner");
  const finance = triaged.filter((t) => t.classification === "finance" || t.handoff_agent === "george");
  const cleanup = isPro ? await suggestCleanupCandidates(userId, 10) : [];
  const ruleSuggestions = isPro ? await suggestArchiveRules(userId) : [];
  const senders = isPro ? await listSenderProfiles(userId) : [];

  const recurringSenders = senders
    .filter((s) => (s.recurringTopics as string[])?.length > 0)
    .slice(0, 5);

  return {
    type: "weekly" as const,
    generated_at: new Date().toISOString(),
    unanswered_important: unanswered,
    recurring_senders: recurringSenders.map((s) => ({
      sender: s.senderName ?? s.senderEmail,
      topics: s.recurringTopics,
    })),
    rule_suggestions: ruleSuggestions.slice(0, 3),
    commercial_opportunities: commercial,
    finance_system_issues: finance,
    cleanup_actions: cleanup.slice(0, 5),
    summary: buildBriefingSummary("weekly", unanswered.length, commercial.length, cleanup.length),
  };
}

function buildBriefingSummary(
  type: "daily" | "weekly",
  urgent: number,
  secondary: number,
  cleanup: number
): string {
  if (type === "daily") {
    return `${urgent} item${urgent !== 1 ? "s" : ""} need attention today. ${secondary} waiting on others. ${cleanup} can likely be archived.`;
  }
  return `${urgent} important threads still unanswered. ${secondary} commercial signals surfaced. ${cleanup} cleanup candidates identified.`;
}
