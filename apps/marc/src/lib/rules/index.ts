import Anthropic from "@anthropic-ai/sdk";
import type { InboxRule } from "@/lib/types";
import { saveInboxRule } from "@/lib/bolton";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { emailMessages } from "@/lib/db/schema";

function getAnthropic() {
  return new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
}

export async function proposeRuleFromNaturalLanguage(
  instruction: string,
  userId = "default"
): Promise<InboxRule & { id: string; preview_matches: number; sample_subjects: string[] }> {
  const response = await getAnthropic().messages.create({
    model: "claude-sonnet-4-20250514",
    max_tokens: 1024,
    messages: [
      {
        role: "user",
        content: `Convert this inbox rule instruction into structured JSON:
{"rule_name": "", "trigger": "sender/domain/keyword/label pattern", "conditions": [], "actions": [], "exceptions": [], "created_by": "Marc", "status": "pending"}

Instruction: "${instruction}"

Include exceptions for billing, security, legal, and account notices.
Return ONLY JSON.`,
      },
    ],
  });

  const textBlock = response.content.find((b) => b.type === "text");
  const text = textBlock?.type === "text" ? textBlock.text : "{}";
  const jsonMatch = text.match(/\{[\s\S]*\}/);
  const rule = jsonMatch ? JSON.parse(jsonMatch[0]) : {};

  const messages = await db
    .select()
    .from(emailMessages)
    .where(eq(emailMessages.userId, userId))
    .limit(200);

  const trigger = (rule.trigger ?? "").toLowerCase();
  const keywords = (rule.conditions as string[]) ?? [];

  const matches = messages.filter((m) => {
    const text = `${m.senderEmail} ${m.subject} ${m.body ?? ""}`.toLowerCase();
    if (trigger.includes("@") && m.senderEmail.includes(trigger.replace("sender:", ""))) return true;
    return keywords.some((k) => text.includes(k.toLowerCase().replace(/contains /i, "")));
  });

  const inboxRule: InboxRule = {
    rule_name: rule.rule_name ?? "Custom rule",
    trigger: rule.trigger ?? instruction,
    conditions: rule.conditions ?? [],
    actions: rule.actions ?? [],
    exceptions: rule.exceptions ?? [],
    created_by: "Marc",
    status: "pending",
  };

  const saved = await saveInboxRule(inboxRule, userId);

  return {
    ...inboxRule,
    id: saved.id,
    preview_matches: matches.length,
    sample_subjects: matches.slice(0, 5).map((m) => m.subject),
  };
}
