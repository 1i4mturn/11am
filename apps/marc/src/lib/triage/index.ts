import Anthropic from "@anthropic-ai/sdk";
import { eq, and } from "drizzle-orm";
import type { InboxReviewItem, Priority, TriageClassification } from "@/lib/types";
import { getSenderProfile, upsertSenderProfile } from "@/lib/bolton";
import { db } from "@/lib/db";
import { emailMessages } from "@/lib/db/schema";
import type { emailMessages as EmailMessagesTable } from "@/lib/db/schema";

function getAnthropic() {
  return new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
}

type EmailRow = typeof EmailMessagesTable.$inferSelect;

const TRIAGE_PROMPT = `You are Marc, the inbox intelligence agent for 11am. Triage this email.

Return ONLY valid JSON:
{
  "why_it_matters": "One sentence on why this needs attention or can be ignored",
  "priority": "high | medium | low",
  "classification": "needs_reply | needs_action | waiting_on_other | fyi | archive | newsletter | finance | system | executive | sensitive",
  "suggested_action": "Specific next step",
  "suggested_reply": "Optional draft reply if needs_reply, else omit or empty string",
  "handoff_agent": "Optional: william | leo | conner | george | james | bolton | null",
  "relationship_type": "executive | client | franchisee | supplier | finance | friend | unknown",
  "update_sender_memory": true/false
}

Rules:
- Direct requests to the user are important
- Prioritise executives, clients, franchisees, finance, billing, contracts, system/access issues
- Ignore promotions/newsletters unless they contain account, billing, or system info
- Be discreet and concise
- Flag sensitive, urgent, or reputation-relevant items
- Never suggest autonomous sending`;

export async function triageMessage(
  message: EmailRow,
  senderContext?: string,
  isPro = false
): Promise<InboxReviewItem & { updateSenderMemory?: boolean; relationshipType?: string }> {
  const senderProfile = isPro
    ? await getSenderProfile(message.senderEmail)
    : null;

  const context = senderProfile
    ? `Sender memory: ${senderProfile.relationshipType}, importance ${senderProfile.importanceLevel}, tone ${senderProfile.preferredTone}. ${senderProfile.lastInteractionSummary ?? ""}`
    : senderContext ?? "";

  const response = await getAnthropic().messages.create({
    model: "claude-sonnet-4-20250514",
    max_tokens: 2048,
    messages: [
      {
        role: "user",
        content: `${TRIAGE_PROMPT}

Email:
From: ${message.senderName ?? message.senderEmail} <${message.senderEmail}>
Subject: ${message.subject}
Date: ${message.receivedAt}
Labels: ${(message.labels as string[])?.join(", ") ?? ""}
Snippet: ${message.snippet}
${message.body ? `Body:\n${message.body.slice(0, 3000)}` : ""}
${context ? `\nSender context:\n${context}` : ""}`,
      },
    ],
  });

  const textBlock = response.content.find((b) => b.type === "text");
  const text = textBlock?.type === "text" ? textBlock.text : "{}";
  const jsonMatch = text.match(/\{[\s\S]*\}/);
  const parsed = jsonMatch ? JSON.parse(jsonMatch[0]) : {};

  const item: InboxReviewItem & {
    updateSenderMemory?: boolean;
    relationshipType?: string;
  } = {
    message_id: message.messageId,
    thread_id: message.threadId,
    sender: message.senderName ?? message.senderEmail,
    sender_email: message.senderEmail,
    subject: message.subject,
    why_it_matters: parsed.why_it_matters ?? "Review recommended",
    priority: (parsed.priority ?? "medium") as Priority,
    classification: (parsed.classification ?? "fyi") as TriageClassification,
    suggested_action: parsed.suggested_action ?? "Review",
    suggested_reply: parsed.suggested_reply || undefined,
    handoff_agent: parsed.handoff_agent ?? undefined,
    updateSenderMemory: parsed.update_sender_memory,
    relationshipType: parsed.relationship_type,
  };

  if (isPro && parsed.update_sender_memory) {
    const profile = await upsertSenderProfile({
      senderEmail: message.senderEmail,
      senderName: message.senderName ?? undefined,
      relationshipType: parsed.relationship_type ?? "unknown",
      importanceLevel: parsed.priority === "high" ? "high" : "medium",
      lastInteractionSummary: parsed.why_it_matters,
      activeThreadTopics: [message.subject],
      urgencyHistory: [parsed.priority],
      responseExpectation: parsed.classification === "needs_reply" ? "prompt" : "normal",
      relatedAgentFlags: parsed.handoff_agent ? [parsed.handoff_agent] : [],
    });

    await db
      .update(emailMessages)
      .set({
        urgencyClassification: item.priority,
        actionClassification: item.classification,
        threadSummary: item.why_it_matters,
        senderMemoryId: profile?.id ?? null,
      })
      .where(
        and(
          eq(emailMessages.userId, "default"),
          eq(emailMessages.messageId, message.messageId)
        )
      );
  } else {
    await db
      .update(emailMessages)
      .set({
        urgencyClassification: item.priority,
        actionClassification: item.classification,
        threadSummary: item.why_it_matters,
      })
      .where(
        and(
          eq(emailMessages.userId, "default"),
          eq(emailMessages.messageId, message.messageId)
        )
      );
  }

  return item;
}

export async function triageInbox(
  messages: EmailRow[],
  isPro = false,
  limit = 20
): Promise<InboxReviewItem[]> {
  const toTriage = messages.slice(0, limit);
  const results: InboxReviewItem[] = [];

  for (const msg of toTriage) {
    const item = await triageMessage(msg, undefined, isPro);
    results.push(item);
  }

  return results.sort((a, b) => {
    const order = { high: 0, medium: 1, low: 2 };
    return order[a.priority] - order[b.priority];
  });
}

export async function summarizeThread(messages: EmailRow[]): Promise<string> {
  const threadText = messages
    .map(
      (m) =>
        `From: ${m.senderEmail}\nSubject: ${m.subject}\n${m.body?.slice(0, 1000) ?? m.snippet}`
    )
    .join("\n\n---\n\n");

  const response = await getAnthropic().messages.create({
    model: "claude-sonnet-4-20250514",
    max_tokens: 1024,
    messages: [
      {
        role: "user",
        content: `Summarise this email thread in 2-3 sentences. Be concise and action-oriented.\n\n${threadText.slice(0, 8000)}`,
      },
    ],
  });

  const textBlock = response.content.find((b) => b.type === "text");
  return textBlock?.type === "text" ? textBlock.text.trim() : "";
}
