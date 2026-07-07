import { embedText } from "@/lib/voice/embeddings";
import {
  getVoiceProfile,
  retrieveSimilarSamples,
  getLatestAgentSummaries,
} from "@/lib/bolton";
import { getUser } from "@/lib/tiers";
import { isPro } from "@/lib/config";
import type { Platform, VoiceProfile } from "@/lib/types/voice-profile";
import {
  parseConnerSummary,
  parseGeorgeSummary,
  type ConnerStrategySummary,
  type GeorgeNumbersSummary,
} from "@/lib/types/agent-summaries";
import type { GenerateContext } from "@/lib/generation";

export async function prepareGenerationContext(
  userId: string,
  body: {
    prompt: string;
    platform: Platform;
    context?: string;
    includeBusinessContext?: boolean;
  }
): Promise<{
  ctx: GenerateContext;
  tier: string;
}> {
  const user = await getUser(userId);
  const pro = isPro(user.tier);

  let voiceProfile: VoiceProfile | null = null;
  let fewShotExamples: Array<{ content: string; similarity: number }> = [];

  if (pro) {
    const profile = await getVoiceProfile(userId);
    if (profile) {
      voiceProfile = {
        tone_adjectives: profile.toneAdjectives as string[],
        sentence_rhythm: profile.sentenceRhythm,
        vocabulary_preferences: profile.vocabularyPreferences as string[],
        avoid_phrases: profile.avoidPhrases as string[],
        platform_rules: profile.platformRules as Record<string, string>,
        argument_style: profile.argumentStyle,
      };
    }

    const queryEmbedding = await embedText(`${body.platform}: ${body.prompt}`);
    const samples = await retrieveSimilarSamples(queryEmbedding, 5, userId);
    fewShotExamples = samples.map((s) => ({
      content: s.content,
      similarity: Number(s.similarity),
    }));
  }

  let george: GeorgeNumbersSummary | null = null;
  let conner: ConnerStrategySummary | null = null;

  if (body.includeBusinessContext && pro) {
    const summaries = await getLatestAgentSummaries(userId);
    george = parseGeorgeSummary(summaries.george?.summary);
    conner = parseConnerSummary(summaries.conner?.summary);
  }

  return {
    tier: user.tier,
    ctx: {
      prompt: body.prompt,
      platform: body.platform,
      context: body.context,
      voiceProfile,
      fewShotExamples,
      george,
      conner,
      tier: user.tier,
    },
  };
}
