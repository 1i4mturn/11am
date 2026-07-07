import Anthropic from "@anthropic-ai/sdk";
import type { Platform, VoiceProfile } from "@/lib/types/voice-profile";
import type { GeorgeNumbersSummary, ConnerStrategySummary } from "@/lib/types/agent-summaries";
import {
  formatConnerForPrompt,
  formatGeorgeForPrompt,
} from "@/lib/types/agent-summaries";
import { voiceProfileToMarkdown } from "@/lib/bolton";
import { isPro } from "@/lib/config";

function getAnthropic() {
  return new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
}

const PLATFORM_GUIDANCE: Record<Platform, string> = {
  email: "Write a complete, send-ready email with subject line if appropriate. Professional but personal.",
  linkedin:
    "Write a LinkedIn post optimised for engagement. Hook in the first line. No hashtag spam.",
  blog: "Write polished blog copy with clear structure. Headings if appropriate.",
  slack: "Write concise Slack message. Conversational, direct, no unnecessary formality.",
  announcement: "Write a clear announcement. Lead with the news, then context.",
  other: "Write copy-ready text appropriate to the request.",
};

export interface GenerateContext {
  prompt: string;
  platform: Platform;
  context?: string;
  voiceProfile?: VoiceProfile | null;
  fewShotExamples?: Array<{ content: string; similarity: number }>;
  george?: GeorgeNumbersSummary | null;
  conner?: ConnerStrategySummary | null;
  tier?: string;
}

function buildSystemPrompt(options: GenerateContext): string {
  const {
    prompt: _p,
    platform,
    voiceProfile,
    fewShotExamples = [],
    george,
    conner,
    tier = "pro",
  } = options;
  const pro = isPro(tier);

  const avgSimilarity =
    fewShotExamples.length > 0
      ? fewShotExamples.reduce((s, e) => s + e.similarity, 0) / fewShotExamples.length
      : 0;

  const systemParts: string[] = [
    `You are William, the writing agent for 11am. You produce copy-ready text in the user's authentic voice — warm, clear, human, never generic AI output.`,
    `\nPlatform: ${platform}\n${PLATFORM_GUIDANCE[platform]}`,
  ];

  if (voiceProfile && pro) {
    systemParts.push(`\n--- VOICE PROFILE ---\n${voiceProfileToMarkdown(voiceProfile)}`);
  } else if (!pro) {
    systemParts.push(
      `\nWrite in a warm, clear, conversational tone. Avoid corporate filler and obvious AI phrasing.`
    );
  }

  if (fewShotExamples.length > 0 && pro) {
    systemParts.push(
      `\n--- WRITING EXAMPLES (match this style) ---\n${fewShotExamples
        .map((e, i) => `Example ${i + 1}:\n${e.content}`)
        .join("\n\n")}`
    );
  }

  if (george || conner) {
    systemParts.push(`\n--- BUSINESS CONTEXT (from Bolton) ---`);
    if (george) systemParts.push(`George (Finance): ${formatGeorgeForPrompt(george)}`);
    if (conner) systemParts.push(`Conner (Strategy): ${formatConnerForPrompt(conner)}`);
  }

  systemParts.push(
    `\nReturn ONLY the finished copy. No preamble, no "Here's your draft", no markdown fences unless the platform calls for it.`
  );

  return systemParts.join("\n");
}

function buildUserContent(options: GenerateContext): string {
  const { prompt, context } = options;
  return context ? `Context/notes:\n${context}\n\nRequest:\n${prompt}` : prompt;
}

function buildHandoff(
  output: string,
  platform: Platform,
  voiceProfile?: VoiceProfile | null
) {
  const toneNotes = voiceProfile
    ? voiceProfile.tone_adjectives.slice(0, 3).join(", ")
    : "Warm, clear, conversational";

  return {
    copy: output,
    platform: platform.charAt(0).toUpperCase() + platform.slice(1),
    format: platform === "linkedin" ? "single image post" : "text",
    tone_notes: toneNotes,
    visual_direction: "Clean, authentic, human — editorial white space, no stock-photo energy",
  };
}

export function computeConfidence(
  fewShotExamples: Array<{ similarity: number }>,
  tier: string
): number {
  const pro = isPro(tier);
  const avgSimilarity =
    fewShotExamples.length > 0
      ? fewShotExamples.reduce((s, e) => s + e.similarity, 0) / fewShotExamples.length
      : 0;
  return pro ? Math.min(95, Math.round(50 + avgSimilarity * 45)) : 40;
}

export async function* streamGenerateCopy(options: GenerateContext): AsyncGenerator<string> {
  const stream = await getAnthropic().messages.stream({
    model: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-20250514",
    max_tokens: 4096,
    system: buildSystemPrompt(options),
    messages: [{ role: "user", content: buildUserContent(options) }],
  });

  for await (const event of stream) {
    if (
      event.type === "content_block_delta" &&
      event.delta.type === "text_delta" &&
      event.delta.text
    ) {
      yield event.delta.text;
    }
  }
}

export async function generateCopyComplete(options: GenerateContext): Promise<{
  output: string;
  confidence: number;
  handoff: ReturnType<typeof buildHandoff>;
}> {
  let output = "";
  for await (const chunk of streamGenerateCopy(options)) {
    output += chunk;
  }
  output = output.trim();

  return {
    output,
    confidence: computeConfidence(options.fewShotExamples ?? [], options.tier ?? "pro"),
    handoff: buildHandoff(output, options.platform, options.voiceProfile),
  };
}

/** @deprecated use streamGenerateCopy — kept for non-stream callers */
export async function generateCopy(options: GenerateContext & { isFreeTier?: boolean }) {
  const result = await generateCopyComplete({
    ...options,
    tier: options.isFreeTier ? "free" : options.tier ?? "pro",
  });
  return result;
}
