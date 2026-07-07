import Anthropic from "@anthropic-ai/sdk";
import type { CaptureCandidate, CaptureAction } from "@/lib/types";

function getAnthropic() {
  return new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
}

const SECRET_PATTERNS = [
  /password\s*[:=]/i,
  /api[_-]?key\s*[:=]/i,
  /secret\s*[:=]/i,
  /Bearer\s+[A-Za-z0-9._-]{20,}/,
  /sk-[A-Za-z0-9]{20,}/,
];

export function containsSecrets(text: string): boolean {
  return SECRET_PATTERNS.some((p) => p.test(text));
}

export async function classifyCapture(
  candidate: CaptureCandidate,
  existing: Array<{ id: string; title: string }> = []
): Promise<{ action: CaptureAction; reason: string; similarTo?: string }> {
  if (containsSecrets(candidate.summary + (candidate.full_content ?? ""))) {
    return { action: "skip", reason: "Contains potential secrets or credentials" };
  }

  if (candidate.summary.length < 20 && !candidate.full_content) {
    return { action: "skip", reason: "Too short to be reusable memory" };
  }

  const duplicate = existing.find(
    (e) => e.title.toLowerCase() === candidate.title.toLowerCase()
  );
  if (duplicate) {
    return {
      action: "update",
      reason: "Title matches existing entry",
      similarTo: duplicate.id,
    };
  }

  const existingList = existing
    .slice(0, 20)
    .map((e) => `${e.id}: ${e.title}`)
    .join("\n");

  const response = await getAnthropic().messages.create({
    model: "claude-sonnet-4-20250514",
    max_tokens: 512,
    messages: [
      {
        role: "user",
        content: `Classify this memory candidate. Return ONLY JSON:
{"action": "save|update|supersede|link|skip|ask_user", "reason": "brief explanation", "similar_to": "uuid of related entry or null"}

Candidate:
Agent: ${candidate.source_agent}
Type: ${candidate.entry_type}
Title: ${candidate.title}
Summary: ${candidate.summary}

Existing entries (id: title):
${existingList || "none"}

Rules:
- save if new reusable context
- update if same topic, refined info (similar_to = entry to update)
- supersede if new info replaces old (similar_to = entry to supersede) — never delete
- link if related but distinct (similar_to = entry to link)
- skip if filler, duplicate, temporary
- ask_user if ambiguous or high-stakes`,
      },
    ],
  });

  const textBlock = response.content.find((b) => b.type === "text");
  const text = textBlock?.type === "text" ? textBlock.text : "{}";
  const jsonMatch = text.match(/\{[\s\S]*\}/);
  if (!jsonMatch) return { action: "save", reason: "Default save" };

  const parsed = JSON.parse(jsonMatch[0]);
  return {
    action: parsed.action ?? "save",
    reason: parsed.reason ?? "",
    similarTo: parsed.similar_to ?? undefined,
  };
}
