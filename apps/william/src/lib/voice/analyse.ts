import Anthropic from "@anthropic-ai/sdk";
import { VoiceProfileSchema, type VoiceProfile } from "@/lib/types/voice-profile";
import { voiceProfileToMarkdown } from "@/lib/bolton";

function getAnthropic() {
  return new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
}

const VOICE_ANALYSIS_PROMPT = `You are William, a writing voice analyst for 11am. Analyse the provided writing corpus and produce a structured voice profile.

Return ONLY valid JSON matching this schema:
{
  "tone_adjectives": ["array of 5-8 tone descriptors"],
  "sentence_rhythm": "description of typical sentence length, pacing, and structure patterns",
  "vocabulary_preferences": ["array of characteristic word choices and phrases they favour"],
  "avoid_phrases": ["array of phrases this writer would never use - corporate filler, AI-isms, etc."],
  "platform_rules": {
    "email": "how they write emails specifically",
    "linkedin": "how they write LinkedIn posts",
    "blog": "how they write blog content",
    "slack": "how they write Slack messages",
    "announcement": "how they write announcements"
  },
  "argument_style": "how they build arguments - direct, narrative, data-led, etc."
}

Be specific and evidence-based. Infer from the actual writing, not generic assumptions.`;

export async function analyseCorpus(corpus: string): Promise<VoiceProfile> {
  const response = await getAnthropic().messages.create({
    model: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-20250514",
    max_tokens: 4096,
    messages: [
      {
        role: "user",
        content: `${VOICE_ANALYSIS_PROMPT}\n\n---\nWRITING CORPUS:\n${corpus.slice(0, 50000)}`,
      },
    ],
  });

  const textBlock = response.content.find((b) => b.type === "text");
  if (!textBlock || textBlock.type !== "text") {
    throw new Error("No text response from voice analysis");
  }

  const jsonMatch = textBlock.text.match(/\{[\s\S]*\}/);
  if (!jsonMatch) throw new Error("Could not parse voice profile JSON");

  const parsed = JSON.parse(jsonMatch[0]);
  return VoiceProfileSchema.parse(parsed);
}

export async function updateProfileFromEdits(
  currentProfile: VoiceProfile,
  originalOutput: string,
  editedOutput: string
): Promise<VoiceProfile> {
  const response = await getAnthropic().messages.create({
    model: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-20250514",
    max_tokens: 4096,
    messages: [
      {
        role: "user",
        content: `You maintain a voice profile for a writer. The user edited William's output. Update the profile to reflect what the edit teaches us about their preferences.

Current profile:
${voiceProfileToMarkdown(currentProfile)}

Original output:
${originalOutput}

User's edited version:
${editedOutput}

Return ONLY the updated profile as valid JSON with the same schema fields.`,
      },
    ],
  });

  const textBlock = response.content.find((b) => b.type === "text");
  if (!textBlock || textBlock.type !== "text") {
    return currentProfile;
  }

  const jsonMatch = textBlock.text.match(/\{[\s\S]*\}/);
  if (!jsonMatch) return currentProfile;

  try {
    return VoiceProfileSchema.parse(JSON.parse(jsonMatch[0]));
  } catch {
    return currentProfile;
  }
}

export function detectVoiceDrift(
  profile: VoiceProfile,
  newOutput: string
): { drifted: boolean; notes: string } {
  const avoidHits = profile.avoid_phrases.filter((phrase) =>
    newOutput.toLowerCase().includes(phrase.toLowerCase())
  );

  if (avoidHits.length > 0) {
    return {
      drifted: true,
      notes: `Output contains avoided phrases: ${avoidHits.join(", ")}`,
    };
  }

  return { drifted: false, notes: "" };
}
