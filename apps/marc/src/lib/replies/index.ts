import Anthropic from "@anthropic-ai/sdk";
import type { ReplyBrief } from "@/lib/types";
import { getVoiceProfile, voiceProfileToMarkdown, getSenderProfile } from "@/lib/bolton";
import { getThreadMessages } from "@/lib/gmail/sync";
import { summarizeThread } from "@/lib/triage";
import type { emailMessages } from "@/lib/db/schema";

function getAnthropic() {
  return new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
}

export async function draftReply(
  message: typeof emailMessages.$inferSelect,
  options: {
    desiredOutcome?: string;
    useWilliam?: boolean;
    isPro?: boolean;
  } = {}
): Promise<ReplyBrief> {
  const isPro = options.isPro ?? false;
  const threadMessages = await getThreadMessages(message.threadId);
  const threadSummary = await summarizeThread(threadMessages);
  const senderProfile = isPro ? await getSenderProfile(message.senderEmail) : null;
  const voiceProfile = isPro ? await getVoiceProfile() : null;

  const sensitivityLevel = detectSensitivity(message, senderProfile?.relationshipType);
  const useWilliam =
    options.useWilliam ??
    (sensitivityLevel === "reputation-relevant" ||
      sensitivityLevel === "urgent" ||
      !voiceProfile);

  const toneInstruction = senderProfile?.preferredTone
    ? `${senderProfile.preferredTone}, appropriate for ${senderProfile.relationshipType}`
    : "Warm, concise, helpful, not too formal";

  const systemParts = [
    "You are Marc, drafting an email reply as a sharp executive assistant.",
    "Write copy-ready reply text only — no preamble.",
    `Tone: ${toneInstruction}`,
    `Desired outcome: ${options.desiredOutcome ?? "Address the sender's request clearly and move the thread forward"}`,
    `Sensitivity: ${sensitivityLevel}`,
  ];

  if (voiceProfile && isPro && !useWilliam) {
    systemParts.push(`\n--- WILLIAM VOICE PROFILE (from Bolton) ---\n${voiceProfileToMarkdown(voiceProfile)}`);
    systemParts.push(`Email-specific rules: ${voiceProfile.platform_rules.email ?? "Professional but personal"}`);
  }

  if (senderProfile) {
    systemParts.push(
      `\nSender: ${senderProfile.senderName ?? message.senderEmail}, relationship: ${senderProfile.relationshipType}`,
      senderProfile.sensitivityNotes ? `Notes: ${senderProfile.sensitivityNotes}` : ""
    );
  }

  const response = await getAnthropic().messages.create({
    model: "claude-sonnet-4-20250514",
    max_tokens: 2048,
    system: systemParts.filter(Boolean).join("\n"),
    messages: [
      {
        role: "user",
        content: `Thread summary:\n${threadSummary}\n\nLatest message to reply to:\nFrom: ${message.senderEmail}\nSubject: ${message.subject}\n${message.body?.slice(0, 3000) ?? message.snippet}`,
      },
    ],
  });

  const textBlock = response.content.find((b) => b.type === "text");
  const draftReplyText = textBlock?.type === "text" ? textBlock.text.trim() : "";

  return {
    sender: `${message.senderName ?? message.senderEmail} / ${message.senderEmail}`,
    relationship_type: senderProfile?.relationshipType ?? "unknown",
    thread_summary: threadSummary,
    desired_outcome:
      options.desiredOutcome ?? "Address the sender's request and move the thread forward",
    sensitivity_level: sensitivityLevel,
    tone_instruction: toneInstruction,
    draft_reply: draftReplyText,
    use_william: useWilliam,
  };
}

function detectSensitivity(
  message: typeof emailMessages.$inferSelect,
  relationshipType?: string | null
): ReplyBrief["sensitivity_level"] {
  const text = `${message.subject} ${message.body ?? ""}`.toLowerCase();
  if (
    text.includes("legal") ||
    text.includes("confidential") ||
    text.includes("reputation") ||
    relationshipType === "executive" ||
    relationshipType === "client"
  ) {
    return "reputation-relevant";
  }
  if (text.includes("urgent") || text.includes("asap") || text.includes("immediately")) {
    return "urgent";
  }
  if (text.includes("contract") || text.includes("billing") || text.includes("invoice")) {
    return "sensitive";
  }
  return "normal";
}

export function buildWilliamHandoff(brief: ReplyBrief): Record<string, unknown> {
  return {
    thread_summary: brief.thread_summary,
    sender_memory: brief.sender,
    desired_outcome: brief.desired_outcome,
    tone: brief.tone_instruction,
    constraints: `Sensitivity: ${brief.sensitivity_level}. Draft provided as starting point.`,
    draft_reply: brief.draft_reply,
  };
}
